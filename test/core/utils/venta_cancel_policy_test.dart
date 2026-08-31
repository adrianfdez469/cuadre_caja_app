import 'package:flutter_test/flutter_test.dart';
import 'package:cuadre_caja_app/core/utils/venta_cancel_policy.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';

VentaLocalModel _venta({
  SyncState syncState = SyncState.synced,
  String? serverId,
}) {
  return VentaLocalModel(
    syncId: 'v1',
    tiendaId: 't1',
    periodoId: 'p1',
    productos: [
      VentaProducto(productoTiendaId: 'A', cantidad: 1, precio: 10),
    ],
    total: 10,
    totalcash: 10,
    createdAt: 0,
    syncState: syncState,
    serverId: serverId,
  );
}

void main() {
  group('VentaCancelPolicy.planFor', () {
    test('sin fila local no se puede anular desde este dispositivo', () {
      expect(VentaCancelPolicy.planFor(null), AnulacionPlan.sinFilaLocal);
    });

    test('sin serverId se borra en local: el servidor no la conoce', () {
      expect(
        VentaCancelPolicy.planFor(_venta(syncState: SyncState.pending)),
        AnulacionPlan.borradoLocal,
      );
    });

    test('una venta en error sin serverId también se borra en local', () {
      // Nunca obtuvo id de servidor, así que no hay nada que cancelar allí.
      expect(
        VentaCancelPolicy.planFor(_venta(syncState: SyncState.error)),
        AnulacionPlan.borradoLocal,
      );
    });

    test('un serverId vacío cuenta como ausente', () {
      expect(
        VentaCancelPolicy.planFor(_venta(serverId: '')),
        AnulacionPlan.borradoLocal,
      );
    });

    test('con serverId la anulación se encola: la confirma el servidor', () {
      expect(
        VentaCancelPolicy.planFor(_venta(serverId: 'srv-1')),
        AnulacionPlan.encolar,
      );
    });

    test('no se anula mientras el POST de la venta está en vuelo', () {
      // Borrarla ahora dejaría una venta huérfana en el servidor: el POST puede
      // triunfar justo después y este dispositivo ya no sabría su serverId.
      expect(
        VentaCancelPolicy.planFor(
          _venta(syncState: SyncState.syncing, serverId: null),
        ),
        AnulacionPlan.subidaEnVuelo,
      );
    });

    test('no se vuelve a pedir una anulación ya en curso', () {
      for (final estado in [
        SyncState.cancelPending,
        SyncState.cancelling,
        SyncState.cancelError,
      ]) {
        expect(
          VentaCancelPolicy.planFor(_venta(syncState: estado, serverId: 'srv-1')),
          AnulacionPlan.yaEnCurso,
          reason: 'estado $estado',
        );
      }
    });
  });

  group('VentaCancelPolicy.quedaPendiente', () {
    test('encolar sin conexión queda pendiente', () {
      expect(
        VentaCancelPolicy.quedaPendiente(
          AnulacionPlan.encolar,
          isOnline: false,
        ),
        isTrue,
      );
    });

    test('encolar con conexión no queda pendiente', () {
      expect(
        VentaCancelPolicy.quedaPendiente(AnulacionPlan.encolar, isOnline: true),
        isFalse,
      );
    });

    test('el borrado local es inmediato aunque no haya conexión', () {
      expect(
        VentaCancelPolicy.quedaPendiente(
          AnulacionPlan.borradoLocal,
          isOnline: false,
        ),
        isFalse,
      );
    });
  });
}
