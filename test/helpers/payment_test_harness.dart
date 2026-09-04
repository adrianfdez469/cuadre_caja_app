import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/moneda_model.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';
import 'package:cuadre_caja_app/data/models/usuario_model.dart';
import 'package:cuadre_caja_app/providers/auth_provider.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/providers/periodo_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/providers/ventas_provider.dart';
import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/screens/pos/cobrar_screen.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/test_fakes.dart';

/// Denominaciones de prueba por moneda. Sin esto `denominacionesPorMoneda`
/// devuelve un mapa vacío y todo el cálculo del vuelto cae al fallback de CUP,
/// que oculta los casos donde la denominación mínima no es 1.
const _denominacionesTest = {
  'CUP': [1.0, 3.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0],
  'USD': [1.0, 5.0, 10.0, 20.0, 50.0, 100.0],
  'MLC': [1.0, 5.0, 10.0, 20.0, 50.0, 100.0],
};

MonedaInfoModel _monedaInfo(String code) => MonedaInfoModel(
      code: code,
      nombre: code,
      simbolo: code,
      denominaciones: [
        for (final v in _denominacionesTest[code] ??
            const [1.0, 5.0, 10.0, 20.0, 50.0, 100.0])
          DenominacionBilleteModel(id: '$code-$v', monedaCode: code, valor: v),
      ],
    );

MultimonedaConfig buildTestConfig({
  String monedaBase = 'CUP',
  Map<String, double> tasas = const {'USD': 400, 'MLC': 120},
  /// Monedas alternativas activas del negocio. MLC solo admite efectivo, para
  /// poder ejercitar el camino "esta moneda no acepta transferencia".
  List<String> monedasAlternativas = const ['USD', 'MLC'],
}) {
  return MultimonedaConfig(
    negocioId: 'neg-1',
    monedaBase: monedaBase,
    tasas: tasas,
    monedas: [
      NegocioMonedaModel(
        id: 'base',
        negocioId: 'neg-1',
        monedaCode: monedaBase,
        moneda: _monedaInfo(monedaBase),
        admiteEfectivo: true,
        admiteTransferencia: true,
      ),
      for (final code in monedasAlternativas)
        if (code != monedaBase)
          NegocioMonedaModel(
            id: code,
            negocioId: 'neg-1',
            monedaCode: code,
            moneda: _monedaInfo(code),
            admiteEfectivo: true,
            admiteTransferencia: code != 'MLC',
          ),
    ],
  );
}

UsuarioModel buildTestUsuario({String monedaBase = 'CUP'}) {
  final tienda = TiendaModel(
    id: 't1',
    nombre: 'Tienda Test',
    negocioId: 'neg-1',
    tipo: 'TIENDA',
  );
  return UsuarioModel(
    id: 'u1',
    nombre: 'Test',
    usuario: 'test',
    negocio: NegocioModel(
      id: 'neg-1',
      nombre: 'Negocio',
      userlimit: 1,
      locallimit: 1,
      productlimit: 100,
      monedaBase: monedaBase,
      monedaFuerte: monedaBase,
    ),
    localActual: tienda,
    locales: [tienda],
    permisos: const [],
  );
}

/// [textScaler] permite montar el cobro con la letra del sistema ampliada, para
/// los tests de escalado (`test/core/textscale_test.dart`).
Widget buildCobrarScreenHarness({
  required MultimonedaConfig config,
  required CartModel cart,
  required FakeSyncService syncService,
  String monedaBase = 'CUP',
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final auth = createTestAuthProvider()
    ..debugSetUsuario(buildTestUsuario(monedaBase: monedaBase));
  final monedas = MonedasProvider(syncService)..debugSetConfig(config);
  final cartProvider = CartProvider(FakeCartLocalDataSource())
    ..debugSetActiveCart(cart);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<MonedasProvider>.value(value: monedas),
      ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
      Provider<SyncService>.value(value: syncService),
    ],
    child: MaterialApp(
      theme: appLightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: CobrarScreen(
          getTransferDestinationsLocalOverride:
              syncService.getTransferDestinationsLocal,
        ),
      ),
    ),
  );
}

Future<void> pumpCobrarScreen(
  WidgetTester tester, {
  double total = 1500,
  String monedaBase = 'CUP',
  Map<String, double> tasas = const {'USD': 400, 'MLC': 120},
  List<String> monedasAlternativas = const ['USD', 'MLC'],
  List<TransferDestinationModel>? destinations,
}) async {
  final config = buildTestConfig(
    monedaBase: monedaBase,
    tasas: tasas,
    monedasAlternativas: monedasAlternativas,
  );
  final sync = FakeSyncService(
    destinations: destinations ??
        [
          TransferDestinationModel(id: 'd1', nombre: 'Banco', isDefault: true),
        ],
  );
  final cart = CartModel(
    id: 'c1',
    nombre: 'Cuenta #1',
    items: [
      CartItemModel(
        productoTiendaId: 'p1',
        nombre: 'Producto',
        precio: total,
        monedaPrecioCode: monedaBase,
      ),
    ],
  );

  await tester.pumpWidget(
    buildCobrarScreenHarness(
      config: config,
      cart: cart,
      syncService: sync,
      monedaBase: monedaBase,
    ),
  );
  await tester.pumpAndSettle();
}

/// El campo de efectivo de una moneda. Se busca por `Key` y no por texto: los
/// montos ya no son `TextField` con label, sino cajas que abren la hoja de
/// entrada.
Finder cashFieldDe(String moneda) => find.byKey(Key('pago-$moneda-cash'));
Finder transferFieldDe(String moneda) =>
    find.byKey(Key('pago-$moneda-transfer'));
Finder transferToggleDe(String moneda) =>
    find.byKey(Key('transfer-toggle-$moneda'));

/// Monto que muestra un campo del cobro.
String montoDe(WidgetTester tester, Finder campo) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: campo, matching: find.byType(Text)),
  );
  // El último Text de un campo con etiqueta es el monto; en el destacado es el
  // primero, seguido del código de moneda. Se toma el que sea numérico.
  for (final t in texts) {
    final data = t.data ?? '';
    if (double.tryParse(data) != null) return data;
  }
  return '';
}

/// Escribe un monto en un campo abriendo la hoja de entrada, tecleándolo y
/// confirmando — que es el único camino que tiene el cajero.
Future<void> escribirMonto(
  WidgetTester tester,
  Finder campo,
  String monto,
) async {
  await tester.tap(campo);
  await tester.pumpAndSettle();
  // La hoja arranca con el monto anterior: se borra dígito a dígito.
  for (var i = 0; i < 14; i++) {
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
  }
  for (final d in monto.split('')) {
    await tester.tap(find.widgetWithText(InkWell, d).last);
    await tester.pump();
  }
  // `.last` porque la hoja de cambio también tiene un "Listo": el de arriba es
  // el de la hoja de montos, que es la que se está confirmando.
  await tester.tap(find.widgetWithText(ElevatedButton, 'Listo').last);
  await tester.pumpAndSettle();
}

/// Monta el modal con el árbol completo de providers que usa
/// `_processPayment()` (Periodo/Ventas/Sync/Productos), para poder llegar
/// hasta confirmar una venta real y ver la pantalla de éxito.
Future<void> pumpCobrarScreenFull(
  WidgetTester tester, {
  required MultimonedaConfig config,
  required CartModel cart,
  required FakeSyncService syncService,
  String tiendaId = 't1',
  bool isOnline = false,
}) async {
  final auth = createTestAuthProvider()
    ..debugSetUsuario(buildTestUsuario(monedaBase: config.monedaBase));
  final monedas = MonedasProvider(syncService)..debugSetConfig(config);
  final cartProvider = CartProvider(FakeCartLocalDataSource())
    ..debugSetActiveCart(cart);
  final periodoProvider = PeriodoProvider(syncService);
  await periodoProvider.loadPeriodo(tiendaId);
  final ventasProvider = VentasProvider(syncService);
  final syncProvider = SyncProvider(syncService);
  if (isOnline) {
    syncService.onConnectionChanged?.call(ConnectionStatus.online);
  }
  final productosProvider = ProductosProvider(syncService);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<MonedasProvider>.value(value: monedas),
        ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
        ChangeNotifierProvider<PeriodoProvider>.value(value: periodoProvider),
        ChangeNotifierProvider<VentasProvider>.value(value: ventasProvider),
        ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
        ChangeNotifierProvider<ProductosProvider>.value(value: productosProvider),
        Provider<SyncService>.value(value: syncService),
      ],
      child: MaterialApp(
        theme: appLightTheme,
        home: Scaffold(
          body: CobrarScreen(
            getTransferDestinationsLocalOverride:
                syncService.getTransferDestinationsLocal,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
