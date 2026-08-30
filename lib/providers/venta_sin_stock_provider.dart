import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/storage_keys.dart';

/// Ajuste "Vender sin existencias", persistido entre sesiones.
///
/// Sin conexión la venta sin stock siempre está permitida (el servidor es el
/// árbitro final al sincronizar). Este ajuste extiende ese permiso a cuando
/// *sí* hay conexión: el usuario decide seguir vendiendo productos agotados o
/// con existencia negativa. Ver [VentaSinStockPolicy], que combina ambos.
class VentaSinStockProvider extends ChangeNotifier {
  bool _enabled = false;

  VentaSinStockProvider() {
    _load();
  }

  bool get enabled => _enabled;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(StorageKeys.ventaSinStockEnabled) ?? false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.ventaSinStockEnabled, value);
  }
}
