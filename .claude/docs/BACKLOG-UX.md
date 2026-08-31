# Backlog UX / accesibilidad del POS

Hallazgos de la revisión del flujo de venta (catálogo → carrito → cuentas →
cobro → escáner → ventas) hecha el 2026-08-30 sobre la v2.0.1.

Se trabajan **de uno en uno**. Al cerrar uno, cambiar su estado a `HECHO` y
anotar el commit. Las referencias `archivo:línea` son de la v2.0.1 y pueden
haberse corrido: verificar antes de tocar.

Estados: `PENDIENTE` · `EN CURSO` · `HECHO` · `DESCARTADO`

---

## A. Bugs

### UX-01 · Anular una venta sincronizada no llega al servidor si no hay conexión
**Prioridad:** alta · **Estado:** HECHO

`deleteVentaAndRestoreStock` solo llamaba a `ventasRemote.cancelarVenta` si
`isOnline`, y si la llamada fallaba se tragaba el error con un `logDebug`. En
ambos casos seguía adelante: borraba la venta local, devolvía el stock y la UI
mostraba "Venta eliminada" en verde mientras el servidor seguía contando esa
venta. Un tercer caso, una venta sin fila local (otro cajero, otro
dispositivo), salía por un `return` temprano sin hacer nada — y también decía
"Venta eliminada".

**Cómo quedó:** anulación write-behind, como las ventas.

- `sync_service.anularVenta` sustituye a `deleteVentaAndRestoreStock`. El
  discriminador es `serverId`, no `syncState`: sin él la venta nunca llegó al
  servidor y se borra en el acto; con él se marca `cancelPending`, se devuelve
  el stock de forma optimista y el DELETE lo confirma el servidor.
- Estados nuevos en `SyncState`: `cancelPending` / `cancelling` / `cancelError`,
  drenados por `_syncPendingCancelaciones` en su propia cola (mezclarlos con
  `getVentasPendientes()` re-postearía la venta). Sin migración de BD.
- Un rechazo revierte el stock devuelto y deja la venta en `cancelError` con el
  motivo real del servidor, con "Reintentar" y "Descartar" en la lista.
- `_reconciliarInventario` pasa a ser
  `servidor − Σ(pendientes) + Σ(anulaciones pendientes)`: sin ese sumando, el
  refresco de inventario revertía en silencio el stock ya devuelto.
- El botón solo aparece si la venta tiene fila local, y no mientras su POST
  está en vuelo (borrarla ahí dejaría una venta huérfana en el servidor).
- Diálogo y mensajes dicen lo que pasa de verdad en cada caso.

Detalle del diseño en `SYNC.md`. Tests: `venta_cancel_policy_test.dart`,
`stock_calculator_test.dart`, `venta_unificada_model_test.dart`,
`ventas_provider_test.dart`.

---

### UX-02 · Tocar una categoría descarta la búsqueda pero deja el texto escrito
**Prioridad:** media · **Estado:** HECHO

`filterByCategoria` reconstruía `_filteredProductos` solo por categoría e
ignoraba el query activo, mientras que `searchProductos` sí respetaba la
categoría. El cajero veía "coca" escrito en el buscador y abajo la categoría
entera.

**Cómo quedó:** el provider guarda `_query` y ambos métodos delegan en un único
`_applyFilters()`, el único sitio que escribe `_filteredProductos`.
`_rebuildProductLists()` también lo llama, así que la búsqueda ya no se pierde
tras una venta ni al cambiar el filtro de stock — otro sitio donde se descartaba
en silencio. Se hizo junto a UX-03/UX-04, que necesitaban la misma estructura.

---

## B. Búsqueda — el cuello de botella del POS

Era un `contains` sobre la cadena cruda. Toda esta sección está cerrada salvo
UX-05; la normalización vive ahora en `lib/core/utils/search_text.dart`.

### UX-03 · La búsqueda no ignora tildes
**Prioridad:** alta · **Estado:** HECHO

"azucar" no encontraba "Azúcar", "cafe" no encontraba "Café".

**Cómo quedó:** `lib/core/utils/search_text.dart` (nuevo) centraliza la
normalización. La lógica ya existía **duplicada y privada** en
`asociar_codigo_sheet.dart` y `punto_de_partida_screen.dart`, con tablas de
caracteres distintas entre sí — y justo el buscador principal no usaba ninguna.
Ambas pantallas pasan ahora por `SearchText.normalize` y sus helpers
desaparecieron.

---

### UX-04 · La búsqueda no soporta palabras sueltas
**Prioridad:** alta · **Estado:** HECHO

Al ser `contains` sobre la cadena completa, "coca 2" no encontraba
"Coca Cola 2L".

**Cómo quedó:** la consulta se parte en tokens y se exigen **todos**, en
cualquier orden, sobre un texto buscable precalculado por producto (nombre,
**proveedor**, descripción y códigos). El proveedor es nuevo: el catálogo pinta
`nombreParaMostrar` = "nombre - proveedor", así que se podía teclear algo
visible en pantalla y no encontrar nada.

Los resultados se ordenan por relevancia: primero los que empiezan por lo
tecleado, luego los que tienen una palabra que empieza por el primer token,
luego el resto; alfabético dentro de cada grupo (`List.sort` de Dart no es
estable, el desempate por nombre es explícito).

---

### UX-05 · Enter en el buscador no hace nada
**Prioridad:** media · **Estado:** PENDIENTE · `pos_home_screen.dart:667`

Si se escanea con la pistola teniendo el buscador enfocado, el código entra
como texto y filtra bien (`searchProductos` sí matchea códigos), pero el Enter
se pierde: hay que tocar el resultado a mano. `HardwareScannerListener` se
desactiva a propósito cuando hay un campo de texto enfocado
(`hardware_scanner_listener.dart`), así que este es el camino que queda.

**Arreglo:** `onSubmitted` que agregue el producto si el filtro dejó
exactamente un resultado, y limpie el buscador.

---

### UX-06 · La búsqueda no tiene debounce
**Prioridad:** baja · **Estado:** DESCARTADO — resuelto por diseño en UX-03/04

Recorría el catálogo normalizando cada nombre en cada pulsación. Ahora el texto
buscable se precalcula una vez al cargar el catálogo (índice por `producto.id`
en `ProductosProvider`), así que por tecla solo queda un `contains` sobre
cadenas ya preparadas.

Un debounce encima solo añadiría latencia a algo que ya es barato, y en un POS
la latencia del buscador se nota. Si algún día un catálogo muy grande lo pidiera,
reconsiderarlo entonces con una medición delante.

---

## C. Carrito

### UX-07 · Bajar de 1 borra la línea sin confirmar ni poder deshacer
**Prioridad:** alta · **Estado:** PENDIENTE · `cart_items_screen.dart:476`

`onDecrement` llama a `removeItemById` en silencio. Todo lo demás destructivo
(vaciar carrito, cerrar cuenta, eliminar venta) tiene diálogo de confirmación;
esto no tiene nada.

**Arreglo:** `SnackBarAction("Deshacer")` al quitar la línea. Hoy no hay ni un
solo `SnackBarAction` en la app — conviene añadirlo a `AppSnackBar` para
reutilizarlo.

**Ojo:** desde UX-08 hay un segundo camino de borrado sin deshacer, el botón
"Quitar del carrito" de la hoja de cantidad. Es menos accidental (botón explícito
en vez de efecto lateral del "−"), pero el deshacer debe cubrir los dos. Ambos
pasan por `quitarLinea` en `_CartLine`, así que es un único sitio donde
engancharlo.

---

### UX-08 · No se puede teclear la cantidad desde el carrito
**Prioridad:** media · **Estado:** HECHO

De 1 a 12 eran once toques en "+", o borrar la línea y volver a agregarla desde
el catálogo.

**Cómo quedó:** tocar la línea abre la `QuantitySheet` que ya existía, ahora con
un modo edición (`QuantitySheet.editar`): arranca con la cantidad de la línea,
su tope incluye lo que ya está en ella, y **no toca el carrito** — devuelve la
cantidad elegida y la aplica `_CartLine`. Eso es deliberado: quitar la última
línea implica saltar a otra cuenta con productos o cerrar la vista, lógica que ya
vivía resuelta en el "−" y que ahora comparten los dos caminos (`quitarLinea`).

Dos guardas se invierten respecto al modo agregar: la hoja se abre aunque no
quede stock (hay que poder *bajar* una línea agotada), y cero es confirmable —
el botón pasa a "Quitar del carrito".

Solo el carrito principal: `CartItemTile` (panel sobre la cámara del escáner)
se quedó como estaba.

---

### UX-09 · El nombre del producto en el carrito se corta a una línea
**Prioridad:** baja · **Estado:** HECHO

`maxLines: 1` con ellipsis. Cortaba justo donde duele: el carrito guarda
`nombreParaMostrar` = "nombre - proveedor" (`cart_provider.dart:152`), así que lo
que distingue dos productos parecidos está **al final** y era lo primero en
desaparecer — "Coca Cola - Distribuidora Sur" y "…Norte" se veían idénticas.

**Cómo quedó:** `maxLines: 2`, igual que la fila del catálogo. Solo en
`_CartLine`; `CartItemTile` sigue a una línea.

---

## D. Accesibilidad

No es cosmético: el POS se usa a contraluz, con prisa y a veces con lentes.
**Sección cerrada.**

### UX-10 · Botones de 36×36 en las líneas del carrito
**Prioridad:** alta · **Estado:** HECHO

Los "−" / "+" del carrito eran 36×36, por debajo de `AppTapTarget.min` y de los
48dp de Material, siendo los controles más pulsados de la app.

**Cómo quedó:** barrido de **todos** los targets por debajo del mínimo, no solo
los del carrito: chips de cuenta y botón "+cuenta" (`cart_items_screen`), los
−/+ del panel del escáner (`cart_item_tile`), la píldora de moneda y el toggle
de transferencia del cobro (alto 40) y el botón del panel del escáner (42).
Todos pasan por `AppTapTarget.min`; ya no quedan literales de tamaño táctil.

De paso apareció que el `OutlinedButton` de los −/+ arrastraba el mínimo por
defecto de Material (64×36) y desbordaba su propia caja cuadrada: ahora fija
`minimumSize` y `tapTargetSize: shrinkWrap`.

---

### UX-11 · `AppTapTarget.min` es 44 (guía de iOS), Android pide 48
**Prioridad:** media · **Estado:** HECHO

**Cómo quedó:** `AppTapTarget.min` pasa de 44 a **48**. El dartdoc citaba
`foundations/paleta.html`, un archivo del design system que ya no está en el
repo; se anota en el token por qué 48 (Material, y la app es Android-only) y que
los tamaños táctiles no se escriben nunca como literales en los widgets.

---

### UX-12 · Faltan etiquetas de accesibilidad en el catálogo, el carrito y el teclado
**Prioridad:** media · **Estado:** HECHO

**Cómo quedó:** siguiendo el patrón que ya usaban `pos_checkout_bar` y
`cobrar_screen` (`Semantics(button:, excludeSemantics:, label:)`):

- Fila del catálogo: una etiqueta con nombre, precio y disponibilidad, en vez de
  que TalkBack leyera sueltas las conversiones de moneda. El "+" dice de qué
  producto es.
- Línea del carrito: cantidad, nombre e importe como una sola etiqueta; los
  −/+, que eran iconos mudos, pasan a "Quitar/Agregar una unidad de X".
- Teclado numérico: el `⌫` pasa a decir "Borrar".

---

### UX-13 · Nada maneja el escalado de fuente del sistema
**Prioridad:** media · **Estado:** HECHO (acotado a 1.3×, decisión consciente)

**Cómo quedó:** `MaterialApp.builder` acota el escalado a `maxTextScale` = 1.3
(`app_tokens.dart`). Android permite hasta 2×, y a esa escala el POS no cabe;
1.3× ayuda de verdad y la UI sigue entrando. **Es un tope deliberado, no un
olvido:** quien necesite más de 1.3× no lo obtiene.

Con el tope puesto, `test/core/textscale_test.dart` renderiza a esa escala el
carrito, el panel del escáner, el teclado, la hoja de cantidad y el cobro, y
exige que no salte ninguna excepción — Flutter reporta el overflow de un
`RenderFlex` como excepción, así que un desborde rompe el test en vez de quedar
en un rayado amarillo que nadie mira.

El test encontró cinco desbordes reales, todos corregidos: el total de la barra
de cobro y el subtotal de la línea (ahora se encogen con `FittedBox` en vez de
desbordar — un importe a medias es peor que uno pequeño), el contenido del botón
"Cobrar", la barra del panel del escáner (`Expanded` en vez de `Column` suelto +
`Spacer`) y el alto fijo del encabezado del panel del escáner (ahora depende de
la escala). Además la barra superior y los chips de categoría pasaron de alto
fijo a alto mínimo/escalado.

**Sin cubrir por tests:** `POSHomeScreen` no tiene harness (necesita auth,
período, sync, monedas, ventas, `SharedPreferences` y `package_info`), así que
sus chips, barra superior y filas de catálogo se arreglaron por construcción y
hay que comprobarlos a mano.

---

### UX-14 · Sin feedback háptico
**Prioridad:** baja · **Estado:** HECHO

**Cómo quedó:** la vibración va **dentro** del servicio de feedback de escaneo,
no sembrada en las llamadas. `ScanAudioService` pasa a llamarse
`ScanFeedbackService` (ya no es solo audio) y sus `playSuccess`/`playError`
vibran junto al tono: los ~15 puntos de llamada de
`barcode_scanner_screen.dart` y `barcode_scan_processor.dart` ganan háptica con
paridad garantizada, sin tocar ninguno. Sembrarla en los quince habría sido la
forma de que dentro de un mes uno sonara sin vibrar.

Fuera del escaneo, `lightImpact()` al agregar al carrito desde el catálogo y
desde la hoja de cantidad. Todo bajo el `try/catch` que el servicio ya tenía: un
dispositivo sin vibrador no puede romper una venta.

---

### UX-15 · La pantalla se apaga en medio de una venta
**Prioridad:** baja · **Estado:** HECHO

**Cómo quedó:** dependencia `wakelock_plus`, envuelta en
`lib/services/screen_wake_service.dart` con `try/catch` (en tests el plugin no
existe, y que la pantalla se apague no puede tumbar el POS).

Se activa **solo con una venta en curso**, no durante todo el período: en los
ratos muertos la pantalla se apaga sola y no se come la batería de un
dispositivo que puede no estar enchufado. El disparador es
`totalItemCountAcrossCarts > 0` — cualquier cuenta abierta con productos, no
solo la activa, porque con varias cuentas el cajero alterna entre ellas. Se
libera al vaciarse todo y en el `dispose()` de `POSHomeScreen` (salir del POS o
cerrar sesión).

---

### UX-20 · Una venta rechazada por el servidor no se ve en ninguna parte
**Prioridad:** alta · **Estado:** HECHO

El POST de una venta es fire-and-forget (`sync_service.dart:crearVenta`), así
que la pantalla de éxito se pintaba antes de saber si el servidor la aceptaba y
nunca se corregía. Una venta en `error` sólo se veía abriendo `VentasListScreen`
a mano, y el subtítulo de la barra decía "N sin subir" mezclando lo rechazado
con lo que sólo esperaba conexión.

**Arreglo:** tres avisos, con **rojo** para lo que hay que revisar (`error` /
`cancelError`) y **ámbar** para lo que sólo espera red (`pending` /
`cancelPending`):

- `VentasProvider` separa `errorCount` de `porSubirCount` (`pendingCount` sigue
  siendo el total), sobre un `countVentasConError()` nuevo en el local de ventas.
- `CobrarScreen` sigue su propia venta por `syncId` sondeando la base local cada
  segundo (tope de 20 s, se corta en cuanto hay desenlace): la pantalla de éxito
  pasa de "Enviando al servidor…" a "Enviada al servidor" o a un bloque rojo con
  el motivo real del servidor y un botón "Revisar ventas". Se sondea en vez de
  engancharse a `onDataRefreshed` porque ese callback hoy sólo lo registra
  `POSHomeScreen`.
- Badge sobre el botón "⋯" (`BadgedIcon`) y en las filas *Sincronizar* y
  *Ventas y sincronizaciones* del menú (`CountBadge`), más el conteo separado en
  el subtítulo de la barra superior.

Widget compartido nuevo: `lib/widgets/sync_badge.dart` (absorbe el `_CountBadge`
privado de `pos_actions_sheet.dart`).

---

## E. Funcionalidad ausente — decisión de producto, no bug

Estas no son fallas de implementación: son cosas que el POS no hace. Requieren
decidir antes de estimar.

### UX-16 · No existe la devolución / anulación como concepto
**Prioridad:** a decidir · **Estado:** PENDIENTE

Lo más cercano es "Eliminar venta" en `ventas_list_screen.dart`, que es una
operación de sincronización disfrazada de anulación: sin motivo, sin registro y
con el problema de UX-01. Una devolución de verdad necesita soporte del backend.

---

### UX-17 · No hay comprobante para el cliente
**Prioridad:** a decidir · **Estado:** PENDIENTE

Ni impresión térmica, ni compartir el detalle, ni QR. La pantalla de éxito del
cobro (`cobrar_screen.dart:_buildExito`) ya tiene toda la información: el
camino más barato es un botón "Compartir" que arme el texto.

---

### UX-18 · No se puede cerrar el período desde la app
**Prioridad:** a decidir · **Estado:** PENDIENTE

`pos_home_screen.dart:_buildNoPeriodoView` solo abre período. El cierre de caja
queda en la web.

---

### UX-19 · El POS no puede aplicar descuentos
**Prioridad:** a decidir · **Estado:** PENDIENTE

El endpoint existe (`api_constants.dart:30`, `/descuentos/preview`) y el detalle
de venta ya muestra la línea (`ventas_detail_screen.dart:253`), pero no hay
forma de aplicar uno al cobrar.

---

## Orden sugerido

1. ~~**UX-01**~~ — hecho.
2. ~~**UX-03 + UX-04**~~ — hechos, junto con UX-02 y UX-06.
3. **UX-07** — el deshacer al quitar una línea, el único de la sección C que
   queda junto a UX-05.
4. El resto por prioridad.

Cerradas por completo las secciones A, B (salvo UX-05) y D. Pendientes: UX-05,
UX-07 y toda la sección E (decisiones de producto).
