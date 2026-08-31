import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/core/theme/app_tokens.dart';
import 'package:cuadre_caja_app/data/datasources/remote/resumen_dia_remote_datasource.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/periodo_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/data/models/resumen_dia_model.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';
import 'package:cuadre_caja_app/providers/auth_provider.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/monedas_provider.dart';
import 'package:cuadre_caja_app/providers/periodo_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/providers/venta_sin_stock_provider.dart';
import 'package:cuadre_caja_app/providers/ventas_provider.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:cuadre_caja_app/screens/pos/cart_items_screen.dart';
import 'package:cuadre_caja_app/screens/pos/productos_vendidos_screen.dart';
import 'package:cuadre_caja_app/screens/pos/punto_de_partida_screen.dart';
import 'package:cuadre_caja_app/screens/pos/ventas_list_screen.dart';
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

  // Las vistas de consulta formatean fechas con locale 'es', igual que la app
  // real (ver `main.dart`). Sin esto, `DateFormat` lanza al primer render.
  setUpAll(() async {
    await initializeDateFormatting('es', null);
    await initializeDateFormatting('es_CO', null);
  });

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

      await tester.pumpWidget(
        conEscala(
          CartPanel(onClose: () {}),
          providers: [
            ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
            ChangeNotifierProvider<ProductosProvider>.value(
              value: productosProvider,
            ),
            ChangeNotifierProvider<MonedasProvider>.value(
              value: MonedasProvider(sync)..debugSetConfig(buildTestConfig()),
            ),
            ChangeNotifierProvider<SyncProvider>(
              create: (_) => SyncProvider(sync),
            ),
            ChangeNotifierProvider<VentaSinStockProvider>(
              create: (_) => VentaSinStockProvider(),
            ),
          ],
        ),
      );
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

      await tester.pumpWidget(
        conEscala(
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
            ChangeNotifierProvider<SyncProvider>(
              create: (_) => SyncProvider(sync),
            ),
            ChangeNotifierProvider<VentaSinStockProvider>(
              create: (_) => VentaSinStockProvider(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('el teclado numérico', (tester) async {
      superficieMovil(tester);

      await tester.pumpWidget(
        conEscala(
          NumericKeypad(cornerLabel: '00', onDigit: (_) {}, onBackspace: () {}),
        ),
      );
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

      await tester.pumpWidget(
        conEscala(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => QuantitySheet.show(
                context,
                producto: p,
                permitirSinStock: false,
              ),
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
        ),
      );
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

      await tester.pumpWidget(
        buildCobrarScreenHarness(
          config: buildTestConfig(),
          cart: CartModel(
            id: 'c1',
            nombre: 'Cuenta #1',
            items: [item('a', nombreLargo, cantidad: 3)],
          ),
          syncService: sync,
          textScaler: escalaMaxima,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    /// Las tres vistas de consulta del período comparten harness: una venta
    /// larga y cara, que es lo que desborda.
    VentaServerModel ventaServidor(String id) => VentaServerModel(
      id: id,
      tiendaId: 't1',
      cierrePeriodoId: 'p1',
      usuarioId: 'u1',
      total: 1234567.89,
      totalcash: 1000000,
      totaltransfer: 234567.89,
      createdAt: DateTime.now(),
      productos: [
        VentaProducto(
          productoTiendaId: 'a',
          cantidad: 12.5,
          precio: 98765.43,
          name: nombreLargo,
        ),
      ],
      usuarioNombre: 'Una cajera con nombre largo',
    );

    PeriodoModel periodoAbierto() => PeriodoModel(
      id: 'p1',
      tiendaId: 't1',
      fechaInicio: DateTime.now(),
      estaAbierto: true,
    );

    Future<List<SingleChildWidget>> proveedoresDeConsulta(
      FakeSyncService sync,
    ) async {
      final ventasProvider = VentasProvider(sync);
      await ventasProvider.loadVentasUnificado('t1', 'p1');
      final productosProvider = ProductosProvider(sync);
      await productosProvider.loadProductos('t1');
      final periodoProvider = PeriodoProvider(sync);
      await periodoProvider.loadPeriodo('t1');
      return [
        ChangeNotifierProvider<AuthProvider>.value(
          value: createTestAuthProvider()..debugSetUsuario(buildTestUsuario()),
        ),
        ChangeNotifierProvider<PeriodoProvider>.value(value: periodoProvider),
        ChangeNotifierProvider<VentasProvider>.value(value: ventasProvider),
        ChangeNotifierProvider<ProductosProvider>.value(
          value: productosProvider,
        ),
        ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider(sync)),
        Provider<SyncService>.value(value: sync),
      ];
    }

    testWidgets('la lista de ventas y sincronizaciones', (tester) async {
      superficieMovil(tester);

      final sync = FakeSyncService(
        productos: [producto('a', nombreLargo)],
        periodoAbierto: periodoAbierto(),
        ventasServidor: [ventaServidor('v1'), ventaServidor('v2')],
      );

      await tester.pumpWidget(
        conEscala(
          const VentasListScreen(),
          providers: await proveedoresDeConsulta(sync),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('productos vendidos', (tester) async {
      superficieMovil(tester);

      final sync = FakeSyncService(
        productos: [producto('a', nombreLargo)],
        periodoAbierto: periodoAbierto(),
        ventasServidor: [ventaServidor('v1')],
      );

      await tester.pumpWidget(
        conEscala(
          const ProductosVendidosScreen(),
          providers: await proveedoresDeConsulta(sync),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // La vista histórica añade una línea con fecha y estado bajo cada fila:
      // es la más apretada de las dos.
      await tester.tap(find.text('Histórica'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('punto de partida', (tester) async {
      superficieMovil(tester);

      final sync = FakeSyncService(
        productos: [producto('a', nombreLargo)],
        periodoAbierto: periodoAbierto(),
      );

      await tester.pumpWidget(
        conEscala(
          PuntoDePartidaScreen(
            datasource: FakeResumenDiaDataSource(nombreLargo),
          ),
          providers: await proveedoresDeConsulta(sync),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // La fila abierta despliega las cuatro cajas de movimientos en una sola
      // línea: el sitio más estrecho de la pantalla.
      await tester.tap(find.text(nombreLargo).first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

/// Devuelve un resumen sin tocar la red, para poder montar la pantalla en un
/// widget test.
class FakeResumenDiaDataSource extends ResumenDiaRemoteDataSource {
  final String nombre;

  FakeResumenDiaDataSource(this.nombre) : super(FakeApiClient());

  @override
  Future<ResumenDiaModel> getResumenDia({
    required String tiendaId,
    required String cierreId,
    bool soloConMovimientos = true,
  }) async => ResumenDiaModel(
    totales: const ResumenDiaTotales(
      ventas: 12345.5,
      entradas: 9876.5,
      salidas: 4321.5,
    ),
    productos: [
      ResumenDiaProducto(
        productoTiendaId: 'a',
        productoId: 'p-a',
        nombre: nombre,
        proveedorNombre: 'Distribuidora del Sur, S.A.',
        permiteDecimal: true,
        categoriaNombre: 'Bebidas y refrescos importados',
        categoriaColor: '#5B4CA8',
        tieneMovimientos: true,
        ultimaModificacion: DateTime.now(),
        cantidadInicial: 12345.5,
        ventas: 1234.5,
        entradas: 567.5,
        salidas: 89.5,
        cantidadFinal: 11588.0,
      ),
    ],
  );
}
