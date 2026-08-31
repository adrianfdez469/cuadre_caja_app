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
**Prioridad:** media · **Estado:** DESCARTADO · `pos_home_screen.dart:667`

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
**Prioridad:** alta · **Estado:** DESCARTADO · `cart_items_screen.dart:476`

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
**Prioridad:** a decidir · **Estado:** DESCARTADO

Lo más cercano es "Eliminar venta" en `ventas_list_screen.dart`, que es una
operación de sincronización disfrazada de anulación: sin motivo, sin registro y
con el problema de UX-01. Una devolución de verdad necesita soporte del backend.

---

### UX-17 · No hay comprobante para el cliente
**Prioridad:** a decidir · **Estado:** DESCARTADO

Ni impresión térmica, ni compartir el detalle, ni QR. La pantalla de éxito del
cobro (`cobrar_screen.dart:_buildExito`) ya tiene toda la información: el
camino más barato es un botón "Compartir" que arme el texto.

---

### UX-18 · No se puede cerrar el período desde la app
**Prioridad:** a decidir · **Estado:** DESCARTADO

`pos_home_screen.dart:_buildNoPeriodoView` solo abre período. El cierre de caja
queda en la web.

---

### UX-19 · El POS no puede aplicar descuentos
**Prioridad:** a decidir · **Estado:** PENDIENTE

El endpoint existe (`api_constants.dart:30`, `/descuentos/preview`) y el detalle
de venta ya muestra la línea (`ventas_detail_screen.dart:253`), pero no hay
forma de aplicar uno al cobrar.

---

## F. Vistas de consulta del período

Hallazgos de la revisión de diseño de `ventas_list_screen.dart`,
`productos_vendidos_screen.dart` y `punto_de_partida_screen.dart` hecha el
2026-08-31 sobre la v2.3.1. Las tres cuelgan de la hoja *Acciones del POS* y
forman el bloque de consulta del período; se leían como tres productos distintos
(una sin `AppBar`, dos con pull-to-refresh, tres formatos numéricos, dos
vocabularios para el estado de sincronización).

### UX-21 · Componentes duplicados entre las tres vistas de consulta
**Prioridad:** alta · **Estado:** HECHO

Cinco componentes copiados entre las tres pantallas y `ventas_detail_screen`:
chip de filtro (`productos_vendidos_screen.dart:866` ≡
`ventas_detail_screen.dart:454`), estado de sincronización (chips de texto con
7 estados en `ventas_list_screen.dart:596` vs iconos de nube con 4 en
`productos_vendidos_screen.dart:763`), estado vacío (cuatro variantes con
iconos 40/56/64 y una sin icono), tarjeta-tabla (anchos 64/80 vs 52/92) y
tarjeta de métrica. Más `decimals: x == x.round() ? 0 : 1` repetido cuatro veces.

**Arreglo:** extraer a `lib/widgets/` — `sync_state_chip.dart`, `empty_state.dart`,
`app_filter_chip.dart`, `data_table_card.dart`, `stat_tile.dart` — y
`Formatters.formatCantidad`.

**Cómo quedó:** cinco widgets en `lib/widgets/` — `sync_state_chip.dart`
(`SyncStateChip` + `SyncStateLabels`, los **siete** estados, fondo con los
tokens `*Wash` y radio `pill`), `empty_state.dart`, `app_filter_chip.dart`
(`AppFilterChip` con contador + `AppChoiceChip`), `data_table_card.dart`
(`TableColumn`/`DataTableHeader`/`DataTableRow`/`DataTableCard`, con `title`
para el nombre del producto y `ClipRRect` en la cabecera) y `stat_tile.dart`
(`StatTile` + `StatTone`). Más `Formatters.formatCantidad` y
`Formatters.formatDiaRelativo`.

El detalle de venta también pasa por ellos: perdió su `_FilterChip` y su
`_proveedorByProducto`, que ahora vive en
`lib/core/utils/productos_vendidos_agregacion.dart`.

La etiqueta se unificó en **"Productos propios"**.
---

### UX-22 · "Ventas y sincronizaciones" no dice qué se está mirando ni deja filtrar
**Prioridad:** alta · **Estado:** HECHO · `ventas_list_screen.dart:162`

Sin resumen (nº de ventas, total, reparto por estado) y sin filtros, pese a que
la pantalla existe para resolver ventas rechazadas: con 80 ventas del día hay que
encontrarlas por scroll. Además: fecha completa repetida en cada tarjeta cuando
todas son del mismo día (`:498`); `Divider` y fila de acciones vacíos en la venta
sincronizada del servidor, que es el caso más común (`:556`); "Efectivo: $x"
visible aunque el 100% sea efectivo (`:543`); "3 ítems" son líneas, no unidades,
y no pluralizan (`venta_model.dart:513`); importe en `accent`, que el token
reserva para acción/selección (`:534`); chip de estado con
`withValues(alpha:0.16)` en vez de los `*Wash` y radio `sm` en vez de `pill`
(`:507`); "Sincronizar todos" desaparece sin explicación sin conexión (`:166`) y
se deshabilita con `isLoading` mientras el body usa `isLoadingVentas`; estado
vacío no scrollable, que se come el pull-to-refresh (`:250`); sin `Semantics`
de tarjeta.

**Cómo quedó:** `CustomScrollView` con tarjeta de resumen (nº de ventas, total
y reparto por estado, contados sobre la lista que se muestra para que los chips
cuadren con las filas), barra de filtros pegajosa —*Todas · Sin subir · Con
error*, y sólo aparece si hay algo pendiente— y encabezados de día con
`formatDiaRelativo`, dejando la hora en la fila.

La fila de acciones y su separador se construyen **sólo si hay alguna acción**:
en una venta ya sincronizada del servidor las tres son `null` y antes se pintaba
el hueco igual. El desglose de pago aparece sólo con dos formas de pago. El
importe pasa de `accent` a `textPrimary`. Chip de estado por `SyncStateChip`.
"Sincronizar" ya no desaparece sin conexión: queda deshabilitado con un banner
`caution` que explica por qué, y ambos —botón y cuerpo— miran `isLoadingVentas`.
El estado vacío es scrollable (`AlwaysScrollableScrollPhysics`), distingue "no
hay ventas" de "el filtro no deja nada" y ofrece "Ver todas". `Semantics` por
tarjeta con hora, estado, líneas e importe.

Tests: `vistas_consulta_test.dart` (acciones ausentes, resumen, filtro) y
`textscale_test.dart`.
---

### UX-23 · "Productos vendidos" oculta su propio alcance
**Prioridad:** alta · **Estado:** HECHO · `productos_vendidos_screen.dart:243`

El filtro de vendedor arranca en el usuario actual y el título solo avisa del
filtro de **proveedor** (`:371`): "Total vendido $X" se lee como el total de la
tienda cuando es solo el propio. Es el hallazgo más grave de las tres pantallas.

Además: los datos empiezan bajo el pliegue, con ~300px de filtros antes de la
primera fila (`:332`); importes alineados a la izquierda, con lo que `tabularNums`
no sirve de nada (`:654`); "Precio" es `Expanded` y "Total" tiene 92px fijos
(`:591`); la columna Precio de la vista agrupada se sobrescribe con el último
precio procesado, así que `Precio × Cant. ≠ Total` si hubo dos precios (`:186`);
orden por defecto por última venta y no configurable (`:208`); la agrupada no
avisa de que sus totales incluyen ventas sin subir (`:574`); la histórica usa
iconos de nube y cubre 4 de 7 estados, pintando "Anulación pendiente" como
"Sincronizando" (`:763`); "Total vendido" (por ítem) y "Total en transferencia"
(por venta) no son comparables y falta efectivo/unidades para cerrar el cuadro
(`:213`); vacío ambiguo sin CTA (`:575`); cabecera de tabla sin `ClipRRect`
dentro de un `Card` redondeado (`:591`); toda la tabla materializada con
`shrinkWrap` (`:633`).

**Cómo quedó:** los filtros de vendedor y proveedor salen a una hoja "Filtros"
(`showModalBottomSheet` + `Aplicar`/`Limpiar`), con `BadgedIcon` en el AppBar
contando los activos; en su lugar hay una **barra de alcance pegajosa** que dice
en texto plano qué se está mirando ("Tus ventas · todos los proveedores") con un
botón "Cambiar". Eso resuelve a la vez el alcance invisible y los ~300px de
chips que empujaban los datos bajo el pliegue.

Tabla por `DataTableCard`: las tres columnas numéricas a la derecha, "Total" la
más ancha y la única en `titleMedium`, y el nombre del producto en su propia
línea con el proveedor debajo. El precio agrupado pasa a `total / cantidad` y la
columna se rotula "P. medio" cuando algún producto tuvo más de un precio. Orden
configurable (importe por defecto, unidades, A–Z, reciente). `SyncStateChip` en
la histórica y aviso en el resumen de la agrupada cuando los totales incluyen
ventas sin subir o con error. El resumen cierra el cuadro —vendido, unidades,
productos, efectivo, transferencia, descuentos y destinos— y dice explícitamente
por qué no reparte el pago con un filtro de proveedor activo. Estados vacíos
distintos con "Quitar filtros". `SliverList` en vez de `shrinkWrap`.

La agregación salió del `State` a `lib/core/utils/productos_vendidos_agregacion.dart`,
con `productos_vendidos_agregacion_test.dart` (12 casos) — el de los dos precios
distintos es el que fija el fallo del precio unitario.
---

### UX-24 · "Punto de partida" no sigue ninguna convención de la app
**Prioridad:** media · **Estado:** HECHO · `punto_de_partida_screen.dart:188`

Única pantalla empujada con `MaterialPageRoute` sin `AppBar`: cabecera propia con
"✕" y sin flecha de retroceso, y con un título ("Punto de partida y
comportamiento") que no coincide con el del menú. Sin pull-to-refresh (`:390`).

El control más importante —cambiar entre "solo con movimientos" y "todos"— es un
icono de ojo ambiguo cuyo estado solo se descubre con el tooltip (`:348`).
Contraste por debajo del umbral en `_MovimientoBox`: texto al `alpha 0.8` sobre
fondo del mismo color al `0.08` (`:694`), y lo mismo en `_InfoBox` (`:659`) —
afecta justo a las cifras que la pantalla existe para mostrar. Tres radios
distintos en la misma tarjeta (`sm`, literal 8, literal 6). No usa `Card`: cuatro
`Container` + `BoxDecoration` que replican `CardTheme`. Dos formatos numéricos
incompatibles en la misma pantalla y **ningún** `tabularNums` (`:181`, `:513`).
Cada producto ocupa ~150px para cinco cifras: con 200 productos, comparar dos
exige memorizar (`:529`). El color de categoría viene del servidor sin control de
contraste y se usa como color de **texto** (`:415`). El buscador reinventa su
`InputDecoration` en vez de heredar el tema y no tiene botón de limpiar (`:323`).

**Lo que esta pantalla hace mejor y hay que propagar:** el banner de error no
bloqueante que conserva los datos previos cuando falla el refresh (`:116`, `:244`).

**Cómo quedó:** `AppBar` estándar con flecha de retroceso, título "Punto de
partida" y `⟳` en `actions`; `RefreshIndicator` sobre un `CustomScrollView`. El
ojo se sustituye por dos `AppChoiceChip` con texto ("Con movimientos" / "Todos").
`StatTile` sustituye a `_TotalCard`, `_InfoBox` y `_MovimientoBox`: fondo con el
`*Wash` del tono y texto con el `ink` a plena opacidad, un solo radio
(`AppRadius.md`) y `Card` del tema. Todas las cifras por
`Formatters.formatCantidad` + `tabularNums`.

La tarjeta de ~150px pasa a fila compacta: nombre, proveedor, una línea con
inicial y **sólo los movimientos que existen**, y la existencia actual como
`StatTile` a la derecha; tocarla despliega las cuatro cajas completas. El color
de categoría va en un punto, no en el texto del rótulo, que usa `textSecondary`
y siempre se lee. El buscador hereda `inputDecorationTheme` y gana ✕.
Estados vacíos distintos para búsqueda sin resultados, período sin movimientos
(con CTA "Ver todos los productos") e inventario vacío. `Semantics` por fila.

`_parseError` pasa a mirar el tipo real de `DioException` en vez de buscar
subcadenas en `e.toString()`. Se añadió un parámetro `datasource` opcional al
widget, sólo para poder montarlo en un widget test.
---

### UX-25 · Los tonos semánticos están mal asignados en las vistas de consulta
**Prioridad:** media · **Estado:** HECHO

`app_tokens.dart:53-61` fija un significado por tono y estas pantallas lo
contradicen. "Ventas" se pinta en `negative` en la fila de totales
(`punto_de_partida_screen.dart:288`) y en cada tarjeta de producto (`:606`):
vender no es "falta / se agotó / falló", y el cajero ve su mejor dato del día en
rojo de alarma. "Salidas" en `caution` tiene el mismo problema. En paralelo, los
fondos tenues se calculan con `withValues(alpha:)` en vez de usar los `*Wash`.

**Decisión:** en un resumen de movimientos el eje no es bueno/malo sino de dónde
vino el movimiento. Ventas y Salidas → `info`; Entradas se queda en `positive`;
`negative` queda libre para lo que sí exige atención (existencia en cero, que
`_colorExistencia` ya resuelve bien). Los importes de la lista de ventas pasan a
`textPrimary`.

**Cómo quedó:** aplicado. Ventas y Salidas en `info`, Entradas en `positive`,
`negative` sólo para la existencia en cero. Los importes de la lista de ventas
en `textPrimary`. Ya no queda ningún `withValues(alpha:)` calculando fondos en
estas pantallas: `SyncStateChip` y `StatTile` usan los `*Wash`.
---

### UX-26 · "Punto de partida" es la única pantalla no offline-first
**Prioridad:** a decidir · **Estado:** PENDIENTE · `punto_de_partida_screen.dart:37`

Pega directo a `ResumenDiaRemoteDataSource` sin caché local ni cola: sin conexión
queda inservible, mientras el POS entero está construido para seguir vendiendo.
Darle caché exige tocar `sync_service` y `database_helper` (ver `SYNC.md`): es un
cambio de arquitectura, no de diseño, y por eso va aparte de UX-24.

De UX-24 sí sale el paliativo: conservar el banner de degradación y sustituir el
*string matching* de `_parseError` (`:85`) por las excepciones tipadas de
`lib/core/errors/exceptions.dart`.

---

## Orden sugerido

1. ~~**UX-01**~~ — hecho.
2. ~~**UX-03 + UX-04**~~ — hechos, junto con UX-02 y UX-06.
3. **UX-07** — el deshacer al quitar una línea, el único de la sección C que
   queda junto a UX-05.
4. El resto por prioridad.

Cerradas por completo las secciones A, B (salvo UX-05), D y F (salvo UX-26).
Pendientes: UX-05, UX-07, toda la sección E (decisiones de producto) y UX-26.

La sección F está cerrada salvo **UX-26**, que espera a que se decida darle
caché offline a "Punto de partida".
