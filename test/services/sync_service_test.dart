import 'package:cuadre_caja_app/data/models/venta_model.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/sync_service_fakes.dart';

void main() {
  group('fullSync — una sola ronda de red por ciclo', () {
    test('online pide cada endpoint exactamente una vez', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      // Esta es la especificación ejecutable del objetivo: si alguien
      // reintroduce el refresco en cascada, estos cuatro contadores suben.
      expect(h.productosRemote.calls, 1, reason: 'GET /productos');
      expect(h.periodosRemote.calls, 1, reason: 'GET /periodo/actual');
      expect(h.monedasRemote.calls, 1, reason: 'GET /monedas');
      expect(h.tasasRemote.calls, 1, reason: 'GET /tasas-cambio');
      expect(h.transferRemote.calls, 1, reason: 'GET /transfer-destinations');

      h.parar();
    });

    test('sin ventas ni anulaciones no relee el listado del servidor', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.avisos, hasLength(1));
      expect(
        h.avisos.single.ventasCambiaron,
        isFalse,
        reason: 'nada subió: releer /venta devolvería lo mismo',
      );

      h.parar();
    });

    test('avisa a la UI exactamente una vez', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.avisos, hasLength(1));

      h.parar();
    });

    test('offline avisa igualmente y no toca la red', () async {
      final h = SyncHarness(online: false);
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(
        h.avisos,
        hasLength(1),
        reason: 'sin este aviso el arranque sin conexión no repintaría nada',
      );
      expect(h.productosRemote.calls, 0);
      expect(h.periodosRemote.calls, 0);
      expect(h.monedasRemote.calls, 0);

      h.parar();
    });

    test('servidor inalcanzable: cae a cache y sigue avisando una vez', () async {
      final h = SyncHarness(reachable: false);
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.avisos, hasLength(1));
      expect(h.productosRemote.calls, 0, reason: 'el probe /health lo evitó');

      h.parar();
    });

    test('dos fullSync concurrentes: el duplicado no toca la red ni avisa',
        () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      await h.arrancar();

      await Future.wait([
        h.service.fullSync('t1', negocioId: 'n1'),
        h.service.fullSync('t1', negocioId: 'n1'),
      ]);

      expect(h.productosRemote.calls, 1);
      expect(h.periodosRemote.calls, 1);
      expect(h.avisos, hasLength(1), reason: 'el que está en vuelo avisa por los dos');

      h.parar();
    });

    test('un fallo del paso de datos no impide el aviso final', () async {
      final h = SyncHarness();
      h.periodosRemote.lanza = true;
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.avisos, hasLength(1));

      h.parar();
    });

    test('con ventas pendientes marca que el listado cambió', () async {
      final h = SyncHarness(
        periodoServidor: periodoDe('p1'),
        ventas: [ventaLocalDe('v1')],
      );
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.ventasRemote.postCalls, hasLength(1));
      expect(h.avisos.single.ventasCambiaron, isTrue);
      // Inventario una sola vez pese al POST: el paso 2 corre con
      // refreshInventarioAfter en false y el paso 3 es quien lo trae.
      expect(h.productosRemote.calls, 1);

      h.parar();
    });
  });

  group('_syncPendingVentas — no molesta al servidor sin motivo', () {
    test('cola vacía: ni inventario ni aviso', () async {
      final h = SyncHarness();
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.productosRemote.calls, 0);
      expect(h.avisos, isEmpty);

      h.parar();
    });

    test('con una venta pendiente: un POST, un refresco de inventario', () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1')]);
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasRemote.postCalls, hasLength(1));
      expect(h.productosRemote.calls, 1);
      expect(h.avisos, hasLength(1));
      expect(h.avisos.single.ventasCambiaron, isTrue);

      h.parar();
    });
  });

  group('loadPeriodoActual — el cache es espejo del servidor', () {
    test('si el servidor dice que no hay período abierto, borra el cache',
        () async {
      final h = SyncHarness(periodoServidor: null);
      h.periodosLocal.almacenado = periodoDe('viejo');
      await h.arrancar();

      final periodo = await h.service.loadPeriodoActual('t1');

      expect(periodo, isNull);
      expect(h.periodosLocal.deleteCalls, 1);
      expect(
        h.periodosLocal.almacenado,
        isNull,
        reason: 'si no se borra, el POS resucita un período ya cerrado',
      );

      h.parar();
    });

    test('un fallo de red NO borra el cache y devuelve lo guardado', () async {
      final h = SyncHarness();
      h.periodosRemote.lanza = true;
      h.periodosLocal.almacenado = periodoDe('p1');
      await h.arrancar();

      final periodo = await h.service.loadPeriodoActual('t1');

      expect(h.periodosLocal.deleteCalls, 0);
      expect(periodo?.id, 'p1');

      h.parar();
    });

    test('el servidor devuelve período: lo persiste', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p2'));
      await h.arrancar();

      await h.service.loadPeriodoActual('t1');

      expect(h.periodosLocal.almacenado?.id, 'p2');
      expect(h.periodosLocal.deleteCalls, 0);

      h.parar();
    });

    test('getPeriodoLocal lee de disco sin tocar la red', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      h.periodosLocal.almacenado = periodoDe('cacheado');
      await h.arrancar();

      final periodo = await h.service.getPeriodoLocal('t1');

      expect(periodo?.id, 'cacheado');
      expect(h.periodosRemote.calls, 0);

      h.parar();
    });
  });

  group('auto-recuperación de conflicto de período', () {
    test('mueve la venta al período actual y reintenta una vez', () async {
      final h = SyncHarness(
        periodoServidor: periodoDe('p2'),
        ventas: [ventaLocalDe('v1', periodoId: 'p1')],
        erroresDeVenta: ['Período cerrado o diferente'],
      );
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasRemote.postCalls, hasLength(2), reason: 'un solo reintento');
      expect(h.ventasLocal.cambiosDePeriodo, hasLength(1));
      expect(h.ventasLocal.cambiosDePeriodo.single.periodoId, 'p2');
      expect(h.ventasRemote.postCalls.last.periodoId, 'p2');
      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.synced,
      );

      h.parar();
    });

    test('sin período abierto en el servidor la venta queda en error', () async {
      final h = SyncHarness(
        periodoServidor: null,
        ventas: [ventaLocalDe('v1', periodoId: 'p1')],
        erroresDeVenta: ['No existe un período abierto'],
      );
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasRemote.postCalls, hasLength(1), reason: 'no hay a dónde moverla');
      expect(h.ventasLocal.cambiosDePeriodo, isEmpty);
      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.error,
      );

      h.parar();
    });

    test('si el reintento también falla, no hay tercer intento', () async {
      final h = SyncHarness(
        periodoServidor: periodoDe('p2'),
        ventas: [ventaLocalDe('v1', periodoId: 'p1')],
        erroresDeVenta: [
          'Período cerrado o diferente',
          'Período cerrado o diferente',
        ],
      );
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasRemote.postCalls, hasLength(2), reason: 'nada de bucles');
      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.error,
      );

      h.parar();
    });

    test('un error que no es de período no dispara la recuperación', () async {
      final h = SyncHarness(
        periodoServidor: periodoDe('p2'),
        ventas: [ventaLocalDe('v1', periodoId: 'p1')],
        erroresDeVenta: ['Existencia insuficiente'],
      );
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasRemote.postCalls, hasLength(1));
      expect(h.ventasLocal.cambiosDePeriodo, isEmpty);
      expect(h.periodosRemote.calls, 0, reason: 'no se pide /periodo sin conflicto');

      h.parar();
    });
  });

  group('crearVenta', () {
    test('online: sube, refresca inventario y avisa una vez', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      await h.arrancar();

      await h.service.crearVenta(ventaLocalDe('v1'));
      // El sync va en fire-and-forget: hay que dejar correr los microtasks.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(h.ventasRemote.postCalls, hasLength(1));
      expect(h.productosRemote.calls, 1, reason: 'un solo GET /productos');
      expect(h.periodosRemote.calls, 0, reason: 'vender no cambia el período');
      expect(h.monedasRemote.calls, 0, reason: 'vender no cambia las tasas');
      expect(h.avisos, hasLength(1));
      expect(h.avisos.single.ventasCambiaron, isTrue);

      h.parar();
    });

    test('offline: ni red ni aviso', () async {
      final h = SyncHarness(online: false);
      await h.arrancar();

      await h.service.crearVenta(ventaLocalDe('v1'));
      await Future<void>.delayed(Duration.zero);

      expect(h.ventasRemote.postCalls, isEmpty);
      expect(h.productosRemote.calls, 0);
      expect(h.avisos, isEmpty);

      h.parar();
    });
  });

  group('SyncRefreshInfo', () {
    test('merge conserva el true: un aviso sin novedades no lo pisa', () {
      const conVentas = SyncRefreshInfo(ventasCambiaron: true);
      const sinVentas = SyncRefreshInfo();

      expect(conVentas.merge(sinVentas).ventasCambiaron, isTrue);
      expect(sinVentas.merge(conVentas).ventasCambiaron, isTrue);
      expect(sinVentas.merge(sinVentas).ventasCambiaron, isFalse);
    });
  });
}
