# Barcode scanning

Two input paths: the camera (`mobile_scanner`) and external Bluetooth/USB scanner "guns" (keyboard-wedge). `HardwareScannerListener` / `barcode_scan_processor.dart` handle the wedge input.

## Cuándo actúa la pistola

`HardwareScannerListener` registra un handler **global de proceso**
(`HardwareKeyboard.instance.addHandler`), que sigue vivo aunque le empujen rutas
encima a la pantalla que lo monta. Para que un escaneo no modifique el carrito
de forma invisible desde otra pantalla, el listener solo procesa el código si:

1. `enabled` es `true` (hay periodo abierto), **y**
2. **su propia ruta está al frente** (`ModalRoute.isCurrent`) — falso en cuanto
   hay cualquier cosa encima: otra pantalla, un `showModalBottomSheet`, un
   `showDialog` o un menú emergente, **y**
3. no hay un campo de texto editable con el foco (`_isEditableFocused`).

El default es seguro: una pantalla nueva **no** recibe escaneos salvo que monte
el listener a propósito. Hoy lo montan la pantalla de venta
(`pos_home_screen.dart`) y el carrito a pantalla completa
(`cart_items_screen.dart`); en tablet el carrito es un panel dentro de la
pantalla de venta, así que queda cubierto por el listener de esa.

Antes existía un `HardwareScannerGate` (lista blanca de razones que cada modal
tenía que acordarse de bloquear). Se eliminó: cubría 5 de ~40 puntos de
navegación y podía quedarse trabado. La regla 2 lo reemplaza por completo.

La pistola **no** consume las teclas de carácter, así que un escaneo sigue
pudiendo escribir dentro de un campo enfocado; distinguir pistola de teclado
físico exigiría medir el timing entre teclas.

`HardwareScannerListener.onScanOverride` existe solo para tests
(`test/widgets/hardware_scanner_listener_test.dart`), ya que
`BarcodeScanProcessor` necesita los providers y la DI completos.
