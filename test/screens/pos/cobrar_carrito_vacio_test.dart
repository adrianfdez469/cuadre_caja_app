import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
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

/// Vaciar el carrito **desde** la pantalla de cobro dejaba cobrando una venta
/// que ya no existía: el total caía a 0, el pago sembrado seguía puesto y
/// "Vender" registraba una venta de 0 sin productos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Cobro empujado como ruta sobre una pantalla base, que es como se abre en
  /// la app: montarlo como `home` haría que el pop no tuviera a dónde ir.
  Future<CartProvider> pumpCobrarSobreBase(
    WidgetTester tester, {
    required List<CartItemModel> items,
  }) async {
    final sync = FakeSyncService();
    final cartProvider = CartProvider(FakeCartLocalDataSource())
      ..debugSetActiveCart(
        CartModel(id: 'c1', nombre: 'Cuenta #1', items: items),
      );
    final periodoProvider = PeriodoProvider(sync);
    await periodoProvider.loadPeriodo('t1');

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
          ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
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
    return cartProvider;
  }

  CartItemModel item(String id, {double precio = 1000, double cantidad = 1}) =>
      CartItemModel(
        productoTiendaId: id,
        nombre: 'Producto $id',
        precio: precio,
        monedaPrecioCode: 'CUP',
        cantidad: cantidad,
      );

  /// Abre el detalle de la cuenta desde el cobro.
  Future<void> abrirCarrito(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.shopping_cart));
    await tester.pumpAndSettle();
  }

  testWidgets('quitar el último producto cierra el cobro y vuelve al inicio',
      (tester) async {
    await pumpCobrarSobreBase(tester, items: [item('p1')]);
    expect(find.text('Cobrar'), findsWidgets);

    await abrirCarrito(tester);
    // Bajar la única unidad elimina la línea y deja la cuenta vacía.
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pumpAndSettle();

    // El carrito se cierra solo, y el cobro detrás también: se vuelve al inicio.
    expect(find.text('ir a cobrar'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart), findsNothing);
  });

  testWidgets('con la cuenta vacía no se puede vender', (tester) async {
    final cartProvider = await pumpCobrarSobreBase(tester, items: [item('p1')]);

    // Se vacía por detrás (sin pasar por el carrito) para dejar la pantalla en
    // el estado exacto que habilitaba la venta de 0.
    cartProvider.debugSetActiveCart(
      CartModel(id: 'c1', nombre: 'Cuenta #1', items: []),
    );
    await tester.pumpAndSettle();

    final vender = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Vender'),
        matching: find.byType(ElevatedButton),
      ).first,
    );
    expect(vender.onPressed, isNull, reason: 'no se vende una cuenta vacía');
  });

  testWidgets('quitar un producto recalcula lo que paga el cliente',
      (tester) async {
    await pumpCobrarSobreBase(
      tester,
      items: [item('p1', precio: 1000), item('p2', precio: 500)],
    );
    // Total 1500: el pago se siembra con el total redondeado.
    expect(montoDe(tester, cashFieldDe('CUP')), '1500');

    await abrirCarrito(tester);
    await tester.tap(find.byIcon(Icons.remove).last);
    await tester.pumpAndSettle();
    // Cerrar el carrito para volver al cobro.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(
      montoDe(tester, cashFieldDe('CUP')),
      '1000',
      reason: 'el monto del cliente sigue al nuevo total',
    );
  });
}
