import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/data/models/periodo_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';
import 'package:cuadre_caja_app/providers/auth_provider.dart';
import 'package:cuadre_caja_app/providers/periodo_provider.dart';
import 'package:cuadre_caja_app/providers/productos_provider.dart';
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/providers/ventas_provider.dart';
import 'package:cuadre_caja_app/screens/pos/productos_vendidos_screen.dart';
import 'package:cuadre_caja_app/screens/pos/ventas_list_screen.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';

import '../../fakes/test_fakes.dart';
import '../../helpers/payment_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('es', null);
    await initializeDateFormatting('es_CO', null);
  });

  ProductoModel producto(String id) => ProductoModel(
    id: id,
    productoId: 'p-$id',
    nombre: id,
    precio: 100,
    costo: 50,
    existencia: 10,
  );

  VentaProducto linea() => VentaProducto(
    productoTiendaId: 'cola',
    cantidad: 2,
    precio: 100,
    name: 'cola',
  );

  /// Una venta que ya está en el servidor y no tiene fila local: el caso más
  /// común de la lista, y el que antes pintaba un separador y una fila de
  /// acciones vacíos.
  VentaServerModel ventaDelServidor(String id) => VentaServerModel(
    id: id,
    tiendaId: 't1',
    cierrePeriodoId: 'p1',
    usuarioId: 'u1',
    total: 200,
    totalcash: 200,
    createdAt: DateTime.now(),
    productos: [linea()],
  );

  VentaLocalModel ventaLocal(String syncId, SyncState estado) =>
      VentaLocalModel(
        syncId: syncId,
        tiendaId: 't1',
        periodoId: 'p1',
        productos: [linea()],
        total: 200,
        totalcash: 200,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        syncState: estado,
        errorMessage: estado == SyncState.error
            ? 'El servidor la rechazó'
            : null,
      );

  Future<List<SingleChildWidget>> proveedores(FakeSyncService sync) async {
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
      ChangeNotifierProvider<ProductosProvider>.value(value: productosProvider),
      ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider(sync)),
      Provider<SyncService>.value(value: sync),
    ];
  }

  Widget app(Widget child, List<SingleChildWidget> providers) => MultiProvider(
    providers: providers,
    child: MaterialApp(theme: appLightTheme, home: child),
  );

  FakeSyncService fake({
    List<VentaServerModel> servidor = const [],
    List<VentaLocalModel> locales = const [],
  }) => FakeSyncService(
    productos: [producto('cola')],
    ventasServidor: servidor,
    periodoAbierto: PeriodoModel(
      id: 'p1',
      tiendaId: 't1',
      fechaInicio: DateTime.now(),
      estaAbierto: true,
    ),
    // La lista unificada lee el período por `getVentasByPeriodo`.
    ventasLocal: FakeVentasLocalDataSource(
      pendientes: locales,
      delPeriodo: locales,
    ),
  );

  group('Ventas y sincronizaciones', () {
    testWidgets('una venta ya sincronizada no muestra acciones', (
      tester,
    ) async {
      final sync = fake(servidor: [ventaDelServidor('v1')]);
      await tester.pumpWidget(
        app(const VentasListScreen(), await proveedores(sync)),
      );
      await tester.pumpAndSettle();

      // Ni sincronizar, ni anular, ni ver el error: sin acciones no se pinta la
      // fila que las contiene.
      expect(find.byType(IconButton), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.text('Sincronizada'), findsOneWidget);
    });

    testWidgets('el resumen dice cuántas hay y cuánto suman', (tester) async {
      final sync = fake(
        servidor: [ventaDelServidor('v1'), ventaDelServidor('v2')],
      );
      await tester.pumpWidget(
        app(const VentasListScreen(), await proveedores(sync)),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 ventas'), findsOneWidget);
      expect(find.textContaining('2 sincronizadas'), findsOneWidget);
    });

    testWidgets('el filtro "Con error" deja sólo lo que hay que revisar', (
      tester,
    ) async {
      final sync = fake(
        servidor: [ventaDelServidor('v1')],
        locales: [ventaLocal('v2', SyncState.error)],
      );
      await tester.pumpWidget(
        app(const VentasListScreen(), await proveedores(sync)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sincronizada'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);

      await tester.tap(find.textContaining('Con error'));
      await tester.pumpAndSettle();

      expect(find.text('Sincronizada'), findsNothing);
      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('sin ventas pendientes no aparece la barra de filtros', (
      tester,
    ) async {
      final sync = fake(servidor: [ventaDelServidor('v1')]);
      await tester.pumpWidget(
        app(const VentasListScreen(), await proveedores(sync)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Todas'), findsNothing);
    });
  });

  group('Productos vendidos', () {
    testWidgets('al entrar dice que sólo muestra tus ventas', (tester) async {
      // El filtro de vendedor arranca acotado al usuario actual; el problema
      // era que no se veía por ningún lado.
      final sync = fake(servidor: [ventaDelServidor('v1')]);
      await tester.pumpWidget(
        app(const ProductosVendidosScreen(), await proveedores(sync)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Tus ventas · todos los proveedores'),
        findsOneWidget,
      );
    });

    testWidgets('quitar el filtro de vendedor cambia el alcance y el total', (
      tester,
    ) async {
      final sync = fake(servidor: [ventaDelServidor('v1')]);
      await tester.pumpWidget(
        app(const ProductosVendidosScreen(), await proveedores(sync)),
      );
      await tester.pumpAndSettle();

      // La venta es de 'u1' — el mismo usuario de prueba — así que ya entra.
      expect(find.textContaining('Tus ventas'), findsOneWidget);

      await tester.tap(find.text('Cambiar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos').first);
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Todas las ventas'), findsOneWidget);
    });
  });
}
