import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/quantity_sheet.dart';

import '../../fakes/test_fakes.dart';
import '../../helpers/payment_test_harness.dart';

void main() {
  ProductoModel producto({bool fraccion = false, double existencia = 100}) =>
      ProductoModel(
        id: 'p1',
        productoId: 'pp1',
        nombre: fraccion ? 'Queso' : 'Cerveza',
        precio: 100,
        costo: 50,
        existencia: existencia,
        permiteDecimal: fraccion,
      );

  /// Abre la hoja de cantidad sobre un árbol mínimo de providers.
  ///
  /// La superficie por defecto de los tests (800×600) es más baja que un
  /// teléfono y la hoja desborda; se usa una de móvil.
  Future<void> pumpSheet(
    WidgetTester tester, {
    bool fraccion = false,
    double existencia = 100,
  }) async {
    tester.view.physicalSize = const Size(420, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = producto(fraccion: fraccion, existencia: existencia);
    final sync = FakeSyncService(productos: [p]);
    final productosProvider = ProductosProvider(sync);
    await productosProvider.loadProductos('t1');
    final monedas = MonedasProvider(sync)..debugSetConfig(buildTestConfig());
    final cartProvider = CartProvider(FakeCartLocalDataSource());
    await cartProvider.init('t1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProductosProvider>.value(value: productosProvider),
          ChangeNotifierProvider<MonedasProvider>.value(value: monedas),
          ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    QuantitySheet.show(context, producto: p, isOnline: true),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> tecla(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(InkWell, label).last);
    await tester.pump();
  }

  Finder confirmar() => find.byType(ElevatedButton).last;

  group('producto por unidades', () {
    testWidgets('teclear reemplaza la cantidad precargada', (tester) async {
      await pumpSheet(tester);
      expect(find.text('1'), findsWidgets);

      await tecla(tester, '5');

      // Antes el 5 se anexaba al 1 precargado.
      expect(find.text('5'), findsWidgets);
    });

    testWidgets('el borrado deja la cantidad en cero', (tester) async {
      await pumpSheet(tester);
      await tecla(tester, '7');

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(find.text('0'), findsWidgets);
    });

    testWidgets('con cantidad cero no se puede confirmar', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(tester.widget<ElevatedButton>(confirmar()).onPressed, isNull);
    });

    testWidgets('la tecla de esquina sigue siendo 00', (tester) async {
      await pumpSheet(tester, existencia: 1000);

      await tecla(tester, '2');
      await tecla(tester, '00');

      expect(find.text('200'), findsWidgets);
    });

    testWidgets('los saltos rápidos son de 10, 50 y 100', (tester) async {
      await pumpSheet(tester);

      expect(find.text('+10'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
      expect(find.text('+100'), findsOneWidget);
    });
  });

  group('producto por fracción', () {
    testWidgets('la tecla de esquina es un punto', (tester) async {
      await pumpSheet(tester, fraccion: true);

      expect(find.widgetWithText(InkWell, '.'), findsWidgets);
    });

    testWidgets('se teclea el número literal, con decimales', (tester) async {
      await pumpSheet(tester, fraccion: true);

      await tecla(tester, '1');
      await tecla(tester, '.');
      await tecla(tester, '5');

      // Antes los dígitos se leían como céntimos: "15" daba 0.15.
      expect(find.text('1.5'), findsWidgets);
    });

    testWidgets('no admite dos puntos', (tester) async {
      await pumpSheet(tester, fraccion: true);

      await tecla(tester, '1');
      await tecla(tester, '.');
      await tecla(tester, '.');
      await tecla(tester, '5');

      expect(find.text('1.5'), findsWidgets);
    });

    testWidgets('el borrado deja la cantidad en cero', (tester) async {
      await pumpSheet(tester, fraccion: true);
      await tecla(tester, '3');

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(find.text('0.00'), findsWidgets);
    });

    testWidgets('los saltos rápidos van de 0.1 a 10', (tester) async {
      await pumpSheet(tester, fraccion: true);

      for (final label in ['+0.1', '+0.5', '+1', '+10']) {
        expect(find.text(label), findsOneWidget, reason: 'falta $label');
      }
      for (final label in ['-0.1', '-0.5', '-1', '-10']) {
        expect(find.text(label), findsOneWidget, reason: 'falta $label');
      }
    });
  });
}
