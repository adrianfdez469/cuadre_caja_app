import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/core/theme/app_tokens.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';
import 'package:cuadre_caja_app/providers/cart_provider.dart';
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/providers/ventas_provider.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/pos_actions_sheet.dart';

import '../../fakes/test_fakes.dart';

VentaLocalModel _local(SyncState syncState) => VentaLocalModel(
      syncId: 'v-${syncState.name}',
      tiendaId: 't1',
      periodoId: 'p1',
      productos: const [],
      total: 10,
      totalcash: 10,
      createdAt: 0,
      syncState: syncState,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Abre la hoja con los contadores ya cargados en `VentasProvider`.
  Future<void> abrirHoja(
    WidgetTester tester, {
    List<VentaLocalModel> pendientes = const [],
    int cancelacionesPendientes = 0,
    int cancelacionesRechazadas = 0,
  }) async {
    final syncService = FakeSyncService(
      ventasLocal: FakeVentasLocalDataSource(
        pendientes: pendientes,
        cancelacionesPendientes: cancelacionesPendientes,
        cancelacionesRechazadas: cancelacionesRechazadas,
      ),
    );
    final ventasProvider = VentasProvider(syncService);
    await ventasProvider.refreshPendientes();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ventasProvider),
          ChangeNotifierProvider(create: (_) => SyncProvider(syncService)),
          ChangeNotifierProvider(
            create: (_) => CartProvider(FakeCartLocalDataSource()),
          ),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PosActionsSheet.show(context, onSync: () {}),
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

  testWidgets('sin nada pendiente el menú no inventa avisos', (tester) async {
    await abrirHoja(tester);

    expect(find.text('Ventas y sincronizaciones'), findsOneWidget);
    expect(find.textContaining('con error'), findsNothing);
    expect(find.textContaining('sin subir'), findsNothing);
  });

  testWidgets('lo que sólo espera conexión se cuenta como "sin subir"',
      (tester) async {
    await abrirHoja(
      tester,
      pendientes: [_local(SyncState.pending)],
      cancelacionesPendientes: 1,
    );

    expect(find.text('2 sin subir'), findsOneWidget);
    // Sin errores, la fila de sincronizar conserva su subtítulo de siempre.
    expect(find.text('Sin conexión'), findsOneWidget);
  });

  testWidgets('un rechazo del servidor manda sobre el mensaje de sync',
      (tester) async {
    await abrirHoja(
      tester,
      pendientes: [_local(SyncState.pending), _local(SyncState.error)],
      cancelacionesRechazadas: 1,
    );

    expect(find.text('2 ventas con error'), findsOneWidget);
    expect(find.text('2 con error · 1 sin subir'), findsOneWidget);
    expect(find.text('Sin conexión'), findsNothing);
  });

  testWidgets('el singular no se pluraliza', (tester) async {
    await abrirHoja(tester, pendientes: [_local(SyncState.error)]);

    expect(find.text('1 venta con error'), findsOneWidget);
    expect(find.text('1 con error'), findsOneWidget);
  });

  testWidgets('el badge de error se pinta en rojo, no en ámbar',
      (tester) async {
    await abrirHoja(
      tester,
      pendientes: [_local(SyncState.error), _local(SyncState.pending)],
    );

    final badge = tester.widget<Container>(
      find
          .ancestor(of: find.text('1').first, matching: find.byType(Container))
          .first,
    );
    expect(
      (badge.decoration as BoxDecoration).color,
      AppSemanticColors.light.negativeWash,
    );
  });
}
