import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/periodo_model.dart';
import 'package:cuadre_caja_app/providers/auth_provider.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/providers/periodo_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/providers/venta_sin_stock_provider.dart';
import 'package:cuadre_caja_app/providers/ventas_provider.dart';
import 'package:cuadre_caja_app/screens/pos/cobrar_screen.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';

import '../../fakes/test_fakes.dart';
import '../../helpers/payment_test_harness.dart';

/// El `tasaSnapshot` se archiva con la venta y el backend reconstruye montos a
/// partir de él. El servidor devuelve dos mapas: `vigentes`, que omite la
/// moneda base, y `tasasCup`, completo. Enviar el primero deja el snapshot sin
/// la tasa de su propia base: `cupTasa(monedaBase)` cae a 1 y toda conversión
/// hacia la base queda inflada por el factor de la base.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Cobra una venta completa y devuelve la fila local creada.
  Future<FakeVentasLocalDataSource> cobrar(
    WidgetTester tester, {
    required String monedaBase,
    required Map<String, double> tasasConversion,
    required Map<String, double> tasasVigentes,
    List<String> monedasAlternativas = const ['EUR'],
  }) async {
    final ventasLocal = FakeVentasLocalDataSource();
    final sync = FakeSyncService(
      ventasLocal: ventasLocal,
      periodoAbierto: PeriodoModel(
        id: 'p1',
        tiendaId: 't1',
        fechaInicio: DateTime(2026, 8, 30),
        estaAbierto: true,
      ),
    );
    final periodoProvider = PeriodoProvider(sync);
    await periodoProvider.loadPeriodo('t1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: createTestAuthProvider()
              ..debugSetUsuario(buildTestUsuario(monedaBase: monedaBase)),
          ),
          ChangeNotifierProvider<MonedasProvider>.value(
            value: MonedasProvider(sync)
              ..debugSetConfig(
                buildTestConfig(
                  monedaBase: monedaBase,
                  tasas: tasasConversion,
                  tasasVigentes: tasasVigentes,
                  monedasAlternativas: monedasAlternativas,
                ),
              ),
          ),
          ChangeNotifierProvider<CartProvider>.value(
            value: CartProvider(FakeCartLocalDataSource())
              ..debugSetActiveCart(
                CartModel(
                  id: 'c1',
                  nombre: 'Cuenta #1',
                  items: [
                    CartItemModel(
                      productoTiendaId: 'p1',
                      nombre: 'Producto',
                      precio: 100,
                      monedaPrecioCode: monedaBase,
                    ),
                  ],
                ),
              ),
          ),
          ChangeNotifierProvider<PeriodoProvider>.value(value: periodoProvider),
          ChangeNotifierProvider<VentasProvider>.value(
            value: VentasProvider(sync),
          ),
          ChangeNotifierProvider<SyncProvider>.value(value: SyncProvider(sync)),
          ChangeNotifierProvider<ProductosProvider>.value(
            value: ProductosProvider(sync),
          ),
          ChangeNotifierProvider<VentaSinStockProvider>(
            create: (_) => VentaSinStockProvider(),
          ),
          Provider<SyncService>.value(value: sync),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCobrarScreen(context),
                child: const Text('ir a cobrar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ir a cobrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vender'));
    await tester.pumpAndSettle();
    return ventasLocal;
  }

  testWidgets(
      'con base distinta de CUP, la venta archiva la tasa de su propia base',
      (tester) async {
    // Lo que devuelve hoy el servidor para un negocio con base USD: `vigentes`
    // trae EUR pero no USD, `tasasCup` trae las dos.
    final local = await cobrar(
      tester,
      monedaBase: 'USD',
      tasasConversion: const {'USD': 670, 'EUR': 775},
      tasasVigentes: const {'EUR': 775},
    );

    final snapshot = local.pendientes.single.tasaSnapshot;
    expect(snapshot['USD'], 670, reason: 'falta la tasa de la moneda base');
    expect(snapshot['EUR'], 775);
  });

  testWidgets('con base CUP el snapshot no cambia', (tester) async {
    // Regresión: con base CUP los dos mapas son idénticos, así que el arreglo
    // no debe alterar nada para la gran mayoría de los negocios.
    final local = await cobrar(
      tester,
      monedaBase: 'CUP',
      tasasConversion: const {'USD': 400, 'MLC': 120},
      tasasVigentes: const {'USD': 400, 'MLC': 120},
      monedasAlternativas: const ['USD', 'MLC'],
    );

    expect(
      local.pendientes.single.tasaSnapshot,
      const {'USD': 400.0, 'MLC': 120.0},
    );
  });
}
