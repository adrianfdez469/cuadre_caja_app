// Casos borde de [SyncService]: reconexión, drenaje de anulaciones,
// autenticación, alcanzabilidad y reconciliación de inventario.
//
// Complementa `sync_service_test.dart`, que cubre el camino feliz de `fullSync`.
// Aquí interesa sobre todo lo que NO debe ocurrir: peticiones de más, DELETEs
// duplicados, expulsiones al login por un corte de red, o borrados de cache
// causados por un fallo temporal.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cuadre_caja_app/core/network/api_client.dart';
import 'package:cuadre_caja_app/core/utils/venta_cancel_policy.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/sync_service_fakes.dart';

DioException _dioError(int status, {Object? data}) => DioException(
      requestOptions: RequestOptions(path: '/venta'),
      response: Response(
        requestOptions: RequestOptions(path: '/venta'),
        statusCode: status,
        data: data,
      ),
    );

void main() {
  // ==========================================
  // Reconexión
  // ==========================================
  group('reconexión', () {
    test('al volver la red se dispara un fullSync completo, una sola vez',
        () async {
      final h = SyncHarness(online: false, periodoServidor: periodoDe('p1'));
      await h.arrancar();

      h.connectivity.emitir(ConnectivityResult.wifi);
      await h.bombear();

      expect(h.productosRemote.calls, 1, reason: 'GET /productos');
      expect(h.periodosRemote.calls, 1, reason: 'GET /periodo/actual');
      expect(h.avisos, hasLength(1));
      expect(h.conexiones, contains(ConnectionStatus.online));

      h.parar();
    });

    test('dos reconexiones solapadas coalescen en un único ciclo', () async {
      final h = SyncHarness(online: false, periodoServidor: periodoDe('p1'));
      await h.arrancar();

      // El GET de inventario se queda colgado: mientras tanto llega un segundo
      // ciclo de "se cayó y volvió la red".
      final puerta = Completer<void>();
      h.productosRemote.puerta = puerta;

      h.connectivity.emitir(ConnectivityResult.wifi);
      await h.bombear();
      // Comprobación del propio montaje: si la puerta no estuviera reteniendo
      // el primer ciclo, este test no probaría ninguna coalescencia.
      expect(h.avisos, isEmpty, reason: 'el primer ciclo sigue en vuelo');
      expect(h.productosRemote.calls, 1);

      h.connectivity.emitir(ConnectivityResult.none);
      await h.bombear();
      h.connectivity.emitir(ConnectivityResult.wifi);
      await h.bombear();

      puerta.complete();
      await h.bombear();

      expect(h.productosRemote.calls, 1, reason: 'un solo GET /productos');
      expect(h.periodosRemote.calls, 1, reason: 'un solo GET /periodo');
      expect(h.avisos, hasLength(1), reason: 'un solo repintado');

      h.parar();
    });

    test('sin sesión válida por red inestable no se sincroniza ni se expulsa',
        () async {
      final h = SyncHarness(online: false, periodoServidor: periodoDe('p1'));
      h.apiClient.auth = AuthResult.networkError;
      await h.arrancar();

      h.connectivity.emitir(ConnectivityResult.wifi);
      await h.bombear();

      expect(h.productosRemote.calls, 0);
      expect(h.periodosRemote.calls, 0);
      expect(h.authRequerido, isEmpty, reason: 'un corte de red no expulsa');

      h.parar();
    });

    test('sin usuario guardado no hay contexto y no se sincroniza', () async {
      final h = SyncHarness(online: false, periodoServidor: periodoDe('p1'));
      h.storage.user = null;
      await h.arrancar();

      h.connectivity.emitir(ConnectivityResult.wifi);
      await h.bombear();

      expect(h.productosRemote.calls, 0);
      expect(h.avisos, isEmpty);

      h.parar();
    });

    test('el contexto sale del usuario guardado cuando nunca hubo fullSync online',
        () async {
      // Un `fullSync` offline retorna antes de guardar `_lastTiendaId`: el
      // único origen del contexto en la reconexión es el usuario en storage.
      final h = SyncHarness(online: false, periodoServidor: periodoDe('p1'));
      await h.arrancar();
      await h.service.fullSync('t1', negocioId: 'n1');
      h.avisos.clear();

      h.connectivity.emitir(ConnectivityResult.wifi);
      await h.bombear();

      expect(h.productosRemote.calls, 1);
      expect(h.monedasRemote.calls, 1,
          reason: 'el negocioId también sale del usuario guardado');

      h.parar();
    });
  });

  // ==========================================
  // Drenaje de anulaciones
  // ==========================================
  group('_syncPendingCancelaciones — un solo DELETE por venta', () {
    test('dos drenajes concurrentes no mandan el DELETE dos veces', () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1', syncState: SyncState.synced, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      final puerta = Completer<void>();
      h.ventasRemote.puertaCancelacion = puerta;

      await h.service.anularVenta('v1');
      await h.bombear(2);
      // Montaje: el primer DELETE tiene que estar retenido en la puerta, o el
      // test no probaría concurrencia ninguna.
      expect(h.ventasRemote.cancelCalls, hasLength(1));
      expect(await h.ventasLocal.getVentaBySyncId('v1'), isNotNull,
          reason: 'el servidor aún no confirmó');

      // Segundo drenaje mientras el primero está en vuelo.
      await h.service.forceSyncVentas();

      puerta.complete();
      await h.bombear();

      expect(h.ventasRemote.cancelCalls, hasLength(1));

      h.parar();
    });

    test('un 404 se toma como anulación ya cumplida', () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1', syncState: SyncState.cancelPending,
              serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      h.ventasRemote.erroresDeCancelacion = [_dioError(404)];
      await h.arrancar();

      final r = await h.service.forceSyncVentas();

      expect(r.canceladas, 1);
      expect(await h.ventasLocal.getVentaBySyncId('v1'), isNull,
          reason: 'la venta desaparece igual que con un DELETE aceptado');

      h.parar();
    });

    test('un rechazo del servidor revierte el stock y deja cancelError',
        () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1',
              syncState: SyncState.cancelPending, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1', existencia: 10)];
      h.ventasRemote.erroresDeCancelacion = [
        _dioError(403, data: {'error': 'Sin permiso para anular'}),
      ];
      await h.arrancar();

      await h.service.forceSyncVentas();

      final venta = await h.ventasLocal.getVentaBySyncId('v1');
      expect(venta?.syncState, SyncState.cancelError);
      expect(venta?.errorMessage, 'Sin permiso para anular');
      expect(
        h.productosLocal.updateExistenciasCalls.first['pt1'],
        9,
        reason: 'se re-descuenta lo que la anulación había devuelto',
      );

      h.parar();
    });

    test('una cancelación sin serverId se resuelve sin tocar la red', () async {
      final h = SyncHarness(
        ventas: [ventaLocalDe('v1', syncState: SyncState.cancelPending)],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasRemote.cancelCalls, isEmpty);
      expect(await h.ventasLocal.getVentaBySyncId('v1'), isNull);

      h.parar();
    });
  });

  // ==========================================
  // anularVenta — los cinco planes
  // ==========================================
  group('anularVenta', () {
    test('borradoLocal: cero red, cero avisos, stock devuelto', () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1', cantidad: 2)]);
      h.productosLocal.almacenados = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      final r = await h.service.anularVenta('v1');
      await h.bombear();

      expect(r, AnulacionResultado.borrada);
      expect(h.ventasRemote.cancelCalls, isEmpty);
      expect(h.ventasRemote.postCalls, isEmpty);
      expect(h.productosRemote.calls, 0);
      expect(h.productosLocal.updateExistenciasCalls.single['pt1'], 12);
      expect(await h.ventasLocal.getVentaBySyncId('v1'), isNull);
      // Documenta el contrato actual: este camino NO avisa, así que la pantalla
      // que lo invoca es responsable de repintarse.
      expect(h.avisos, isEmpty);

      h.parar();
    });

    test('encolar online: un DELETE, un GET de inventario y un aviso', () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1', syncState: SyncState.synced, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      final r = await h.service.anularVenta('v1');
      await h.bombear();

      expect(r, AnulacionResultado.encolada);
      expect(h.ventasRemote.cancelCalls, hasLength(1));
      expect(h.ventasRemote.cancelCalls.single.ventaId, 'srv-1');
      expect(h.ventasRemote.cancelCalls.single.tiendaId, 't1');
      expect(h.ventasRemote.cancelCalls.single.periodoId, 'p1');
      expect(h.productosRemote.calls, 1, reason: 'un solo GET /productos');
      expect(h.periodosRemote.calls, 0, reason: 'anular no relee el período');
      expect(h.avisos, hasLength(1));
      expect(h.avisos.single.ventasCambiaron, isTrue);

      h.parar();
    });

    test('encolar offline: ni red ni aviso, la anulación espera en cola',
        () async {
      final h = SyncHarness(
        online: false,
        ventas: [
          ventaLocalDe('v1', syncState: SyncState.synced, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      final r = await h.service.anularVenta('v1');
      await h.bombear();

      expect(r, AnulacionResultado.encolada);
      expect(h.ventasRemote.cancelCalls, isEmpty);
      expect(h.productosRemote.calls, 0);
      expect(h.avisos, isEmpty);
      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.cancelPending,
      );
      expect(h.productosLocal.updateExistenciasCalls.single['pt1'], 11);

      h.parar();
    });

    test('yaEnCurso: no re-pide nada ni toca el stock', () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1',
              syncState: SyncState.cancelPending, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      final r = await h.service.anularVenta('v1');
      await h.bombear();

      expect(r, AnulacionResultado.yaEnCurso);
      expect(h.ventasRemote.cancelCalls, isEmpty);
      expect(h.productosLocal.updateExistenciasCalls, isEmpty);
      expect(h.avisos, isEmpty);

      h.parar();
    });

    test('subidaEnVuelo: no se borra una venta cuyo POST está en vuelo',
        () async {
      final h = SyncHarness(
        ventas: [ventaLocalDe('v1', syncState: SyncState.syncing)],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      final r = await h.service.anularVenta('v1');
      await h.bombear();

      expect(r, AnulacionResultado.subidaEnVuelo);
      expect(await h.ventasLocal.getVentaBySyncId('v1'), isNotNull);
      expect(h.productosLocal.updateExistenciasCalls, isEmpty);

      h.parar();
    });

    test('sin fila local: no permitida', () async {
      final h = SyncHarness();
      await h.arrancar();

      expect(
        await h.service.anularVenta('inexistente'),
        AnulacionResultado.noPermitida,
      );
      expect(h.ventasRemote.cancelCalls, isEmpty);

      h.parar();
    });
  });

  // ==========================================
  // reintentar / descartar
  // ==========================================
  group('reintentarAnulacion y descartarAnulacion', () {
    test('descartar es 100% local: ni un byte de red', () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1',
              syncState: SyncState.cancelError, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      await h.service.descartarAnulacion('v1');
      await h.bombear();

      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.synced,
      );
      expect(h.apiClient.reachableCalls, 0);
      expect(h.ventasRemote.cancelCalls, isEmpty);
      expect(h.productosRemote.calls, 0);
      expect(
        h.productosLocal.updateExistenciasCalls,
        isEmpty,
        reason: 'el rechazo ya revirtió el stock',
      );

      h.parar();
    });

    test('descartar una venta que no está en cancelError no hace nada',
        () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1')]);
      await h.arrancar();

      await h.service.descartarAnulacion('v1');

      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.pending,
      );

      h.parar();
    });

    test('reintentar re-devuelve el stock y vuelve a mandar el DELETE',
        () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1',
              syncState: SyncState.cancelError, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      await h.service.reintentarAnulacion('v1');
      await h.bombear();

      expect(h.productosLocal.updateExistenciasCalls.first['pt1'], 11);
      expect(h.ventasRemote.cancelCalls, hasLength(1));
      expect(h.avisos, hasLength(1));
      expect(h.avisos.single.ventasCambiaron, isTrue);
      expect(await h.ventasLocal.getVentaBySyncId('v1'), isNull);

      h.parar();
    });

    test('reintentar sin conexión deja la anulación en cola, sin red',
        () async {
      final h = SyncHarness(
        online: false,
        ventas: [
          ventaLocalDe('v1',
              syncState: SyncState.cancelError, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      await h.service.reintentarAnulacion('v1');
      await h.bombear();

      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.cancelPending,
      );
      expect(h.ventasRemote.cancelCalls, isEmpty);
      expect(h.avisos, isEmpty);

      h.parar();
    });

    test('reintentar una venta que no está en cancelError no hace nada',
        () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1', syncState: SyncState.synced, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      await h.service.reintentarAnulacion('v1');
      await h.bombear();

      expect(h.productosLocal.updateExistenciasCalls, isEmpty);
      expect(h.ventasRemote.cancelCalls, isEmpty);

      h.parar();
    });
  });

  // ==========================================
  // Reconciliación de inventario
  // ==========================================
  group('_reconciliarInventario dentro de loadProductos', () {
    test('resta las ventas pendientes al snapshot del servidor', () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1', cantidad: 3)]);
      h.productosRemote.productos = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      final ajustados = await h.service.loadProductos('t1');

      expect(h.productosLocal.updateExistenciasCalls, hasLength(1));
      expect(h.productosLocal.updateExistenciasCalls.single['pt1'], 7);
      expect(ajustados.single.existencia, 7,
          reason: 'la UI recibe la existencia ya reconciliada');

      h.parar();
    });

    test('suma las anulaciones pendientes: snapshot − ventas + anulaciones',
        () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1', cantidad: 3),
          ventaLocalDe('v2',
              cantidad: 5,
              syncState: SyncState.cancelPending,
              serverId: 'srv-2'),
        ],
      );
      h.productosRemote.productos = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      final ajustados = await h.service.loadProductos('t1');

      expect(h.productosLocal.updateExistenciasCalls.single['pt1'], 12);
      expect(ajustados.single.existencia, 12);

      h.parar();
    });

    test('no reconcilia ventas de otra tienda', () async {
      final h = SyncHarness(
        ventas: [ventaLocalDe('v1', tiendaId: 'otra', cantidad: 3)],
      );
      h.productosRemote.productos = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      final ajustados = await h.service.loadProductos('t1');

      expect(h.productosLocal.updateExistenciasCalls, isEmpty);
      expect(ajustados.single.existencia, 10);

      h.parar();
    });

    test('una anulación en `cancelling` NO se replaya (ventana conocida)',
        () async {
      // Test de caracterización, no de deseo: `getCancelacionesPendientesByTienda`
      // filtra por `cancelPending`, así que mientras el DELETE está en vuelo la
      // devolución de stock local queda fuera de la fórmula y el snapshot del
      // servidor la revierte. Se cierra sola en cuanto el DELETE se confirma y
      // llega el siguiente `_pullInventario`, y por eso `ventas_list_screen`
      // repinta desde disco en vez de pedir un GET. Si alguien mete `cancelling`
      // en la consulta, este test se cae y hay que revisar la fórmula entera.
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1',
              cantidad: 4,
              syncState: SyncState.cancelling,
              serverId: 'srv-1'),
        ],
      );
      h.productosRemote.productos = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      final ajustados = await h.service.loadProductos('t1');

      expect(h.productosLocal.updateExistenciasCalls, isEmpty);
      expect(ajustados.single.existencia, 10);

      h.parar();
    });

    test('sin nada pendiente no se reescriben existencias', () async {
      final h = SyncHarness();
      h.productosRemote.productos = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      await h.service.loadProductos('t1');

      expect(h.productosLocal.updateExistenciasCalls, isEmpty);

      h.parar();
    });

    test('un fallo del GET no deja el catálogo vacío: cae a cache', () async {
      final h = SyncHarness();
      h.productosRemote.lanza = true;
      h.productosLocal.almacenados = [productoDe('pt1', existencia: 4)];
      await h.arrancar();

      final resultado = await h.service.loadProductos('t1');

      expect(resultado.single.existencia, 4);
      expect(h.productosLocal.cacheCalls, 0);

      h.parar();
    });
  });

  // ==========================================
  // Autenticación
  // ==========================================
  group('_ensureAuthenticated', () {
    test('la sesión se revalida una sola vez dentro del TTL', () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1')]);
      await h.arrancar();

      await h.service.forceSyncVentas();
      await h.service.forceSyncVentas();

      expect(h.apiClient.refreshTokenCalls, 1, reason: 'TTL de 5 min');

      h.parar();
    });

    test('un fallo de red no expulsa al login ni sincroniza', () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1')]);
      h.apiClient.auth = AuthResult.networkError;
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.authRequerido, isEmpty);
      expect(h.ventasRemote.postCalls, isEmpty);
      expect(h.apiClient.reLoginCalls, 0,
          reason: 'ante un error de red no se intenta re-login');

      h.parar();
    });

    test('un fallo de red no se cachea: se revalida al ciclo siguiente',
        () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1')]);
      h.apiClient.auth = AuthResult.networkError;
      await h.arrancar();

      await h.service.forceSyncVentas();
      await h.service.forceSyncVentas();

      expect(h.apiClient.refreshTokenCalls, 2);

      h.parar();
    });

    test('sesión rechazada + re-login fallido: expulsa al login', () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1')]);
      h.apiClient.auth = AuthResult.authRejected;
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.apiClient.reLoginCalls, 1);
      expect(h.authRequerido, [true]);
      expect(h.ventasRemote.postCalls, isEmpty);

      h.parar();
    });

    test('sesión rechazada pero re-login exitoso: sigue sincronizando',
        () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1')]);
      h.apiClient.auth = AuthResult.authRejected;
      h.apiClient.reLoginAuth = AuthResult.ok;
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.authRequerido, isEmpty);
      expect(h.ventasRemote.postCalls, hasLength(1));

      h.parar();
    });

    test('sin token no se golpea /auth/refresh, se va directo al login',
        () async {
      final h = SyncHarness(ventas: [ventaLocalDe('v1')]);
      h.storage.token = null;
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.apiClient.refreshTokenCalls, 0);
      expect(h.authRequerido, [true]);

      h.parar();
    });

    test('forceSyncVentas sin conexión no autentica ni sube nada', () async {
      final h = SyncHarness(online: false, ventas: [ventaLocalDe('v1')]);
      await h.arrancar();

      final r = await h.service.forceSyncVentas();

      expect(h.apiClient.refreshTokenCalls, 0);
      expect(h.ventasRemote.postCalls, isEmpty);
      expect(r.pending, 1, reason: 'informa lo que queda en cola');

      h.parar();
    });
  });

  // ==========================================
  // Alcanzabilidad del servidor
  // ==========================================
  group('_isServerReachable', () {
    test('el probe se cachea dentro del TTL de 15 s', () async {
      final h = SyncHarness();
      await h.arrancar();

      await h.service.loadProductos('t1');
      await h.service.loadProductos('t1');
      await h.service.loadPeriodoActual('t1');

      expect(h.apiClient.reachableCalls, 1);

      h.parar();
    });

    test('un cambio de red invalida el probe cacheado', () async {
      final h = SyncHarness();
      await h.arrancar();

      await h.service.loadProductos('t1');
      expect(h.apiClient.reachableCalls, 1);

      // wifi → móvil: sigue habiendo red (no dispara reconexión), pero el probe
      // anterior ya no vale.
      h.connectivity.emitir(ConnectivityResult.mobile);
      await h.bombear();

      await h.service.loadProductos('t1');
      expect(h.apiClient.reachableCalls, 2);

      h.parar();
    });

    test('sin conexión no se sondea siquiera', () async {
      final h = SyncHarness(online: false);
      await h.arrancar();

      await h.service.loadProductos('t1');
      await h.service.loadPeriodoActual('t1');

      expect(h.apiClient.reachableCalls, 0);

      h.parar();
    });
  });

  // ==========================================
  // syncSingleVentaBySyncId
  // ==========================================
  group('syncSingleVentaBySyncId', () {
    test('una venta ya sincronizada retorna true sin tocar la red', () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1', syncState: SyncState.synced, serverId: 'srv-1'),
        ],
      );
      await h.arrancar();

      expect(await h.service.syncSingleVentaBySyncId('v1'), isTrue);
      expect(h.ventasRemote.postCalls, isEmpty);
      expect(h.productosRemote.calls, 0);
      expect(h.avisos, isEmpty);

      h.parar();
    });

    test('una venta en vuelo retorna true sin re-postearla', () async {
      final h = SyncHarness(
        ventas: [ventaLocalDe('v1', syncState: SyncState.syncing)],
      );
      await h.arrancar();

      expect(await h.service.syncSingleVentaBySyncId('v1'), isTrue);
      expect(h.ventasRemote.postCalls, isEmpty);

      h.parar();
    });

    test('una venta en error sí se re-sube y refresca inventario', () async {
      final h = SyncHarness(
        ventas: [ventaLocalDe('v1', syncState: SyncState.error)],
      );
      await h.arrancar();

      expect(await h.service.syncSingleVentaBySyncId('v1'), isTrue);
      expect(h.ventasRemote.postCalls, hasLength(1));
      expect(h.productosRemote.calls, 1);
      expect(h.avisos, hasLength(1));
      expect(h.avisos.single.ventasCambiaron, isTrue);

      h.parar();
    });

    test('si el POST falla se refresca igual, pero marcando que nada cambió',
        () async {
      final h = SyncHarness(
        ventas: [ventaLocalDe('v1')],
        erroresDeVenta: ['Existencia insuficiente'],
      );
      await h.arrancar();

      expect(await h.service.syncSingleVentaBySyncId('v1'), isFalse);
      expect(h.productosRemote.calls, 1,
          reason: 'el stock autoritativo lo pone el servidor');
      expect(h.avisos.single.ventasCambiaron, isFalse);

      h.parar();
    });

    test('sin fila local retorna false y no toca la red', () async {
      final h = SyncHarness();
      await h.arrancar();

      expect(await h.service.syncSingleVentaBySyncId('nope'), isFalse);
      expect(h.productosRemote.calls, 0);

      h.parar();
    });

    test('sin conexión retorna false sin leer la BD', () async {
      final h = SyncHarness(online: false, ventas: [ventaLocalDe('v1')]);
      await h.arrancar();

      expect(await h.service.syncSingleVentaBySyncId('v1'), isFalse);
      expect(h.ventasRemote.postCalls, isEmpty);

      h.parar();
    });
  });

  // ==========================================
  // startMonitoring
  // ==========================================
  group('startMonitoring', () {
    test('recupera las ventas atascadas en syncing al arrancar', () async {
      final h = SyncHarness();
      await h.arrancar();

      expect(h.ventasLocal.resetStaleCalls, 1);

      h.parar();
    });

    test('un fallo recuperando ventas no impide arrancar el monitoreo',
        () async {
      final h = SyncHarness();
      h.ventasLocal.errorAlRecuperarSyncing = Exception('BD bloqueada');

      await h.arrancar();

      expect(h.conexiones, isNotEmpty,
          reason: 'el chequeo de conectividad sí llegó a correr');

      h.parar();
    });
  });

  // ==========================================
  // Auto-recuperación de período: los casos que NO se recuperan
  // ==========================================
  group('auto-recuperación de período — casos sin salida', () {
    test('si el servidor devuelve el MISMO período no se mueve la venta',
        () async {
      final h = SyncHarness(
        periodoServidor: periodoDe('p1'),
        ventas: [ventaLocalDe('v1', periodoId: 'p1')],
        erroresDeVenta: ['Período cerrado o diferente'],
      );
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasLocal.cambiosDePeriodo, isEmpty);
      expect(h.ventasRemote.postCalls, hasLength(1), reason: 'sin reintento');
      expect(h.periodosRemote.calls, 1);
      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.error,
      );

      h.parar();
    });

    test('un período cerrado no sirve de destino', () async {
      final h = SyncHarness(
        periodoServidor: periodoDe('p2', abierto: false),
        ventas: [ventaLocalDe('v1', periodoId: 'p1')],
        erroresDeVenta: ['Período cerrado o diferente'],
      );
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasLocal.cambiosDePeriodo, isEmpty);
      expect(h.ventasRemote.postCalls, hasLength(1));
      expect(
        (await h.ventasLocal.getVentaBySyncId('v1'))?.syncState,
        SyncState.error,
      );

      h.parar();
    });

    test('un período con id vacío tampoco', () async {
      final h = SyncHarness(
        periodoServidor: periodoDe(''),
        ventas: [ventaLocalDe('v1', periodoId: 'p1')],
        erroresDeVenta: ['Período cerrado o diferente'],
      );
      await h.arrancar();

      await h.service.forceSyncVentas();

      expect(h.ventasLocal.cambiosDePeriodo, isEmpty);
      expect(h.ventasRemote.postCalls, hasLength(1));

      h.parar();
    });

    test('el syncAttempts sube una sola vez pese al reintento interno',
        () async {
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

      expect((await h.ventasLocal.getVentaBySyncId('v1'))?.syncAttempts, 1);

      h.parar();
    });
  });

  // ==========================================
  // fullSync — invariante del aviso único
  // ==========================================
  group('fullSync — el aviso sobrevive a todo', () {
    test('si un paso lanza de verdad, el aviso ya se emitió', () async {
      // `loadPeriodoActual` y `loadProductos` se tragan sus propias
      // excepciones; el listado de pendientes es el único paso cuya excepción
      // escapa, así que es el que de verdad ejercita el `finally`.
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      h.ventasLocal.errorAlListarPendientes = Exception('BD corrupta');
      await h.arrancar();

      await expectLater(
        h.service.fullSync('t1', negocioId: 'n1'),
        throwsA(isA<Exception>()),
      );

      expect(h.avisos, hasLength(1),
          reason: 'el finally avisa aunque el ciclo se rompa');

      h.parar();
    });

    test('una excepción de la UI no rompe el ciclo de sync', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      h.errorAlAvisar = Exception('pantalla ya desmontada');
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.avisos, hasLength(1));

      h.parar();
    });

    test('sin negocioId no se piden monedas ni tasas', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      await h.arrancar();

      await h.service.fullSync('t1');

      expect(h.monedasRemote.calls, 0);
      expect(h.tasasRemote.calls, 0);
      expect(h.periodosRemote.calls, 1);
      expect(h.productosRemote.calls, 1);
      expect(h.avisos, hasLength(1));

      h.parar();
    });

    test('fullSync no relee el listado de ventas del servidor', () async {
      final h = SyncHarness(
        periodoServidor: periodoDe('p1'),
        ventas: [ventaLocalDe('v1')],
      );
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.ventasRemote.getCalls, 0,
          reason: 'eso lo decide la pantalla con SyncRefreshInfo');

      h.parar();
    });

    test('el duplicado descartado no reordena ni adelanta el aviso', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      await h.arrancar();

      final puerta = Completer<void>();
      h.productosRemote.puerta = puerta;

      final primero = h.service.fullSync('t1', negocioId: 'n1');
      await h.bombear(2);
      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.avisos, isEmpty,
          reason: 'el duplicado retorna sin avisar por su cuenta');

      puerta.complete();
      await primero;

      expect(h.avisos, hasLength(1));

      h.parar();
    });

    test('offline no marca que las ventas cambiaron', () async {
      final h = SyncHarness(online: false);
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.avisos.single.ventasCambiaron, isFalse);

      h.parar();
    });

    test('las anulaciones confirmadas también marcan que el listado cambió',
        () async {
      final h = SyncHarness(
        periodoServidor: periodoDe('p1'),
        ventas: [
          ventaLocalDe('v1',
              syncState: SyncState.cancelPending, serverId: 'srv-1'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      await h.service.fullSync('t1', negocioId: 'n1');

      expect(h.ventasRemote.cancelCalls, hasLength(1));
      expect(h.avisos.single.ventasCambiaron, isTrue);
      expect(h.productosRemote.calls, 1, reason: 'un solo GET /productos');

      h.parar();
    });
  });

  // ==========================================
  // crearVenta
  // ==========================================
  group('crearVenta — casos borde', () {
    test('si el POST falla, el aviso dice que el listado no cambió', () async {
      final h = SyncHarness(erroresDeVenta: ['Existencia insuficiente']);
      await h.arrancar();

      await h.service.crearVenta(ventaLocalDe('v1'));
      await h.bombear();

      expect(h.avisos, hasLength(1));
      expect(h.avisos.single.ventasCambiaron, isFalse);
      expect(h.productosRemote.calls, 1);

      h.parar();
    });

    test('online la venta se persiste ya en syncing, no en pending', () async {
      // Cierra la ventana de carrera con el sync periódico: getVentasPendientes
      // excluye `syncing`, así que nadie puede re-postearla.
      final h = SyncHarness();
      await h.arrancar();

      final guardada = await h.service.crearVenta(ventaLocalDe('v1'));

      expect(guardada.syncState, SyncState.syncing);
      expect(
        await h.ventasLocal.getVentasPendientes(),
        isEmpty,
        reason: 'el sync periódico no puede tomarla mientras sube',
      );
      await h.bombear();

      h.parar();
    });

    test('offline la venta queda pendiente y descuenta stock igualmente',
        () async {
      final h = SyncHarness(online: false);
      h.productosLocal.almacenados = [productoDe('pt1', existencia: 10)];
      await h.arrancar();

      final guardada = await h.service.crearVenta(ventaLocalDe('v1',
          cantidad: 4));
      await h.bombear();

      expect(guardada.syncState, SyncState.pending);
      expect(h.productosLocal.updateExistenciasCalls.single['pt1'], 6);

      h.parar();
    });
  });

  // ==========================================
  // loadPeriodoActual — bordes del espejo
  // ==========================================
  group('loadPeriodoActual — bordes', () {
    test('servidor inalcanzable: ni borra ni pide, devuelve el cache',
        () async {
      final h = SyncHarness(reachable: false);
      h.periodosLocal.almacenado = periodoDe('p1');
      await h.arrancar();

      final periodo = await h.service.loadPeriodoActual('t1');

      expect(h.periodosRemote.calls, 0);
      expect(h.periodosLocal.deleteCalls, 0);
      expect(periodo?.id, 'p1');

      h.parar();
    });

    test('sin conexión no se borra el cache', () async {
      final h = SyncHarness(online: false);
      h.periodosLocal.almacenado = periodoDe('p1');
      await h.arrancar();

      expect((await h.service.loadPeriodoActual('t1'))?.id, 'p1');
      expect(h.periodosLocal.deleteCalls, 0);

      h.parar();
    });

    test('el borrado se repite en cada ciclo sin período abierto', () async {
      final h = SyncHarness(periodoServidor: null);
      await h.arrancar();

      await h.service.loadPeriodoActual('t1');
      await h.service.loadPeriodoActual('t1');

      expect(h.periodosLocal.deleteCalls, 2);
      expect(await h.service.getPeriodoLocal('t1'), isNull);

      h.parar();
    });
  });

  // ==========================================
  // SyncResult / SyncRefreshInfo
  // ==========================================
  group('SyncResult y SyncRefreshInfo', () {
    test('canceladas cuenta las anulaciones confirmadas', () async {
      final h = SyncHarness(
        ventas: [
          ventaLocalDe('v1',
              syncState: SyncState.cancelPending, serverId: 'srv-1'),
          ventaLocalDe('v2',
              syncState: SyncState.cancelPending, serverId: 'srv-2'),
        ],
      );
      h.productosLocal.almacenados = [productoDe('pt1')];
      await h.arrancar();

      final r = await h.service.forceSyncVentas();

      expect(r.canceladas, 2);
      expect(r.synced, 0);

      h.parar();
    });

    test('merge es asociativo y no muta los operandos', () {
      const a = SyncRefreshInfo(ventasCambiaron: true);
      const b = SyncRefreshInfo();
      const c = SyncRefreshInfo();

      expect(a.merge(b).merge(c).ventasCambiaron, isTrue);
      expect(a.merge(b.merge(c)).ventasCambiaron, isTrue);
      expect(a.ventasCambiaron, isTrue);
      expect(b.ventasCambiaron, isFalse,
          reason: 'merge devuelve uno nuevo, no modifica el receptor');
    });

    test('acumular avisos concurrentes conserva el true intermedio', () {
      // Es lo que hace `_refreshUiAfterSync` en pos_home_screen mientras
      // serializa varios refrescos.
      var acumulado = const SyncRefreshInfo();
      for (final info in [
        const SyncRefreshInfo(),
        const SyncRefreshInfo(ventasCambiaron: true),
        const SyncRefreshInfo(),
      ]) {
        acumulado = acumulado.merge(info);
      }

      expect(acumulado.ventasCambiaron, isTrue);
    });
  });
}
