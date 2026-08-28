# Barcode scanning

Two input paths: the camera (`mobile_scanner`) and external Bluetooth/USB scanner "guns" (keyboard-wedge). `HardwareScannerGate` (a singleton with reason-tagged blocking) suppresses the hardware scanner during certain UI states (modals, etc.); `HardwareScannerListener` / `barcode_scan_processor.dart` handle the wedge input.
