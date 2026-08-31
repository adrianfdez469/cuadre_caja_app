import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/widgets/multi_currency_amount.dart';

import '../fakes/test_fakes.dart';
import '../helpers/payment_test_harness.dart';

/// Reglas de la variante `checkout` (las tres barras de cobro: pantalla de
/// venta, vista del carrito y pantalla de cobro).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ancho = 600.0;

  /// Base de una línea tal como se ve en pantalla. `getRect` devuelve la caja
  /// ya transformada, así que si un `FittedBox` encogió el monto se nota en el
  /// alto y la base se escala en la misma proporción.
  double baseVisual(WidgetTester tester, Finder f) {
    final box = tester.renderObject<RenderBox>(f);
    final rect = tester.getRect(f);
    final base = box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
    return rect.top + base * (rect.height / box.size.height);
  }

  /// 1.0 mientras el monto se dibuje a su tamaño; menos si tuvo que encogerse.
  double escalaDelMonto(WidgetTester tester, Finder f) {
    final box = tester.renderObject<RenderBox>(f);
    return tester.getRect(f).height / box.size.height;
  }

  Future<void> pump(WidgetTester tester, double amount) async {
    final monedas = MonedasProvider(FakeSyncService())
      ..debugSetConfig(buildTestConfig());
    await tester.pumpWidget(
      ChangeNotifierProvider<MonedasProvider>.value(
        value: monedas,
        child: MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: ancho,
                child: MultiCurrencyAmount(
                  amount: amount,
                  variant: MultiCurrencyVariant.checkout,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final monto = find.textContaining('CUP');
  final usd = find.textContaining('USD');
  final mlc = find.textContaining('MLC');

  group('barra de cobro', () {
    testWidgets('la última conversión comparte línea de base con el monto',
        (tester) async {
      await pump(tester, 1500);

      // Alinear por el borde inferior de las cajas dejaba los números
      // desfasados: 38px de alto contra 12.5px no tienen el mismo descendente.
      expect(
        baseVisual(tester, monto),
        closeTo(baseVisual(tester, mlc), 0.5),
      );
    });

    testWidgets('las conversiones se apilan hacia arriba, en orden',
        (tester) async {
      await pump(tester, 1500);

      // MLC va después de USD en la configuración, así que es la de abajo: la
      // lista se invierte para que la última quede pegada a la base del monto.
      expect(tester.getRect(mlc).top, greaterThan(tester.getRect(usd).top));
    });

    testWidgets('las conversiones quedan pegadas al borde derecho',
        (tester) async {
      await pump(tester, 1500);

      final derecha = tester.getRect(find.byType(MultiCurrencyAmount)).right;
      expect(tester.getRect(usd).right, closeTo(derecha, 0.5));
      expect(tester.getRect(mlc).right, closeTo(derecha, 0.5));
    });

    testWidgets('el monto se queda con el ancho que las conversiones no usan',
        (tester) async {
      // Este importe ocupa más de la mitad de la barra: cuando monto y
      // conversiones eran los dos flexibles se repartían el espacio a mitades
      // exactas y el total se dibujaba encogido aunque al lado sobrara sitio.
      await pump(tester, 1500);

      expect(escalaDelMonto(tester, monto), 1.0);
      expect(
        tester.getRect(monto).left,
        closeTo(tester.getRect(find.byType(MultiCurrencyAmount)).left, 0.5),
      );
    });

    testWidgets('un total enorme se encoge en vez de desbordar', (tester) async {
      await pump(tester, 98765432.1);

      expect(escalaDelMonto(tester, monto), lessThan(1.0));
      expect(tester.takeException(), isNull);
    });
  });
}
