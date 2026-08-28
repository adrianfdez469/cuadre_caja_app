import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/scanner_cart_panel.dart';

import '../../fakes/test_fakes.dart';
import '../../helpers/payment_test_harness.dart';

void main() {
  ProductoModel producto(String id, String nombre) => ProductoModel(
        id: id,
        productoId: 'p-$id',
        nombre: nombre,
        precio: 100,
        costo: 50,
        existencia: 50,
      );

  CartItemModel item(String id, String nombre, {double cantidad = 1}) =>
      CartItemModel(
        productoTiendaId: id,
        nombre: nombre,
        precio: 100,
        monedaPrecioCode: 'CUP',
        cantidad: cantidad,
      );

  /// Monta el panel con los providers que consume, tal como lo hace la pantalla
  /// del escáner.
  Future<CartProvider> pumpPanel(
    WidgetTester tester, {
    required List<CartItemModel> items,
    ValueNotifier<String?>? highlighted,
  }) async {
    final sync = FakeSyncService(
      productos: [
        producto('a', 'Cerveza'),
        producto('b', 'Pan'),
        producto('c', 'Refresco'),
      ],
    );
    final cartProvider = CartProvider(FakeCartLocalDataSource())
      ..debugSetActiveCart(
        CartModel(id: 'c-1', nombre: 'Carrito 1', items: items),
      );
    final productosProvider = ProductosProvider(sync);
    await productosProvider.loadProductos('t1');
    final monedas = MonedasProvider(sync)..debugSetConfig(buildTestConfig());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
          ChangeNotifierProvider<ProductosProvider>.value(
            value: productosProvider,
          ),
          ChangeNotifierProvider<MonedasProvider>.value(value: monedas),
          ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider(sync)),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: ScannerCartPanel(
              scrollController: ScrollController(),
              highlightedId: highlighted ?? ValueNotifier<String?>(null),
              onSaleCompleted: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cartProvider;
  }

  testWidgets('muestra los items en el orden del carrito', (tester) async {
    await pumpPanel(
      tester,
      items: [item('c', 'Refresco'), item('a', 'Cerveza'), item('b', 'Pan')],
    );

    final textos = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    expect(
      textos.indexOf('Refresco') < textos.indexOf('Cerveza'),
      isTrue,
      reason: 'el primero del carrito debe pintarse arriba',
    );
    expect(textos.indexOf('Cerveza') < textos.indexOf('Pan'), isTrue);
  });

  testWidgets('el botón + incrementa sin mover la fila', (tester) async {
    final cart = await pumpPanel(
      tester,
      items: [item('a', 'Cerveza'), item('b', 'Pan'), item('c', 'Refresco')],
    );

    // El "+" de la segunda fila (Pan).
    await tester.tap(find.byIcon(Icons.add_circle_outline).at(1));
    await tester.pumpAndSettle();

    expect(cart.activeCart!.items[1].cantidad, 2);
    expect(
      cart.activeCart!.items.map((i) => i.productoTiendaId).toList(),
      ['a', 'b', 'c'],
      reason: 'editar la cantidad no debe reordenar',
    );
  });

  testWidgets('el botón − elimina la fila al llegar al mínimo', (tester) async {
    final cart = await pumpPanel(
      tester,
      items: [item('a', 'Cerveza'), item('b', 'Pan', cantidad: 1)],
    );

    await tester.tap(find.byIcon(Icons.remove_circle_outline).at(1));
    await tester.pumpAndSettle();

    expect(
      cart.activeCart!.items.map((i) => i.productoTiendaId).toList(),
      ['a'],
    );
  });

  testWidgets('el encabezado nombra el carrito activo', (tester) async {
    await pumpPanel(tester, items: [item('a', 'Cerveza')]);

    expect(find.text('Carrito 1'), findsOneWidget);
    expect(find.text('1 ítem'), findsOneWidget);
    expect(find.text('Cobrar'), findsOneWidget);
  });

  testWidgets('con el carrito vacío invita a escanear y Cobrar se deshabilita',
      (tester) async {
    await pumpPanel(tester, items: []);

    expect(find.text('Escanea un producto para agregarlo'), findsOneWidget);
    final boton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Cobrar'),
    );
    expect(boton.onPressed, isNull);
  });
}
