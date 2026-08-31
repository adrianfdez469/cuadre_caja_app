import 'package:flutter_test/flutter_test.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';
import 'package:cuadre_caja_app/providers/ventas_provider.dart';

import '../fakes/test_fakes.dart';

VentaProducto _item(String id, double cantidad) =>
    VentaProducto(productoTiendaId: id, cantidad: cantidad, precio: 10);

VentaServerModel _server({required String syncId, String id = 'srv-1'}) =>
    VentaServerModel(
      id: id,
      tiendaId: 't1',
      usuarioId: 'u1',
      cierrePeriodoId: 'p1',
      total: 10,
      totalcash: 10,
      syncId: syncId,
      createdAt: DateTime(2026, 8, 30),
      productos: [_item('A', 1)],
    );

VentaLocalModel _local({
  required String syncId,
  SyncState syncState = SyncState.synced,
  String? serverId = 'srv-1',
}) =>
    VentaLocalModel(
      syncId: syncId,
      tiendaId: 't1',
      periodoId: 'p1',
      productos: [_item('A', 1)],
      total: 10,
      totalcash: 10,
      createdAt: 0,
      syncState: syncState,
      serverId: serverId,
    );

void main() {
  group('VentasProvider.loadVentasUnificado', () {
    test('una venta propia ya sincronizada conserva su fila local', () async {
      // Llega por la rama del servidor (gana el dedupe) pero sí tiene fila
      // local: debe poder anularse.
      final sync = FakeSyncService(
        ventasServidor: [_server(syncId: 'sync-1')],
        ventasLocal: FakeVentasLocalDataSource(
          delPeriodo: [_local(syncId: 'sync-1')],
        ),
      );
      final provider = VentasProvider(sync);

      await provider.loadVentasUnificado('t1', 'p1');

      expect(provider.ventasUnificado, hasLength(1));
      final venta = provider.ventasUnificado.single;
      expect(venta.hasLocalRow, isTrue);
      expect(venta.puedeAnularse, isTrue);
    });

    test('una venta de otro dispositivo no ofrece anulación', () async {
      final sync = FakeSyncService(
        ventasServidor: [_server(syncId: 'sync-ajena')],
        ventasLocal: FakeVentasLocalDataSource(delPeriodo: const []),
      );
      final provider = VentasProvider(sync);

      await provider.loadVentasUnificado('t1', 'p1');

      final venta = provider.ventasUnificado.single;
      expect(venta.hasLocalRow, isFalse);
      expect(venta.puedeAnularse, isFalse);
    });

    test('el estado de anulación sobrevive al dedupe con el servidor', () async {
      // El servidor sigue devolviendo la venta (todavía no le hemos pedido el
      // DELETE): sin la superposición se listaría como "Sincronizada".
      final sync = FakeSyncService(
        ventasServidor: [_server(syncId: 'sync-1')],
        ventasLocal: FakeVentasLocalDataSource(
          delPeriodo: [
            _local(syncId: 'sync-1', syncState: SyncState.cancelPending),
          ],
        ),
      );
      final provider = VentasProvider(sync);

      await provider.loadVentasUnificado('t1', 'p1');

      final venta = provider.ventasUnificado.single;
      expect(venta.syncState, SyncState.cancelPending);
      expect(venta.puedeAnularse, isFalse);
    });

    test('una venta local no subida sigue apareciendo y se puede anular',
        () async {
      final sync = FakeSyncService(
        ventasServidor: const [],
        ventasLocal: FakeVentasLocalDataSource(
          delPeriodo: [
            _local(
              syncId: 'sync-offline',
              syncState: SyncState.pending,
              serverId: null,
            ),
          ],
        ),
      );
      final provider = VentasProvider(sync);

      await provider.loadVentasUnificado('t1', 'p1');

      final venta = provider.ventasUnificado.single;
      expect(venta.hasLocalRow, isTrue);
      expect(venta.puedeAnularse, isTrue);
      expect(venta.dbId, isNull, reason: 'el diálogo la trata como solo local');
    });
  });

  group('VentasProvider.pendingCount', () {
    test('suma las ventas por subir y las anulaciones por confirmar', () async {
      final sync = FakeSyncService(
        ventasLocal: FakeVentasLocalDataSource(
          pendientes: [_local(syncId: 'a', syncState: SyncState.pending)],
          cancelacionesPendientes: 2,
        ),
      );
      final provider = VentasProvider(sync);

      await provider.refreshPendientes();

      expect(provider.pendingCount, 3);
    });
  });
}
