import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cuadre_caja_app/core/constants/storage_keys.dart';
import 'package:cuadre_caja_app/providers/venta_sin_stock_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('por defecto el ajuste está desactivado', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = VentaSinStockProvider();
    // _load() se dispara desde el constructor sin await.
    await Future<void>.delayed(Duration.zero);
    expect(provider.enabled, isFalse);
  });

  test('recupera el valor guardado en una sesión anterior', () async {
    SharedPreferences.setMockInitialValues(
      {StorageKeys.ventaSinStockEnabled: true},
    );
    final provider = VentaSinStockProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.enabled, isTrue);
  });

  test('activarlo notifica y persiste', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = VentaSinStockProvider();
    await Future<void>.delayed(Duration.zero);

    var notificaciones = 0;
    provider.addListener(() => notificaciones++);

    await provider.setEnabled(true);

    expect(provider.enabled, isTrue);
    expect(notificaciones, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(StorageKeys.ventaSinStockEnabled), isTrue);
  });

  test('desactivarlo vuelve a persistir false', () async {
    SharedPreferences.setMockInitialValues(
      {StorageKeys.ventaSinStockEnabled: true},
    );
    final provider = VentaSinStockProvider();
    await Future<void>.delayed(Duration.zero);

    await provider.setEnabled(false);

    expect(provider.enabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(StorageKeys.ventaSinStockEnabled), isFalse);
  });
}
