import 'package:flutter_test/flutter_test.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';

VentaProducto _item(String id, double cantidad) =>
    VentaProducto(productoTiendaId: id, cantidad: cantidad, precio: 10);

VentaServerModel _server({String syncId = 'sync-1'}) => VentaServerModel(
      id: 'srv-1',
      tiendaId: 't1',
      usuarioId: 'u1',
      cierrePeriodoId: 'p1',
      total: 10,
      totalcash: 10,
      syncId: syncId,
      createdAt: DateTime(2026, 8, 30),
      usuarioNombre: 'Otro cajero',
      productos: [_item('A', 1)],
    );

VentaLocalModel _local({
  SyncState syncState = SyncState.synced,
  String? serverId = 'srv-1',
  String? errorMessage,
}) =>
    VentaLocalModel(
      syncId: 'sync-1',
      tiendaId: 't1',
      periodoId: 'p1',
      productos: [_item('A', 1)],
      total: 10,
      totalcash: 10,
      createdAt: 0,
      syncState: syncState,
      serverId: serverId,
      errorMessage: errorMessage,
    );

void main() {
  group('VentaUnificadaModel.fromServer', () {
    test('sin fila local no se puede anular desde este dispositivo', () {
      // Venta de otro cajero / otro dispositivo: antes el botón se ofrecía y no
      // hacía nada, pero decía "Venta eliminada".
      final venta = VentaUnificadaModel.fromServer(_server());

      expect(venta.hasLocalRow, isFalse);
      expect(venta.puedeAnularse, isFalse);
    });

    test('con fila local sí se puede anular', () {
      final venta = VentaUnificadaModel.fromServer(_server(), local: _local());

      expect(venta.hasLocalRow, isTrue);
      expect(venta.puedeAnularse, isTrue);
      expect(venta.syncState, SyncState.synced);
    });

    test('el estado de una anulación en curso lo pone la fila local', () {
      // El servidor todavía no sabe nada de la anulación: si ganara su versión,
      // la venta se listaría como "Sincronizada" y volvería a ofrecer el botón.
      final venta = VentaUnificadaModel.fromServer(
        _server(),
        local: _local(syncState: SyncState.cancelPending),
      );

      expect(venta.syncState, SyncState.cancelPending);
      expect(venta.enAnulacion, isTrue);
      expect(venta.puedeAnularse, isFalse,
          reason: 'no se pide dos veces la misma anulación');
      // Los datos ricos siguen viniendo del servidor.
      expect(venta.usuarioNombre, 'Otro cajero');
    });

    test('una anulación rechazada arrastra su motivo a la lista', () {
      final venta = VentaUnificadaModel.fromServer(
        _server(),
        local: _local(
          syncState: SyncState.cancelError,
          errorMessage: 'No se puede cancelar una venta de un período cerrado',
        ),
      );

      expect(venta.syncState, SyncState.cancelError);
      expect(venta.errorMessage,
          'No se puede cancelar una venta de un período cerrado');
    });

    test('nunca se ofrece "sincronizar" para algo que ya está en el servidor',
        () {
      final venta = VentaUnificadaModel.fromServer(
        _server(),
        local: _local(syncState: SyncState.cancelPending),
      );

      expect(venta.synced, isTrue);
    });
  });

  group('VentaUnificadaModel.fromLocal', () {
    test('una venta local siempre tiene fila local', () {
      final venta = VentaUnificadaModel.fromLocal(
        _local(syncState: SyncState.pending, serverId: null),
      );

      expect(venta.hasLocalRow, isTrue);
      expect(venta.puedeAnularse, isTrue);
    });

    test('no se puede volver a anular una que ya está en cola', () {
      final venta = VentaUnificadaModel.fromLocal(
        _local(syncState: SyncState.cancelPending),
      );

      expect(venta.puedeAnularse, isFalse);
    });
  });
}
