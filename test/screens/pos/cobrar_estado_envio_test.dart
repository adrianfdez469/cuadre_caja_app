import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/periodo_model.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';
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

/// El POST de una venta es fire-and-forget: la pantalla de éxito se pinta antes
/// de que el servidor conteste. Hasta ahora un rechazo no se veía por ninguna
/// parte y la venta se quedaba en el equipo sin que nadie lo supiera.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Cobra una venta completa y devuelve el local falso, ya con la fila creada,
  /// para poder simular el desenlace del POST.
  Future<FakeVentasLocalDataSource> cobrar(
    WidgetTester tester, {
    required bool online,
    TextScaler textScaler = TextScaler.noScaling,
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
    final syncProvider = SyncProvider(sync);
    if (online) {
      // SyncProvider sólo conoce la conexión por el callback del servicio.
      sync.onConnectionChanged?.call(ConnectionStatus.online);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: createTestAuthProvider()
              ..debugSetUsuario(buildTestUsuario(monedaBase: 'CUP')),
          ),
          ChangeNotifierProvider<MonedasProvider>.value(
            value: MonedasProvider(sync)..debugSetConfig(buildTestConfig()),
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
                      monedaPrecioCode: 'CUP',
                    ),
                  ],
                ),
              ),
          ),
          ChangeNotifierProvider<PeriodoProvider>.value(value: periodoProvider),
          ChangeNotifierProvider<VentasProvider>.value(
            value: VentasProvider(sync),
          ),
          ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
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
    await tester.pump();
    return ventasLocal;
  }

  testWidgets('sin conexión no se sondea nada: la venta espera a la red',
      (tester) async {
    await cobrar(tester, online: false);
    await tester.pumpAndSettle();

    expect(find.text('Cobro registrado'), findsOneWidget);
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.text('Enviando al servidor…'), findsNothing);
  });

  testWidgets('el servidor la acepta: el aviso pasa a "Enviada"',
      (tester) async {
    final local = await cobrar(tester, online: true);
    final syncId = local.pendientes.single.syncId;

    expect(find.text('Enviando al servidor…'), findsOneWidget);

    local.debugSetEstado(syncId, SyncState.synced);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Enviada al servidor'), findsOneWidget);
    expect(find.text('Enviando al servidor…'), findsNothing);
  });

  testWidgets('el servidor la rechaza: se avisa con el motivo real',
      (tester) async {
    final local = await cobrar(tester, online: true);
    final syncId = local.pendientes.single.syncId;

    local.debugSetEstado(
      syncId,
      SyncState.error,
      errorMessage: 'Período cerrado o diferente al actual',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo enviar al servidor'), findsOneWidget);
    // Título amigable de SyncErrorMessages, más el detalle crudo del servidor.
    expect(find.text('Período no es el actual'), findsOneWidget);
    expect(find.text('Período cerrado o diferente al actual'), findsOneWidget);
    expect(find.text('Revisar ventas'), findsOneWidget);
    // El cobro sigue siendo válido: lo que falló es el envío.
    expect(find.text('Cobro registrado'), findsOneWidget);
    expect(find.text('Nueva venta'), findsOneWidget);
  });

  testWidgets('el aviso de error no desborda con la letra ampliada',
      (tester) async {
    // La misma escala que acota `MaterialApp.builder` en producción; el bloque
    // de error es lo más denso de la pantalla de éxito.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final local = await cobrar(
      tester,
      online: true,
      textScaler: const TextScaler.linear(1.3),
    );
    local.debugSetEstado(
      local.pendientes.single.syncId,
      SyncState.error,
      errorMessage: 'Existencia insuficiente para desagregar el producto '
          'Refresco de naranja de 1,5 litros en la tienda principal',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo enviar al servidor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el sondeo se detiene al llegar a un estado terminal',
      (tester) async {
    final local = await cobrar(tester, online: true);
    final syncId = local.pendientes.single.syncId;

    local.debugSetEstado(syncId, SyncState.error, errorMessage: 'boom');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Si el timer siguiera vivo, pumpAndSettle nunca asentaría.
    local.debugSetEstado(syncId, SyncState.synced);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('No se pudo enviar al servidor'), findsOneWidget);
  });
}
