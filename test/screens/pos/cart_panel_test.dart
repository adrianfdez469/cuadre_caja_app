import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/providers/venta_sin_stock_provider.dart';
import 'package:cuadre_caja_app/screens/pos/cart_items_screen.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/cobrar_button.dart';

import '../../fakes/test_fakes.dart';
import '../../helpers/payment_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProductoModel producto(String id, String nombre) => ProductoModel(
        id: id,
        productoId: 'p-$id',
        nombre: nombre,
        precio: 100,
        costo: 50,
        existencia: 50,
      );

  /// Monta [CartPanel] como ruta a pantalla completa, con un provider ya
  /// inicializado (o sea, con la cuenta principal creada por `init`).
  Future<CartProvider> pumpPanel(
    WidgetTester tester, {
    /// Unidades a agregar a la cuenta activa, por producto.
    Map<String, double> unidades = const {},
    int cuentas = 1,
    VoidCallback? onClose,
    /// Productos que se dejan en la cuenta principal antes de volver a la
    /// última, para probar el salto entre cuentas.
    Map<String, double>? unidadesOtraCuenta,
  }) async {
    final sync = FakeSyncService(
      productos: [producto('a', 'Cerveza'), producto('b', 'Pan')],
    );
    final cartProvider = CartProvider(FakeCartLocalDataSource());
    await cartProvider.init('t1');
    for (var i = 1; i < cuentas; i++) {
      await cartProvider.createNextCart();
    }
    for (final entry in unidades.entries) {
      await cartProvider.addToCart(
        producto(entry.key, entry.key == 'a' ? 'Cerveza' : 'Pan'),
        cantidad: entry.value,
      );
    }
    if (unidadesOtraCuenta != null) {
      cartProvider.switchCart(0);
      for (final entry in unidadesOtraCuenta.entries) {
        await cartProvider.addToCart(
          producto(entry.key, entry.key == 'a' ? 'Cerveza' : 'Pan'),
          cantidad: entry.value,
        );
      }
      cartProvider.switchCart(cartProvider.cartCount - 1);
    }

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
          ChangeNotifierProvider<VentaSinStockProvider>(
            create: (_) => VentaSinStockProvider(),
          ),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: Scaffold(body: CartPanel(onClose: onClose ?? () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cartProvider;
  }

  bool itemHabilitado(WidgetTester tester, String label) {
    return tester
        .widget<PopupMenuItem<String>>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(PopupMenuItem<String>),
          ),
        )
        .enabled;
  }

  group('resumen "EN LA VENTA"', () {
    testWidgets('cuenta unidades, no líneas distintas', (tester) async {
      await pumpPanel(tester, unidades: {'a': 2, 'b': 3});

      // Son 2 líneas pero 5 unidades: antes decía "2 ARTÍCULOS".
      expect(find.text('EN LA VENTA · 5 ARTÍCULOS'), findsOneWidget);
    });

    testWidgets('usa singular con una sola unidad', (tester) async {
      await pumpPanel(tester, unidades: {'a': 1});

      expect(find.text('EN LA VENTA · 1 ARTÍCULO'), findsOneWidget);
    });
  });

  group('botón de cobro', () {
    testWidgets('la acción y el conteo son textos separados', (tester) async {
      await pumpPanel(tester, unidades: {'a': 2, 'b': 3});

      // Concatenados en un solo Text el conteo salía en negrita, igual que
      // "Cobrar"; separados cada uno lleva su peso.
      expect(find.text('Cobrar'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CobrarButton),
          matching: find.text('5 artículos'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin productos el botón no muestra conteo', (tester) async {
      await pumpPanel(tester);

      expect(find.text('Cobrar'), findsOneWidget);
      // El "0 artículos" del pie sigue ahí; el botón es el que no lo repite.
      expect(
        find.descendant(
          of: find.byType(CobrarButton),
          matching: find.text('0 artículos'),
        ),
        findsNothing,
      );
    });
  });

  group('menú de la cuenta', () {
    testWidgets('la cabecera ya no tiene el botón de 3 puntos', (tester) async {
      await pumpPanel(tester, unidades: {'a': 1});

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('el chip activo despliega las tres acciones', (tester) async {
      await pumpPanel(tester, unidades: {'a': 1});

      await tester.tap(find.text('Cuenta #1'));
      await tester.pumpAndSettle();

      expect(find.text('Cambiar nombre'), findsOneWidget);
      expect(find.text('Vaciar carrito'), findsOneWidget);
      expect(find.text('Cerrar cuenta'), findsOneWidget);
    });

    testWidgets('en la cuenta principal solo se puede vaciar', (tester) async {
      await pumpPanel(tester, unidades: {'a': 1});

      await tester.tap(find.text('Cuenta #1'));
      await tester.pumpAndSettle();

      expect(itemHabilitado(tester, 'Cambiar nombre'), isFalse);
      expect(itemHabilitado(tester, 'Vaciar carrito'), isTrue);
      expect(itemHabilitado(tester, 'Cerrar cuenta'), isFalse);
    });

    testWidgets('en las demás cuentas se puede renombrar y cerrar',
        (tester) async {
      await pumpPanel(tester, cuentas: 2, unidades: {'a': 1});

      await tester.tap(find.text('Cuenta #2'));
      await tester.pumpAndSettle();

      expect(itemHabilitado(tester, 'Cambiar nombre'), isTrue);
      expect(itemHabilitado(tester, 'Cerrar cuenta'), isTrue);
    });

    testWidgets('vaciar queda deshabilitado con la cuenta vacía',
        (tester) async {
      await pumpPanel(tester, cuentas: 2);

      await tester.tap(find.text('Cuenta #2'));
      await tester.pumpAndSettle();

      expect(itemHabilitado(tester, 'Vaciar carrito'), isFalse);
    });
  });

  group('vaciar la cuenta', () {
    testWidgets('cierra la vista ampliada al terminar', (tester) async {
      var cerrada = false;
      await pumpPanel(
        tester,
        unidades: {'a': 1},
        onClose: () => cerrada = true,
      );

      await tester.tap(find.text('Cuenta #1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vaciar carrito'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Vaciar'));
      await tester.pumpAndSettle();

      // Con la cuenta vacía no queda nada que mirar acá: se vuelve al catálogo.
      expect(cerrada, isTrue);
    });

    testWidgets('cancelar no cierra nada ni vacía', (tester) async {
      var cerrada = false;
      final provider = await pumpPanel(
        tester,
        unidades: {'a': 1},
        onClose: () => cerrada = true,
      );

      await tester.tap(find.text('Cuenta #1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vaciar carrito'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(cerrada, isFalse);
      expect(provider.activeCart!.isEmpty, isFalse);
    });
  });

  group('bajar la última unidad', () {
    testWidgets('quitar la última línea con "−" también cierra la vista',
        (tester) async {
      var cerrada = false;
      final provider = await pumpPanel(
        tester,
        unidades: {'a': 1},
        onClose: () => cerrada = true,
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(provider.activeCart!.isEmpty, isTrue);
      expect(cerrada, isTrue);
    });

    testWidgets('con otra línea todavía en la cuenta no cierra nada',
        (tester) async {
      var cerrada = false;
      final provider = await pumpPanel(
        tester,
        unidades: {'a': 1, 'b': 1},
        onClose: () => cerrada = true,
      );

      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pumpAndSettle();

      expect(provider.activeCart!.items.length, 1);
      expect(cerrada, isFalse);
    });

    testWidgets('bajar de 2 a 1 no cierra la vista', (tester) async {
      var cerrada = false;
      await pumpPanel(
        tester,
        unidades: {'a': 2},
        onClose: () => cerrada = true,
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(cerrada, isFalse);
    });
  });

  group('salto entre cuentas al vaciar', () {
    testWidgets('vaciar salta a la otra cuenta con productos y no cierra',
        (tester) async {
      var cerrada = false;
      final provider = await pumpPanel(
        tester,
        cuentas: 2,
        unidades: {'a': 1},
        unidadesOtraCuenta: {'b': 2},
        onClose: () => cerrada = true,
      );

      await tester.tap(find.text('Cuenta #2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vaciar carrito'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Vaciar'));
      await tester.pumpAndSettle();

      expect(provider.activeCart!.nombre, 'Cuenta #1');
      expect(cerrada, isFalse);
      expect(find.text('EN LA VENTA · 2 ARTÍCULOS'), findsOneWidget);
    });

    testWidgets('bajar la última unidad salta a la otra cuenta con productos',
        (tester) async {
      var cerrada = false;
      final provider = await pumpPanel(
        tester,
        cuentas: 2,
        unidades: {'a': 1},
        unidadesOtraCuenta: {'b': 2},
        onClose: () => cerrada = true,
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(provider.activeCart!.nombre, 'Cuenta #1');
      expect(cerrada, isFalse);
    });

    testWidgets('con todas las demás vacías sí cierra la vista',
        (tester) async {
      var cerrada = false;
      await pumpPanel(
        tester,
        cuentas: 2,
        unidades: {'a': 1},
        onClose: () => cerrada = true,
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(cerrada, isTrue);
    });
  });

  group('crear cuenta', () {
    testWidgets('el "+" crea la siguiente y cierra la vista sin preguntar',
        (tester) async {
      var cerrada = false;
      final sync = FakeSyncService(productos: [producto('a', 'Cerveza')]);
      final cartProvider = CartProvider(FakeCartLocalDataSource());
      await cartProvider.init('t1');
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
            ChangeNotifierProvider<SyncProvider>(
              create: (_) => SyncProvider(sync),
            ),
            ChangeNotifierProvider<VentaSinStockProvider>(
              create: (_) => VentaSinStockProvider(),
            ),
          ],
          child: MaterialApp(
            theme: appLightTheme,
            home: Scaffold(body: CartPanel(onClose: () => cerrada = true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Sin diálogo de nombre de por medio.
      expect(find.byType(AlertDialog), findsNothing);
      expect(cartProvider.cartCount, 2);
      expect(cartProvider.activeCart!.nombre, 'Cuenta #2');
      expect(cerrada, isTrue);
    });
  });
}
