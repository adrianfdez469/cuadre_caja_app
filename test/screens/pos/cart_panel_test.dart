import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/core/theme/app_tokens.dart';
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

  group('editar la cantidad tocando la línea', () {
    /// La hoja de cantidad no cabe en la superficie por defecto de los tests
    /// (800×600) y desborda en layout; se usa una de móvil, igual que hace
    /// `quantity_sheet_test.dart`.
    void superficieMovil(WidgetTester tester) {
      tester.view.physicalSize = const Size(420, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    /// Toca la línea del producto y espera a que abra la hoja de cantidad.
    Future<void> abrirHoja(WidgetTester tester, String nombre) async {
      await tester.tap(find.text(nombre));
      await tester.pumpAndSettle();
    }

    /// Pulsa una tecla del teclado numérico de la hoja.
    Future<void> tecla(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(InkWell, label).last);
      await tester.pump();
    }

    Future<void> confirmar(WidgetTester tester) async {
      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pumpAndSettle();
    }

    testWidgets('tocar la línea abre la hoja con la cantidad actual',
        (tester) async {
      superficieMovil(tester);
      await pumpPanel(tester, unidades: {'a': 3});

      await abrirHoja(tester, 'Cerveza');

      expect(find.text('Guardar 3'), findsOneWidget);
    });

    testWidgets('guardar una cantidad nueva la aplica al carrito',
        (tester) async {
      superficieMovil(tester);
      // Doce unidades eran doce toques en "+"; ahora se teclean.
      final provider = await pumpPanel(tester, unidades: {'a': 1});

      await abrirHoja(tester, 'Cerveza');
      await tecla(tester, '1');
      await tecla(tester, '2');
      await confirmar(tester);

      expect(provider.activeCart!.items.single.cantidad, 12);
    });

    testWidgets('guardar cero quita la línea y cierra la vista si queda vacía',
        (tester) async {
      superficieMovil(tester);
      var cerrada = false;
      final provider = await pumpPanel(
        tester,
        unidades: {'a': 1},
        onClose: () => cerrada = true,
      );

      await abrirHoja(tester, 'Cerveza');
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      await confirmar(tester);

      expect(provider.activeCart!.isEmpty, isTrue);
      expect(cerrada, isTrue, reason: 'mismo destino que el "−" en la última línea');
    });

    testWidgets('guardar cero con otra línea presente no cierra la vista',
        (tester) async {
      superficieMovil(tester);
      var cerrada = false;
      final provider = await pumpPanel(
        tester,
        unidades: {'a': 1, 'b': 2},
        onClose: () => cerrada = true,
      );

      await abrirHoja(tester, 'Cerveza');
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      await confirmar(tester);

      expect(provider.activeCart!.items.length, 1);
      expect(cerrada, isFalse);
    });

    testWidgets('cerrar la hoja sin confirmar no cambia nada', (tester) async {
      superficieMovil(tester);
      final provider = await pumpPanel(tester, unidades: {'a': 3});

      await abrirHoja(tester, 'Cerveza');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(provider.activeCart!.items.single.cantidad, 3);
    });
  });

  group('nombre del producto en la línea', () {
    testWidgets('admite dos líneas para no cortar el proveedor',
        (tester) async {
      // El carrito guarda "nombre - proveedor": con una sola línea, dos
      // productos del mismo nombre y distinto proveedor se veían idénticos.
      await pumpPanel(tester, unidades: {'a': 1});

      final texto = tester.widget<Text>(find.text('Cerveza'));
      expect(texto.maxLines, 2);
    });
  });

  group('accesibilidad de la línea del carrito', () {
    testWidgets('los −/+ cumplen el objetivo táctil mínimo', (tester) async {
      // Eran 36×36: por debajo de los 48 de Material, y son los controles más
      // pulsados de la app.
      await pumpPanel(tester, unidades: {'a': 2});

      for (final icono in [Icons.remove, Icons.add]) {
        final size = tester.getSize(
          find.ancestor(
            of: find.byIcon(icono),
            matching: find.byType(SizedBox),
          ).first,
        );
        expect(size.width, greaterThanOrEqualTo(AppTapTarget.min),
            reason: 'ancho de $icono');
        expect(size.height, greaterThanOrEqualTo(AppTapTarget.min),
            reason: 'alto de $icono');
      }
    });

    testWidgets('los −/+ dicen a TalkBack sobre qué producto actúan',
        (tester) async {
      // Antes eran iconos mudos: "botón" a secas, sin decir de qué producto.
      await pumpPanel(tester, unidades: {'a': 2});

      expect(find.bySemanticsLabel('Quitar una unidad de Cerveza'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Agregar una unidad de Cerveza'),
          findsOneWidget);
    });

    testWidgets('la línea se lee como una sola etiqueta con sentido',
        (tester) async {
      await pumpPanel(tester, unidades: {'a': 2});

      // Cantidad, nombre e importe juntos, en vez de tres fragmentos sueltos.
      expect(
        find.bySemanticsLabel(RegExp(r'^2 × Cerveza, ')),
        findsOneWidget,
      );
    });
  });

  group('alineación de la línea del carrito', () {
    /// El "+" del catálogo de cuentas usa el mismo ícono; los de las líneas son
    /// los únicos dentro de un `OutlinedButton`.
    Finder masDeLinea() => find.descendant(
          of: find.byType(OutlinedButton),
          matching: find.byIcon(Icons.add),
        );

    testWidgets('los −/+ caen en la misma columna aunque cambie el importe',
        (tester) async {
      // Dos líneas con importes de distinto largo: 100.00 y 5000.00.
      await pumpPanel(tester, unidades: {'a': 1, 'b': 50});

      final menos = find.byIcon(Icons.remove);
      final mas = masDeLinea();
      expect(menos, findsNWidgets(2));
      expect(mas, findsNWidgets(2));

      // Antes el importe y el nombre se repartían el espacio libre a mitades:
      // lo que al importe le sobraba quedaba como hueco a la derecha del "+",
      // así que los botones bailaban de una línea a otra.
      expect(tester.getRect(mas.at(0)).right, tester.getRect(mas.at(1)).right);
      expect(
        tester.getRect(menos.at(0)).right,
        tester.getRect(menos.at(1)).right,
      );
    });

    testWidgets('el importe va pegado a los botones, contra el borde derecho',
        (tester) async {
      await pumpPanel(tester, unidades: {'a': 1});

      final menos = tester.getRect(find.byType(OutlinedButton).at(0));
      final mas = tester.getRect(find.byType(OutlinedButton).at(1));
      final importe = tester.getRect(find.text('100.00'));

      // El bloque importe + − + + termina contra el borde derecho de la lista
      // (16 de padding), sin hueco sobrante que lo empuje hacia la izquierda.
      expect(
        mas.right,
        closeTo(tester.getRect(find.byType(CartPanel)).right - 16, 0.5),
      );
      expect(importe.right, closeTo(menos.left - 12, 0.5));
      // Y el nombre se queda con todo el ancho que el importe no usa: entre los
      // dos solo está el separador de 8.
      expect(
        tester.getRect(find.text('Cerveza')).right + 8,
        closeTo(importe.left, 0.5),
      );
    });
  });
}
