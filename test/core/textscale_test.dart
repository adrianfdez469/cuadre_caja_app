import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/core/theme/app_tokens.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/providers/venta_sin_stock_provider.dart';
import 'package:cuadre_caja_app/screens/pos/cart_items_screen.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/quantity_sheet.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/scanner_cart_panel.dart';
import 'package:cuadre_caja_app/widgets/numeric_keypad.dart';

import '../fakes/test_fakes.dart';
import '../helpers/payment_test_harness.dart';

/// El POS acota el escalado de fuente del sistema a [maxTextScale] (ver el
/// `builder` de `MaterialApp` en `main.dart`). Estos tests renderizan a esa
/// escala y exigen que no salte ninguna excepción: Flutter reporta el
/// desbordamiento de un `RenderFlex` como excepción, así que un overflow hace
/// fallar el test en vez de quedarse en un rayado amarillo que nadie mira.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final escalaMaxima = TextScaler.linear(maxTextScale);

  ProductoModel producto(String id, String nombre) => ProductoModel(
        id: id,
        productoId: 'p-$id',
        nombre: nombre,
        precio: 1234.56,
        costo: 50,
        existencia: 50,
      );

  CartItemModel item(String id, String nombre, {double cantidad = 1}) =>
      CartItemModel(
        productoTiendaId: id,
        nombre: nombre,
        precio: 1234.56,
        monedaPrecioCode: 'CUP',
        cantidad: cantidad,
      );

  /// Nombres largos a propósito: el texto que desborda es el que no cabe, y con
  /// "Pan" no desborda nada ni al doble de tamaño.
  const nombreLargo = 'Refresco de cola 2 litros - Distribuidora del Sur';

  /// Superficie de móvil: la de por defecto (800×600) es más ancha y más baja
  /// que un teléfono y no representa el caso real.
  void superficieMovil(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget conEscala(
    Widget child, {
    List<SingleChildWidget> providers = const [],
  }) {
    // `MultiProvider` no admite una lista vacía de providers.
    Widget conProviders(Widget hijo) => providers.isEmpty
        ? hijo
        : MultiProvider(providers: providers, child: hijo);

    return conProviders(
      MaterialApp(
        theme: appLightTheme,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: escalaMaxima),
          child: inner!,
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  group('a escala $maxTextScale× no desborda', () {
    testWidgets('el carrito', (tester) async {
      superficieMovil(tester);

      final sync = FakeSyncService(
        productos: [producto('a', nombreLargo), producto('b', 'Pan integral')],
      );
      final cartProvider = CartProvider(FakeCartLocalDataSource());
      await cartProvider.init('t1');
      await cartProvider.addToCart(producto('a', nombreLargo), cantidad: 12);
      await cartProvider.addToCart(producto('b', 'Pan integral'), cantidad: 3);
      final productosProvider = ProductosProvider(sync);
      await productosProvider.loadProductos('t1');

      await tester.pumpWidget(conEscala(
        CartPanel(onClose: () {}),
        providers: [
          ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
          ChangeNotifierProvider<ProductosProvider>.value(
            value: productosProvider,
          ),
          ChangeNotifierProvider<MonedasProvider>.value(
            value: MonedasProvider(sync)..debugSetConfig(buildTestConfig()),
          ),
          ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider(sync)),
          ChangeNotifierProvider<VentaSinStockProvider>(
            create: (_) => VentaSinStockProvider(),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('el panel del escáner', (tester) async {
      superficieMovil(tester);

      final sync = FakeSyncService(productos: [producto('a', nombreLargo)]);
      final cartProvider = CartProvider(FakeCartLocalDataSource());
      await cartProvider.init('t1');
      cartProvider.debugSetActiveCart(
        CartModel(
          id: 'c1',
          nombre: 'Cuenta #1',
          items: [item('a', nombreLargo, cantidad: 12)],
        ),
      );
      final productosProvider = ProductosProvider(sync);
      await productosProvider.loadProductos('t1');

      await tester.pumpWidget(conEscala(
        ScannerCartPanel(
          scrollController: ScrollController(),
          highlightedId: ValueNotifier<String?>(null),
          onSaleCompleted: () {},
          onHandleTap: () {},
        ),
        providers: [
          ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
          ChangeNotifierProvider<ProductosProvider>.value(
            value: productosProvider,
          ),
          ChangeNotifierProvider<MonedasProvider>.value(
            value: MonedasProvider(sync)..debugSetConfig(buildTestConfig()),
          ),
          ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider(sync)),
          ChangeNotifierProvider<VentaSinStockProvider>(
            create: (_) => VentaSinStockProvider(),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('el teclado numérico', (tester) async {
      superficieMovil(tester);

      await tester.pumpWidget(conEscala(
        NumericKeypad(cornerLabel: '00', onDigit: (_) {}, onBackspace: () {}),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('la hoja de cantidad', (tester) async {
      superficieMovil(tester);

      final p = producto('a', nombreLargo);
      final sync = FakeSyncService(productos: [p]);
      final productosProvider = ProductosProvider(sync);
      await productosProvider.loadProductos('t1');
      final cartProvider = CartProvider(FakeCartLocalDataSource());
      await cartProvider.init('t1');

      await tester.pumpWidget(conEscala(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                QuantitySheet.show(context, producto: p, permitirSinStock: false),
            child: const Text('abrir'),
          ),
        ),
        providers: [
          ChangeNotifierProvider<ProductosProvider>.value(
            value: productosProvider,
          ),
          ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
          ChangeNotifierProvider<MonedasProvider>.value(
            value: MonedasProvider(sync)..debugSetConfig(buildTestConfig()),
          ),
        ],
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('la pantalla de cobro', (tester) async {
      superficieMovil(tester);

      final sync = FakeSyncService(
        destinations: const [],
        productos: [producto('a', nombreLargo)],
      );

      await tester.pumpWidget(buildCobrarScreenHarness(
        config: buildTestConfig(),
        cart: CartModel(
          id: 'c1',
          nombre: 'Cuenta #1',
          items: [item('a', nombreLargo, cantidad: 3)],
        ),
        syncService: sync,
        textScaler: escalaMaxima,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
