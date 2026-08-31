import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/core/theme/app_tokens.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/pos_checkout_bar.dart';

import '../../fakes/test_fakes.dart';
import '../../helpers/payment_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpBarra(WidgetTester tester) async {
    final producto = ProductoModel(
      id: 'a',
      productoId: 'p-a',
      nombre: 'Cerveza',
      precio: 100,
      costo: 50,
      existencia: 50,
    );
    final sync = FakeSyncService(productos: [producto]);
    final cartProvider = CartProvider(FakeCartLocalDataSource());
    await cartProvider.init('t1');
    await cartProvider.addToCart(producto, cantidad: 2);
    final productosProvider = ProductosProvider(sync);
    await productosProvider.loadProductos('t1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
          ChangeNotifierProvider<ProductosProvider>.value(
            value: productosProvider,
          ),
          ChangeNotifierProvider<MonedasProvider>.value(
            value: MonedasProvider(sync)..debugSetConfig(buildTestConfig()),
          ),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: const Scaffold(
            body: Column(children: [Spacer(), PosCheckoutBar()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Caja realmente pintada del botón (su `Material`), no el área táctil que
  /// Material puede acolchar por fuera.
  Rect cajaVisible(WidgetTester tester, Finder boton) => tester.getRect(
        find.descendant(of: boton, matching: find.byType(Material)).first,
      );

  testWidgets('el botón de la cuenta mide lo mismo que "Vaciar"',
      (tester) async {
    await pumpBarra(tester);

    final cuenta = find.ancestor(
      of: find.textContaining('Cuenta'),
      matching: find.byType(TextButton),
    );
    final vaciar = find.widgetWithText(TextButton, 'Vaciar');

    // Van pegados en la misma fila: cualquier diferencia de alto se ve. Antes
    // uno era un recuadro dibujado a mano y el otro un botón de Material.
    expect(cajaVisible(tester, cuenta).height, AppTapTarget.min);
    expect(cajaVisible(tester, cuenta).height, cajaVisible(tester, vaciar).height);
    expect(cajaVisible(tester, cuenta).top, cajaVisible(tester, vaciar).top);
    expect(cajaVisible(tester, cuenta).bottom, cajaVisible(tester, vaciar).bottom);
  });

  testWidgets('el botón de la cuenta muestra solo el nombre de la cuenta',
      (tester) async {
    await pumpBarra(tester);

    // "A cobrar" sobraba: el botón cambia de cuenta, y justo debajo están el
    // total y el botón de cobrar.
    expect(find.textContaining('A cobrar'), findsNothing);
    expect(find.text('Cuenta #1'), findsOneWidget);
  });
}
