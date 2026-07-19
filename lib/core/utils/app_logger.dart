import 'package:flutter/foundation.dart';

/// Log de desarrollo con la convención de emojis del proyecto (🚀 ✅ ❌ 🌐 ⚠️).
///
/// Solo emite en modo debug: en builds de release no imprime nada, para no
/// filtrar rutas de request / flujo de token a logcat ni agregar overhead.
/// Reemplaza los `print(...)` sueltos que antes se enviaban también en release.
void logDebug(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}
