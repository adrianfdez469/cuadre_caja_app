# TODO — Fixes pendientes

Hallazgos de una revisión de código enfocada en el motor de sincronización, la cola offline,
las migraciones de BD y la autenticación (las zonas de mayor riesgo para un POS offline-first).
Ordenados por impacto. **Ninguno tiene cambios aplicados todavía.**

---

## Bugs confirmados

### 1. ✅ HECHO — `crearVenta` reescribe el stock de **todos** los productos en **cada** venta — rendimiento + atomicidad
**Archivo:** `lib/services/sync_service.dart` → `crearVenta`

> **Corregido:** la lógica de existencias se extrajo a `lib/core/utils/stock_calculator.dart`
> (`StockCalculator.existenciasTrasVenta`), que devuelve **solo** los productos tocados. La escritura
> ahora usa `ProductosLocalDataSource.updateExistencias`, un único `db.transaction` + batch (atómico).
> Cubierto por `test/core/utils/stock_calculator_test.dart`.

```dart
final existencias = {for (final p in productos) p.id: p.existencia}; // TODOS los productos
...
for (final e in existencias.entries) {
  await productosLocal.updateExistencia(e.key, e.value); // un UPDATE await por producto
}
```

El mapa `existencias` se inicializa con **todos** los productos de la tienda, así que el loop final
emite un `UPDATE` separado por producto por venta — incluso para los que no se tocaron (reescribe
el mismo valor). Con ~2.000 productos son ~2.000 escrituras secuenciales con `await` en el hilo de
UI por una sola venta. Además **no está envuelto en una transacción**, por lo que un crash a mitad
del loop deja el stock parcialmente actualizado.

**Fix sugerido:** iterar solo los productos que realmente cambiaron (items del carrito + padres/hijos
de la desagregación) y envolverlos en `db.transaction` / batch.
**Prioridad: ALTA** (está en el hot path de cada venta y empeora al crecer el catálogo).

---

### 2. ✅ HECHO — Ventana de carrera que permite doble-post de la misma venta
**Archivo:** `lib/services/sync_service.dart` → `crearVenta` + `_syncPendingVentas`

> **Corregido:** cuando hay conexión, `crearVenta` persiste la venta directamente en estado `syncing`
> **antes** del trabajo de stock. Como `getVentasPendientes()` excluye `syncing`, el `_syncTimer` ya no
> puede tomar la venta mientras `crearVenta` sigue trabajando. Las ventas offline siguen en `pending`.

`getVentasPendientes()` filtra solo a `pending`/`error` (excluye `syncing` correctamente). Pero en
`crearVenta` la venta se guarda como `pending` **primero**, luego corre el largo loop de stock
(bug #1), y **solo después** se marca `syncing`. Si el `_syncTimer` (cada 30s) dispara durante esa
ventana, `_syncPendingVentas` toma la venta aún `pending` y empieza a postearla, mientras `crearVenta`
lanza además su propio `_syncSingleVenta` sin await. Dos posts concurrentes de la misma venta.
El bug #1 agranda esta ventana.

Actualmente solo lo mitiga la idempotencia del servidor (`result.duplicado`).

**Fix sugerido:** marcar `syncing` **antes** del trabajo de stock, no después.
**Prioridad: ALTA**

---

### 3. ✅ HECHO — `_ensureAuthenticated()` es prácticamente un no-op
**Archivo:** `lib/services/sync_service.dart` → `_ensureAuthenticated`

> **Corregido:** `_ensureAuthenticated` ahora hace un probe real contra el servidor.
> Como no existe `/health`, se usa `/auth/refresh` como validación: `ApiClient.refreshToken()`
> devuelve un enum `AuthResult { ok, authRejected, networkError }` que distingue un rechazo
> definitivo de sesión (401/403) de un fallo de red. Ante `ok` renueva el token; ante
> `authRejected` intenta `reLogin()` con credenciales guardadas; solo ante un rechazo definitivo
> dispara `onAuthRequired` (es su único dueño). Un `networkError` **no** expulsa al usuario ni
> sincroniza: se reintenta en el próximo ciclo. Este chequeo gatea **ambos** disparadores de
> sync (reconexión y timer de 30s), así que si el token no se puede refrescar el sync no se intenta.
> `tryReLogin()` se mantiene devolviendo `bool` por compatibilidad.

```dart
Future<bool> _ensureAuthenticated() async {
  final token = await storageService.getToken();
  if (token == null) { onAuthRequired?.call(true); return false; }
  try {
    final user = await storageService.getUser();
    if (user == null) return false;
    return true;               // nunca hace una petición
  } catch (_) {
    final relogged = await apiClient.tryReLogin(); // código muerto
    ...
  }
}
```

El comentario dice "intentar una petición simple para verificar el token", pero no se hace ninguna
petición — solo verifica que exista un token/usuario local. Siempre devuelve `true` para un usuario
logueado, así que `tryReLogin()` es inalcanzable y `forceSyncVentas`/reconexión nunca validan
realmente el token (dependen por completo del interceptor 401).

**Fix sugerido:** hacer un GET liviano a un endpoint (p. ej. `/health` o perfil) o eliminar la lógica
engañosa.
**Prioridad: MEDIA**

---

### 4. ✅ HECHO — `clearAllData()` deja `ventas_servidor_cache` — fuga entre tiendas/sesiones
**Archivo:** `lib/data/datasources/local/database_helper.dart` → `clearAllData`

> **Corregido:** se agregó `await db.delete('ventas_servidor_cache');` a `clearAllData`.
> `ventas_pendientes` se sigue conservando (no se pierden ventas sin sincronizar).

```dart
await db.delete('productos');
await db.delete('periodo_cache');
await db.delete('transfer_destinations');
await db.delete('carritos');
await db.delete('multimoneda_cache');
// ventas_pendientes NO se borra — correcto
// pero ventas_servidor_cache TAMPOCO se borra
```

Al cerrar sesión o cambiar de tienda, el cache de ventas-servidor de la tienda anterior sobrevive y
puede aparecer offline bajo otro contexto de `tiendaId`. Está keyeado por `tiendaId`+`periodoId`, así
que el radio de impacto es pequeño, pero es una fuga que nunca se purga.

**Fix sugerido:** agregar `await db.delete('ventas_servidor_cache');` a `clearAllData`.
**Prioridad: MEDIA-BAJA**

---

## Preocupaciones de diseño

### 5. ✅ HECHO — `connectivity_plus` ≠ alcanzabilidad real de internet
**Archivo:** `lib/services/sync_service.dart` → `_mapConnectivity`

> **Corregido:** dos frentes. (1) Timeouts bajados de 30s → 8s (`api_constants.dart`) para acotar
> el peor caso de bloqueo. (2) Probe de alcanzabilidad `ApiClient.isServerReachable()`: como no
> existe `/health`, hace un GET corto (3s) a la base de la API — cualquier respuesta HTTP (incl.
> 404/401) cuenta como alcanzable; solo timeout/error de conexión = no alcanzable. `SyncService`
> lo cachea 15s (`_isServerReachable`) e invalida al cambiar la red, y las lecturas
> (`loadProductos`, `loadPeriodoActual`, `loadTransferDestinations`, `loadMultimonedaConfig`,
> `loadVentas`) van directo a cache cuando el servidor no responde.
> **Caveat:** un portal cautivo que responde 200 con su propia página puede dar un falso positivo
> en el probe; ahí el timeout reducido es la red de seguridad.

Mapea "hay alguna interfaz de red" → `online`. Con Wi-Fi de portal cautivo o sin uplink real,
`isOnline` es `true`, así que las lecturas van API-first y bloquean hasta 30s (`receiveTimeout`) por
llamada antes de caer a cache — justo cuando el cajero necesita que el POS sea instantáneo.

**Fix sugerido:** un probe rápido de alcanzabilidad (ping con timeout corto a `/health`) antes de
confiar en `isOnline`, o reducir bastante el timeout de lectura.
**Prioridad: MEDIA**

---

### 6. ✅ HECHO — El refresco de inventario puede sobrescribir el stock de *otras* ventas sin sincronizar
**Archivo:** `lib/services/sync_service.dart` → `_refreshInventarioFromServer` / `crearVenta`

> **Corregido por reconciliación** (no por "sync-todo-antes"). Tras cachear el snapshot del
> servidor, `loadProductos` re-aplica encima los decrementos de las ventas aún no sincronizadas
> de la tienda: `existencia_local = snapshot_servidor − Σ(decrementos no sincronizados)`. Lógica
> pura en `StockCalculator.replayVentas` (encadena ventas en orden, respeta desagregación de
> fracción) + `_reconciliarInventario` en `SyncService`. **No clampea a 0**: vender en negativo
> offline sigue permitido (es una feature); las dos exigencias no chocan porque restar nunca borra
> los decrementos de otras pendientes. Centralizado en `loadProductos`, así cubre también refrescos
> disparados por la UI, no solo el path de venta. Cubierto por tests de `replayVentas`.

`_refreshInventarioFromServer` → `loadProductos` sobrescribe la `existencia` local con los valores del
servidor. En el path online de `crearVenta` solo se sincroniza *esta* venta antes del refresco, así que
si hay **otras** ventas offline pendientes, sus decrementos optimistas se pisan con el snapshot del
servidor (stock inflado) hasta que esas ventas se sincronicen. `fullSync` ordena esto bien (todas las
pendientes → luego inventario); el path de venta única no.

**Fix sugerido:** en `crearVenta` sincronizar todas las pendientes antes de refrescar inventario, o no
refrescar inventario si quedan pendientes.
**Prioridad: MEDIA**

---

## Menores — ✅ TODOS HECHOS

- ✅ **`_syncSingleVenta` usaba el parámetro obsoleto** `venta.syncAttempts + 1` en el catch.
  **Corregido:** `toSync` se declara fuera del `try` y el catch incrementa sobre el valor releído
  (`toSync.syncAttempts + 1`). `lib/services/sync_service.dart`.

- ✅ **401 concurrentes solo recuperaban una petición** (flag `_isRefreshing`).
  **Corregido:** se reemplazó por un `Completer<bool>` compartido (`_refreshTokenShared`): la primera
  petición que recibe 401 dispara el refresh y las demás esperan el mismo resultado y reintentan.
  Se agregó la marca `extra['__authRetried']` para evitar bucles si el reintento vuelve a dar 401.
  `lib/core/network/api_client.dart`.

- ✅ **Migración `oldVersion <= 1` dropeaba `ventas_pendientes`**.
  **Corregido:** ya no se destruye. Se aparta (`RENAME TO ..._old`), se recrea el esquema actual vía
  `_onCreate` (ahora idempotente con `CREATE TABLE/INDEX IF NOT EXISTS`) y se copian las columnas
  comunes (`_copyCommonColumns`), preservando las ventas sin sincronizar.
  `lib/data/datasources/local/database_helper.dart`.

- ✅ **`avoid_print` en release**.
  **Corregido:** nuevo `lib/core/utils/app_logger.dart` con `logDebug()` guardado por `kDebugMode`
  (no emite en release). Todos los `print(...)` de `lib/` se migraron a `logDebug(...)`. El analyzer
  ya no reporta `avoid_print`.

---

## Orden recomendado de ataque
1. ~~**#1** (hot path de cada venta, empeora con catálogos grandes)~~ ✅ HECHO
2. ~~**#2** (doble-post, relacionado con #1)~~ ✅ HECHO
3. ~~**#3** (lógica de auth-recovery muerta y engañosa)~~ ✅ HECHO
4. ~~**#4**, **#5**, **#6**~~ ✅ HECHO
5. ~~Menores~~ ✅ HECHO — **todos los hallazgos de la revisión están resueltos.**
