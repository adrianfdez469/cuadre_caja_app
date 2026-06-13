# Contrato API — App Flutter Cuadre de Caja

Documento de referencia para **cruzar con la API del backend** y detectar breaking changes.

> **Uso recomendado con IA del backend:**
> "Compara este contrato con la API actual. Lista cada breaking change que rompa la app móvil: endpoint, campo, código HTTP, mensaje de error y archivo Dart afectado."

Documentación ampliada: [API_APP_DOCUMENTATION.md](API_APP_DOCUMENTATION.md) · Respuestas POST venta: [API_APP_VENTA_POST_RESPUESTAS.md](API_APP_VENTA_POST_RESPUESTAS.md)

---

## Configuración del cliente

| Concepto | Valor en la app |
|----------|-----------------|
| Base URL | `{SERVER}/api/app` (`lib/core/constants/api_constants.dart`) |
| Auth | `Authorization: Bearer <token>` en todas las peticiones excepto login |
| Content-Type | `application/json` |
| Timeout | 30 s connect / 30 s receive |
| Cliente HTTP | Dio (`lib/core/network/api_client.dart`) |
| Refresh automático | Ante `401`, reintenta con `POST /auth/refresh`; si falla, re-login con credenciales guardadas |

---

## Resumen de endpoints consumidos

| # | Método | Ruta | ¿Activo? | Datasource | Modelo |
|---|--------|------|----------|------------|--------|
| 1 | POST | `/auth/login` | ✅ | `auth_remote_datasource.dart` | `usuario_model.dart` |
| 2 | POST | `/auth/refresh` | ✅ | `auth_remote_datasource.dart` + `api_client.dart` | `usuario_model.dart` |
| 3 | POST | `/auth/cambiar-tienda` | ✅ | `auth_remote_datasource.dart` | `usuario_model.dart` |
| 4 | GET | `/productos/{tiendaId}` | ✅ | `productos_remote_datasource.dart` | `producto_model.dart` |
| 5 | POST | `/productos/agregar-codigo/{productoId}` | ✅ | `productos_remote_datasource.dart` | `producto_model.dart` |
| 6 | GET | `/periodo/{tiendaId}/actual` | ✅ | `periodos_remote_datasource.dart` | `periodo_model.dart` |
| 7 | POST | `/periodo/{tiendaId}/abrir` | ✅ | `periodos_remote_datasource.dart` | `periodo_model.dart` |
| 8 | POST | `/venta/{tiendaId}/{periodoId}` | ✅ | `ventas_remote_datasource.dart` | `venta_model.dart` |
| 9 | GET | `/venta/{tiendaId}/{periodoId}` | ✅ | `ventas_remote_datasource.dart` | `venta_model.dart` |
| 10 | DELETE | `/venta/{tiendaId}/{periodoId}/{ventaId}` | ✅ | `ventas_remote_datasource.dart` | — |
| 11 | GET | `/transfer-destinations/{tiendaId}` | ✅ | `transfer_destinations_remote_datasource.dart` | `transfer_destination_model.dart` |
| 12 | GET | `/resumen-dia/{tiendaId}` | ✅ | `resumen_dia_remote_datasource.dart` | `resumen_dia_model.dart` |
| — | GET | `/venta/{tiendaId}/{periodoId}/{ventaId}` | ⚠️ Definido, no usado en UI | `ventas_remote_datasource.dart` | `venta_model.dart` |
| — | POST | `/descuentos/preview` | ❌ Solo constante, sin uso | — | — |

**Orquestación:** `lib/services/sync_service.dart` · **DI:** `lib/core/di/injection.dart`

---

## 1. Autenticación

### POST `/auth/login`

**Envía:**
```json
{ "usuario": "string", "password": "string" }
```

**Espera (200, `success: true`):**
```json
{
  "success": true,
  "token": "string",
  "user": {
    "id": "uuid",
    "nombre": "string",
    "usuario": "string",
    "rol": "string | null",
    "negocio": { "id", "nombre", "userlimit", "limitTime", "locallimit", "productlimit" },
    "localActual": { "id", "nombre", "negocioId", "tipo" },
    "locales": [{ "id", "nombre", "negocioId", "tipo" }],
    "permisos": ["string"] | "string"
  }
}
```

> `permisos` se parsea como **array** o **string** (un solo permiso).

**Errores:** campo `error` en body → `Exception(error)`.

**Archivos:** `auth_remote_datasource.dart`, `usuario_model.dart`, `auth_provider.dart`, `secure_storage_service.dart`

---

### POST `/auth/refresh`

**Envía:** body vacío. Header `Authorization: Bearer <token>`.

**Espera:** misma forma que login (`success`, `token`, `user`).

**Archivos:** `auth_remote_datasource.dart`, `api_client.dart` (interceptor 401)

---

### POST `/auth/cambiar-tienda`

**Envía:**
```json
{ "tiendaId": "uuid" }
```

**Espera:** misma forma que login.

**Archivos:** `auth_remote_datasource.dart`, `auth_provider.dart`

---

## 2. Productos

### GET `/productos/{tiendaId}`

**Espera:** `{ "productos": [ ... ] }` (no valida `success`).

**Cada producto — campos parseados:**

| Campo | Tipo | Uso en app |
|-------|------|------------|
| `id` | string | ID ProductoTienda (ventas, stock) |
| `productoId` | string | ID producto base (asociar código) |
| `nombre` | string | UI |
| `descripcion` | string? | UI |
| `precio` | number | Ventas |
| `costo` | number | Cache |
| `existencia` | number | Stock offline |
| `permiteDecimal` | bool | Validación local |
| `categoria` | `{ id, nombre, color }` | Grid POS |
| `codigos` | `[{ id, codigo, tipo }]` | Escáner |
| `proveedor` | string? \| object | Filtros ventas |
| `esFraccion` | bool | Desagregación local |
| `fraccionDe` | `{ id, nombre }`? | Desagregación local |
| `unidadesPorFraccion` | int? | Desagregación local |

**Archivos:** `productos_remote_datasource.dart`, `producto_model.dart`, `sync_service.dart`, `productos_provider.dart`

---

### POST `/productos/agregar-codigo/{productoId}`

**Path:** `productoId` = ID del **producto base** (`producto.productoId`), no ProductoTienda.

**Envía:**
```json
{ "codigo": "string" }
```

**Espera (201):**
```json
{ "codigo": { "id": "uuid", "codigo": "string", "tipo": "string?" } }
```

**Errores:** campo `error` en body (400, 403, 404, 409).

**Permiso en app:** `operaciones.pos-venta.asociar_codigo` (o `SUPER_ADMIN`).

**Archivos:** `productos_remote_datasource.dart`, `asociar_codigo_sheet.dart`, `barcode_scanner_screen.dart`

---

## 3. Período de caja

### GET `/periodo/{tiendaId}/actual`

**Espera:**
```json
{
  "periodo": { "id", "tiendaId", "fechaInicio", "fechaFin", "totalVentas", "totalGanancia", "totalInversion", "totalTransferencia" } | null,
  "estaAbierto": bool
}
```

Si `periodo == null` → app interpreta "sin período".

**Archivos:** `periodos_remote_datasource.dart`, `periodo_model.dart`, `periodo_provider.dart`

---

### POST `/periodo/{tiendaId}/abrir`

**Envía:** body vacío.

**Espera:** `{ "success": true, "periodo": { ... }, "estaAbierto": true }`

**Errores:** `{ "error": "string" }` si `success != true`.

**Archivos:** `periodos_remote_datasource.dart`, `periodo_provider.dart`

---

## 4. Ventas (crítico — offline-first)

### POST `/venta/{tiendaId}/{periodoId}`

**Envía** (`VentaLocalModel.toApiJson` + `usuarioId` opcional al sincronizar):

```json
{
  "usuarioId": "uuid?",
  "syncId": "uuid",
  "createdAt": 1705401600000,
  "productos": [{ "productoTiendaId", "cantidad", "name?", "precio" }],
  "total": number,
  "totalcash": number,
  "totaltransfer": number,
  "transferDestinationId": "uuid? | null",
  "wasOffline": bool,
  "syncAttempts": int,
  "discountCodes": ["string"]?
}
```

**Espera éxito (200 idempotente / 201 creada):**
```json
{
  "success": true,
  "venta": {
    "id", "tiendaId", "usuarioId", "cierrePeriodoId",
    "total", "totalcash", "totaltransfer", "discountTotal",
    "syncId", "createdAt", "frontendCreatedAt?", "wasOffline",
    "usuario": { "nombre" }?,
    "productos": [{ "productoTiendaId", "cantidad", "precio"|"price", "name"? }]
  },
  "duplicado": bool
}
```

**Errores:** siempre campo `error: string` en body. La app **no parsea** `periodoActualId`; detecta conflictos por texto del mensaje.

**Mensajes de error que la app reconoce** (ver `sync_error_messages.dart`):

- `No autenticado`
- `Datos insuficientes para crear la venta: ...`
- `No existe un período abierto en la tienda`
- `No existe un período con el id proporcionado...`
- `La venta pertenece a un período cerrado o diferente al actual...`
- `Productos no encontrados: ...`
- `Cantidad decimal no permitida para algunos productos`
- `Vendes más unidades sueltas de las que lleva una caja...`
- `Existencia insuficiente para desagregar...`
- `Existencia insuficiente para ...`
- `Error al crear la venta`

> **Cambiar el texto de estos errores rompe la UX** (títulos amigables y detección de conflicto de período).

**Flujo app:** guarda local → descuenta stock → sincroniza en background cada 30 s.

**Archivos:** `ventas_remote_datasource.dart`, `venta_model.dart`, `sync_service.dart`, `ventas_provider.dart`, `sync_error_messages.dart`, `payment_modal.dart`, `ventas_list_screen.dart`

---

### GET `/venta/{tiendaId}/{periodoId}`

**Espera:** `{ "ventas": [ ... ] }`

**Campos de venta parseados:** `id`, `createdAt`, `total`, `totalcash`, `totaltransfer`, `discountTotal`, `tiendaId`, `usuarioId`, `cierrePeriodoId`, `syncId`, `wasOffline`, `frontendCreatedAt`, `usuario.nombre`, `productos[]`, `transferDestination` o `transferDestinationId`.

**NO parsea:** `appliedDiscounts`.

**Archivos:** `ventas_remote_datasource.dart`, `venta_model.dart`, `ventas_list_screen.dart`, `ventas_detail_screen.dart`

---

### DELETE `/venta/{tiendaId}/{periodoId}/{ventaId}`

**Espera:** 200 sin validar body específico.

**Archivos:** `ventas_remote_datasource.dart`, `sync_service.dart` (restaura stock local tras borrar)

---

## 5. Destinos de transferencia

### GET `/transfer-destinations/{tiendaId}`

**Espera:** `{ "destinos": [{ "id", "nombre", "descripcion", "default" }] }`

**Archivos:** `transfer_destinations_remote_datasource.dart`, `transfer_destination_model.dart`, `payment_modal.dart`

---

## 6. Resumen de día (Punto de partida)

### GET `/resumen-dia/{tiendaId}?cierreId={periodoId}&soloConMovimientos={bool}`

**Query params:**

| Param | Obligatorio | Default app |
|-------|-------------|-------------|
| `cierreId` | Sí | ID del período activo |
| `soloConMovimientos` | No | `true` (modo por defecto) |

**Espera (200):**
```json
{
  "totales": { "ventas", "entradas", "salidas" },
  "productos": [{
    "productoTiendaId", "productoId", "nombre", "proveedorNombre",
    "permiteDecimal", "categoriaId", "categoriaNombre", "categoriaColor",
    "tieneMovimientos", "ultimaModificacion",
    "cantidadInicial", "ventas", "entradas", "salidas", "cantidadFinal"
  }]
}
```

**Archivos:** `resumen_dia_remote_datasource.dart`, `resumen_dia_model.dart`, `punto_de_partida_screen.dart`

---

## Flujos críticos (no deben romperse)

```
Login → Cargar productos + período + destinos transferencia
      → Si período cerrado: abrir período
      → POS: ventas offline-first con syncId
      → Sync background cada 30s
      → Refresh token automático en 401
```

| Flujo | Dependencias API |
|-------|------------------|
| Arranque POS | login/refresh, GET productos, GET período, GET transfer-destinations |
| Venta offline | POST venta (idempotencia syncId), mensajes de error de período/stock |
| Historial ventas | GET ventas del período |
| Cancelar venta | DELETE venta |
| Escáner + código nuevo | POST agregar-codigo |
| Punto de partida | GET resumen-dia |
| Cambio de tienda | POST cambiar-tienda → recarga catálogo y período |

---

## Campos / endpoints que la app ignora hoy

Útil para saber qué puede cambiar sin impacto inmediato:

- `appliedDiscounts` en respuestas de venta
- `POST /descuentos/preview` (no implementado)
- `GET /venta/.../detalle` (datasource existe, UI no lo llama)
- Campo `total` en listado de productos
- `periodoActualId` en error 400 de venta (la app usa texto + PeriodoProvider)

---

## Checklist para la IA del backend

Al comparar con la API actual, reportar por cada breaking change:

```
[ ] Endpoint: método + ruta
[ ] Tipo de cambio: renombrado / eliminado / tipo distinto / nuevo obligatorio / código HTTP distinto
[ ] Antes (contrato app) vs Ahora (API backend)
[ ] Flujo afectado: (login | venta | sync | productos | período | ...)
[ ] Archivo(s) Dart a modificar
[ ] ¿Rompe offline/sync? (sí/no)
[ ] ¿Rompe detección de errores por texto? (sí/no)
```

---

## Versión

Generado desde el código Flutter en `cuadre_caja_app` v`1.0.7` (`pubspec.yaml`).
