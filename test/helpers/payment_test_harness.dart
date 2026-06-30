import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/moneda_model.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';
import 'package:cuadre_caja_app/data/models/usuario_model.dart';
import 'package:cuadre_caja_app/providers/auth_provider.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/screens/pos/payment_modal.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/test_fakes.dart';

MultimonedaConfig buildTestConfig({
  String monedaBase = 'CUP',
  Map<String, double> tasas = const {'USD': 400, 'MLC': 120},
}) {
  return MultimonedaConfig(
    negocioId: 'neg-1',
    monedaBase: monedaBase,
    tasasVigentes: tasas,
    tasasConversion: tasas,
    monedas: [
      NegocioMonedaModel(
        id: '1',
        negocioId: 'neg-1',
        monedaCode: monedaBase,
        admiteEfectivo: true,
        admiteTransferencia: true,
      ),
      NegocioMonedaModel(
        id: '2',
        negocioId: 'neg-1',
        monedaCode: 'USD',
        admiteEfectivo: true,
        admiteTransferencia: true,
      ),
      NegocioMonedaModel(
        id: '3',
        negocioId: 'neg-1',
        monedaCode: 'MLC',
        admiteEfectivo: true,
        admiteTransferencia: false,
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

Widget buildPaymentModalHarness({
  required MultimonedaConfig config,
  required CartModel cart,
  required FakeSyncService syncService,
  String monedaBase = 'CUP',
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
      home: Scaffold(
        body: PaymentModal(
          loadTransferDestinationsOverride: syncService.loadTransferDestinations,
        ),
      ),
    ),
  );
}

Future<void> pumpPaymentModal(
  WidgetTester tester, {
  double total = 1500,
  String monedaBase = 'CUP',
  Map<String, double> tasas = const {'USD': 400, 'MLC': 120},
}) async {
  final config = buildTestConfig(monedaBase: monedaBase, tasas: tasas);
  final sync = FakeSyncService(
    destinations: [
      TransferDestinationModel(id: 'd1', nombre: 'Banco', isDefault: true),
    ],
  );
  final cart = CartModel(
    id: 'c1',
    nombre: 'Carrito',
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
    buildPaymentModalHarness(
      config: config,
      cart: cart,
      syncService: sync,
      monedaBase: monedaBase,
    ),
  );
  await tester.pumpAndSettle();
}

Finder get cashField => find.widgetWithText(TextField, 'Efectivo');
Finder get transferField => find.widgetWithText(TextField, 'Transferencia');
