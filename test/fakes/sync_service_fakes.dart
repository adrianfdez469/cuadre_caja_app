// Colaboradores falsos para construir un [SyncService] real en tests.
//
// Todos cuentan sus llamadas: el objetivo de esta batería es verificar
// **cuántas veces** se pide cada endpoint por ciclo de sincronización, no solo
// que el resultado sea correcto.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cuadre_caja_app/core/errors/exceptions.dart';
import 'package:cuadre_caja_app/core/network/api_client.dart';
import 'package:cuadre_caja_app/core/network/secure_storage_service.dart';
import 'package:cuadre_caja_app/data/datasources/local/multimoneda_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/local/periodos_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/local/productos_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/local/transfer_destinations_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/local/ventas_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/monedas_remote_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/periodos_remote_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/productos_remote_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/tasas_remote_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/transfer_destinations_remote_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/ventas_remote_datasource.dart';
import 'package:cuadre_caja_app/data/models/categoria_model.dart';
import 'package:cuadre_caja_app/data/models/moneda_model.dart';
import 'package:cuadre_caja_app/data/models/periodo_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/data/models/tasa_model.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ==========================================
// Constructores de modelos para los tests
// ==========================================

PeriodoModel periodoDe(
  String id, {
  String tiendaId = 't1',
  bool abierto = true,
}) =>
    PeriodoModel(
      id: id,
      tiendaId: tiendaId,
      fechaInicio: DateTime(2026, 1, 1),
      estaAbierto: abierto,
    );

VentaLocalModel ventaLocalDe(
  String syncId, {
  String tiendaId = 't1',
  String periodoId = 'p1',
  SyncState syncState = SyncState.pending,
  int syncAttempts = 0,
  String? serverId,
  double cantidad = 1,
  List<VentaProducto>? productos,
}) =>
    VentaLocalModel(
      syncId: syncId,
      tiendaId: tiendaId,
      periodoId: periodoId,
      // Con la lista vacía, `isPayloadReady` rechaza la venta antes de llegar
      // al POST y el test no ejercitaría nada.
      productos: productos ??
          [
            VentaProducto(
              productoTiendaId: 'pt1',
              cantidad: cantidad,
              precio: 100,
            ),
          ],
      total: 100,
      totalcash: 100,
      createdAt: 1000,
      syncState: syncState,
      syncAttempts: syncAttempts,
      serverId: serverId,
    );

/// Producto de catálogo mínimo, para los tests de reconciliación de inventario.
ProductoModel productoDe(
  String id, {
  double existencia = 10,
  String? productoId,
}) =>
    ProductoModel(
      id: id,
      productoId: productoId ?? 'base-$id',
      nombre: 'Producto $id',
      precio: 100,
      costo: 50,
      existencia: existencia,
    );

// ==========================================
// Infraestructura
// ==========================================

class FakeConnectivity extends Fake implements Connectivity {
  FakeConnectivity({this.online = true});

  bool online;
  final _controller = StreamController<ConnectivityResult>.broadcast();

  @override
  Future<ConnectivityResult> checkConnectivity() async =>
      online ? ConnectivityResult.wifi : ConnectivityResult.none;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => _controller.stream;

  /// Simula un cambio de red. Mueve también [online] para que un
  /// `checkConnectivity` posterior sea coherente con lo emitido.
  void emitir(ConnectivityResult result) {
    online = result != ConnectivityResult.none;
    _controller.add(result);
  }

  void dispose() => _controller.close();
}

class FakeApiClientSync extends Fake implements ApiClient {
  FakeApiClientSync({this.reachable = true, this.auth = AuthResult.ok});

  bool reachable;

  /// Resultado de `/auth/refresh`.
  AuthResult auth;

  /// Resultado del re-login. Si es `null` se usa [auth]; ponerlo aparte permite
  /// el caso real "el refresh es rechazado pero el re-login funciona".
  AuthResult? reLoginAuth;

  int reachableCalls = 0;
  int refreshTokenCalls = 0;
  int reLoginCalls = 0;

  @override
  Future<bool> isServerReachable() async {
    reachableCalls++;
    return reachable;
  }

  @override
  Future<AuthResult> refreshToken() async {
    refreshTokenCalls++;
    return auth;
  }

  @override
  Future<AuthResult> reLogin() async {
    reLoginCalls++;
    return reLoginAuth ?? auth;
  }
}

class FakeStorageSync extends Fake implements SecureStorageService {
  FakeStorageSync({this.user, this.token = 'tok'});

  Map<String, dynamic>? user;
  String? token;

  @override
  Future<Map<String, dynamic>?> getUser() async => user;

  @override
  Future<String?> getToken() async => token;
}

// ==========================================
// Remotos (cuentan llamadas)
// ==========================================

class FakeProductosRemote extends Fake implements ProductosRemoteDataSource {
  FakeProductosRemote({this.productos = const []});

  List<ProductoModel> productos;
  int calls = 0;
  bool lanza = false;

  /// Si se define, el GET se queda colgado hasta completarla. Permite tener un
  /// ciclo de sync "en vuelo" de forma determinista.
  Completer<void>? puerta;

  @override
  Future<List<ProductoModel>> getProductos(String tiendaId) async {
    calls++;
    final p = puerta;
    if (p != null) await p.future;
    if (lanza) throw Exception('red caída');
    return productos;
  }
}

class FakePeriodosRemote extends Fake implements PeriodosRemoteDataSource {
  FakePeriodosRemote({this.periodo, this.lanza = false});

  PeriodoModel? periodo;
  bool lanza;
  int calls = 0;

  @override
  Future<PeriodoModel?> getPeriodoActual(String tiendaId) async {
    calls++;
    if (lanza) throw Exception('red caída');
    return periodo;
  }
}

class FakeMonedasRemote extends Fake implements MonedasRemoteDataSource {
  int calls = 0;

  @override
  Future<MonedasNegocioResponse> getMonedas(String negocioId) async {
    calls++;
    return const MonedasNegocioResponse(monedas: []);
  }
}

class FakeTasasRemote extends Fake implements TasasRemoteDataSource {
  int calls = 0;

  @override
  Future<TasasVigentesResponse> getTasasCambio(String negocioId) async {
    calls++;
    return const TasasVigentesResponse(vigentes: {}, monedaBase: 'CUP');
  }
}

class FakeTransferRemote extends Fake
    implements TransferDestinationsRemoteDataSource {
  int calls = 0;

  @override
  Future<List<TransferDestinationModel>> getDestinos(String tiendaId) async {
    calls++;
    return const [];
  }
}

/// POST /venta falso. [errorPorIntento] permite simular que el primer intento
/// falla (p. ej. conflicto de período) y el segundo tiene éxito.
class FakeVentasRemote extends Fake implements VentasRemoteDataSource {
  FakeVentasRemote({this.errorPorIntento = const []});

  /// Mensaje de error para cada intento, en orden. `null` = éxito.
  final List<String?> errorPorIntento;

  final List<VentaLocalModel> postCalls = [];
  int getCalls = 0;

  @override
  Future<VentaCreateResult> crearVenta(VentaLocalModel ventaLocal) async {
    final intento = postCalls.length;
    postCalls.add(ventaLocal);
    final error =
        intento < errorPorIntento.length ? errorPorIntento[intento] : null;
    if (error != null) throw SyncVentaException(error);
    return VentaCreateResult(
      venta: VentaServerModel(
        id: 'srv-${ventaLocal.syncId}',
        tiendaId: ventaLocal.tiendaId,
        usuarioId: 'u1',
        cierrePeriodoId: ventaLocal.periodoId,
        total: ventaLocal.total,
        totalcash: ventaLocal.totalcash,
        syncId: ventaLocal.syncId,
        createdAt: DateTime(2026, 1, 1),
        productos: const [],
      ),
      duplicado: false,
    );
  }

  @override
  Future<List<VentaServerModel>> getVentas(
    String tiendaId,
    String periodoId,
  ) async {
    getCalls++;
    return const [];
  }

  /// DELETE /venta. Cada llamada queda registrada con sus tres argumentos para
  /// poder afirmar que se anuló *esa* venta, en esa tienda y ese período.
  final List<({String tiendaId, String periodoId, String ventaId})>
      cancelCalls = [];

  /// Error a lanzar en cada DELETE, en orden. `null` = éxito.
  List<Object?> erroresDeCancelacion = const [];

  /// Igual que [FakeProductosRemote.puerta], para dejar un DELETE en vuelo.
  Completer<void>? puertaCancelacion;

  @override
  Future<void> cancelarVenta(
    String tiendaId,
    String periodoId,
    String ventaId,
  ) async {
    final intento = cancelCalls.length;
    cancelCalls
        .add((tiendaId: tiendaId, periodoId: periodoId, ventaId: ventaId));
    final p = puertaCancelacion;
    if (p != null) await p.future;
    final error = intento < erroresDeCancelacion.length
        ? erroresDeCancelacion[intento]
        : null;
    if (error != null) throw error;
  }
}

// ==========================================
// Locales
// ==========================================

class FakeProductosLocalSync extends Fake
    implements ProductosLocalDataSource {
  List<ProductoModel> almacenados = [];
  int cacheCalls = 0;
  final List<Map<String, double>> updateExistenciasCalls = [];

  @override
  Future<List<ProductoModel>> getProductos(String tiendaId) async =>
      almacenados;

  @override
  Future<void> cacheProductos(
    String tiendaId,
    List<ProductoModel> productos,
  ) async {
    cacheCalls++;
    almacenados = productos;
  }

  @override
  Future<void> updateExistencias(Map<String, double> existencias) async =>
      updateExistenciasCalls.add(existencias);

  @override
  Future<List<CategoriaModel>> getCategorias(String tiendaId) async => const [];
}

class FakePeriodosLocalSync extends Fake implements PeriodosLocalDataSource {
  PeriodoModel? almacenado;
  int deleteCalls = 0;
  int replaceCalls = 0;

  @override
  Future<PeriodoModel?> getPeriodo(String tiendaId) async => almacenado;

  @override
  Future<void> replacePeriodo(String tiendaId, PeriodoModel periodo) async {
    replaceCalls++;
    almacenado = periodo;
  }

  @override
  Future<void> deletePeriodo(String tiendaId) async {
    deleteCalls++;
    almacenado = null;
  }
}

class FakeTransferLocalSync extends Fake
    implements TransferDestinationsLocalDataSource {
  @override
  Future<void> cacheDestinos(
    String tiendaId,
    List<TransferDestinationModel> destinos,
  ) async {}

  @override
  Future<List<TransferDestinationModel>> getDestinos(String tiendaId) async =>
      const [];
}

class FakeMultimonedaLocalSync extends Fake
    implements MultimonedaLocalDataSource {
  MultimonedaConfig? config;

  @override
  Future<MultimonedaConfig?> getConfig(String negocioId) async => config;

  @override
  Future<void> saveConfig(MultimonedaConfig c) async => config = c;
}

/// Cola de ventas en memoria, con el suficiente comportamiento real para que
/// los ciclos de sincronización se puedan ejercitar de punta a punta.
class FakeVentasLocalSync extends Fake implements VentasLocalDataSource {
  FakeVentasLocalSync({List<VentaLocalModel>? ventas})
      : ventas = [...?ventas];

  final List<VentaLocalModel> ventas;
  int resetStaleCalls = 0;
  final List<({String syncId, String periodoId})> cambiosDePeriodo = [];

  /// Si se define, [resetStaleSyncing] lanza. Sirve para comprobar que un fallo
  /// de la recuperación no impide arrancar el monitoreo.
  Object? errorAlRecuperarSyncing;

  /// Si se define, [getVentasPendientes] lanza. Es el único paso de `fullSync`
  /// cuya excepción sí escapa del método.
  Object? errorAlListarPendientes;

  VentaLocalModel? _find(String syncId) {
    for (final v in ventas) {
      if (v.syncId == syncId) return v;
    }
    return null;
  }

  void _replace(String syncId, VentaLocalModel nueva) {
    final i = ventas.indexWhere((v) => v.syncId == syncId);
    if (i >= 0) ventas[i] = nueva;
  }

  @override
  Future<int> resetStaleSyncing() async {
    resetStaleCalls++;
    final e = errorAlRecuperarSyncing;
    if (e != null) throw e;
    return 0;
  }

  @override
  Future<List<VentaLocalModel>> getVentasPendientes() async {
    final e = errorAlListarPendientes;
    if (e != null) throw e;
    return ventas
        .where((v) =>
            v.syncState == SyncState.pending || v.syncState == SyncState.error)
        .toList();
  }

  @override
  Future<List<VentaLocalModel>> getCancelacionesPendientes() async => ventas
      .where((v) => v.syncState == SyncState.cancelPending)
      .toList();

  @override
  Future<List<VentaLocalModel>> getCancelacionesPendientesByTienda(
    String tiendaId,
  ) async =>
      ventas
          .where((v) =>
              v.tiendaId == tiendaId && v.syncState == SyncState.cancelPending)
          .toList();

  @override
  Future<VentaLocalModel?> getVentaBySyncId(String syncId) async =>
      _find(syncId);

  // Cuenta sobre la lista, sin pasar por getVentasPendientes: en la BD real son
  // dos consultas independientes, y hacerlas compartir el fallo simulado haría
  // que `errorAlListarPendientes` rompiera también este contador.
  @override
  Future<int> countPendientes() async => ventas
      .where((v) =>
          v.syncState == SyncState.pending || v.syncState == SyncState.error)
      .length;

  @override
  Future<int> countVentasConError() async => ventas
      .where((v) =>
          v.syncState == SyncState.error ||
          v.syncState == SyncState.cancelError)
      .length;

  @override
  Future<void> saveVentaPendiente(VentaLocalModel venta) async =>
      ventas.add(venta);

  @override
  Future<void> updateVentaPendiente(VentaLocalModel venta) async =>
      _replace(venta.syncId, venta);

  @override
  Future<void> deleteBySyncId(String syncId) async =>
      ventas.removeWhere((v) => v.syncId == syncId);

  @override
  Future<void> updateSyncState(
    String syncId, {
    SyncState? syncState,
    int? syncAttempts,
    String? errorMessage,
    String? serverId,
  }) async {
    final actual = _find(syncId);
    if (actual == null) return;
    _replace(
      syncId,
      actual.copyWith(
        syncState: syncState,
        syncAttempts: syncAttempts,
        errorMessage: errorMessage,
        serverId: serverId,
      ),
    );
  }

  @override
  Future<void> updateVentaPeriodo(String syncId, String newPeriodoId) async {
    cambiosDePeriodo.add((syncId: syncId, periodoId: newPeriodoId));
    final actual = _find(syncId);
    if (actual == null) return;
    // copyWith no expone periodoId (es lo que esta operación cambia), así que
    // se reconstruye a mano, igual que hace el UPDATE real.
    _replace(
      syncId,
      ventaLocalDe(
        syncId,
        tiendaId: actual.tiendaId,
        periodoId: newPeriodoId,
        syncState: SyncState.pending,
        syncAttempts: actual.syncAttempts,
        serverId: actual.serverId,
        productos: actual.productos,
      ),
    );
  }

  @override
  Future<void> cacheVentasServidor(
    String tiendaId,
    String periodoId,
    List<VentaServerModel> ventas,
  ) async {}

  @override
  Future<List<VentaServerModel>> getVentasServidorCache(
    String tiendaId,
    String periodoId,
  ) async =>
      const [];
}

// ==========================================
// Banco de pruebas
// ==========================================

/// Agrupa el [SyncService] real con todos sus fakes, para poder afirmar sobre
/// el número de llamadas de cada uno.
class SyncHarness {
  SyncHarness({
    bool online = true,
    bool reachable = true,
    PeriodoModel? periodoServidor,
    List<VentaLocalModel>? ventas,
    List<String?> erroresDeVenta = const [],
  })  : connectivity = FakeConnectivity(online: online),
        apiClient = FakeApiClientSync(reachable: reachable),
        productosRemote = FakeProductosRemote(),
        periodosRemote = FakePeriodosRemote(periodo: periodoServidor),
        monedasRemote = FakeMonedasRemote(),
        tasasRemote = FakeTasasRemote(),
        transferRemote = FakeTransferRemote(),
        ventasRemote = FakeVentasRemote(errorPorIntento: erroresDeVenta),
        productosLocal = FakeProductosLocalSync(),
        periodosLocal = FakePeriodosLocalSync(),
        transferLocal = FakeTransferLocalSync(),
        multimonedaLocal = FakeMultimonedaLocalSync(),
        ventasLocal = FakeVentasLocalSync(ventas: ventas),
        // La clave del mapa es `localActual`, igual que en `UsuarioModel.toJson`
        // y que en `SyncService._resolveSyncContext`. Con cualquier otra, el
        // contexto de sync se resuelve a `null` y la reconexión y el timer
        // horario no harían nada — pero los tests seguirían en verde porque el
        // resto de flujos reciben el tiendaId por parámetro.
        storage = FakeStorageSync(
          user: {
            'localActual': {'id': 't1'},
            'negocio': {'id': 'n1'},
          },
        );

  final FakeConnectivity connectivity;
  final FakeApiClientSync apiClient;
  final FakeProductosRemote productosRemote;
  final FakePeriodosRemote periodosRemote;
  final FakeMonedasRemote monedasRemote;
  final FakeTasasRemote tasasRemote;
  final FakeTransferRemote transferRemote;
  final FakeVentasRemote ventasRemote;
  final FakeProductosLocalSync productosLocal;
  final FakePeriodosLocalSync periodosLocal;
  final FakeTransferLocalSync transferLocal;
  final FakeMultimonedaLocalSync multimonedaLocal;
  final FakeVentasLocalSync ventasLocal;
  final FakeStorageSync storage;

  late final SyncService service = SyncService(
    apiClient: apiClient,
    storageService: storage,
    connectivity: connectivity,
    productosRemote: productosRemote,
    periodosRemote: periodosRemote,
    ventasRemote: ventasRemote,
    transferRemote: transferRemote,
    monedasRemote: monedasRemote,
    tasasRemote: tasasRemote,
    productosLocal: productosLocal,
    periodosLocal: periodosLocal,
    ventasLocal: ventasLocal,
    transferLocal: transferLocal,
    multimonedaLocal: multimonedaLocal,
  );

  /// Avisos recibidos por `onDataRefreshed`, en orden.
  final List<SyncRefreshInfo> avisos = [];

  /// Mensajes de `onSyncEvent`, en orden.
  final List<String> eventos = [];

  /// Cada vez que el servicio pidió expulsar al login.
  final List<bool> authRequerido = [];

  /// Cambios de estado de conexión notificados a la UI.
  final List<ConnectionStatus> conexiones = [];

  /// Si se define, `onDataRefreshed` lanza esto: sirve para comprobar que un
  /// fallo de la UI no rompe el ciclo de sincronización.
  Object? errorAlAvisar;

  /// Fija el estado de conexión (leído del fake) y engancha el contador de
  /// avisos. Llamar siempre [parar] al terminar: `startMonitoring` deja vivos
  /// un timer y una suscripción.
  Future<void> arrancar() async {
    service.onDataRefreshed = (info) async {
      avisos.add(info);
      final e = errorAlAvisar;
      if (e != null) throw e;
    };
    service.onSyncEvent = eventos.add;
    service.onAuthRequired = authRequerido.add;
    service.onConnectionChanged = conexiones.add;
    await service.startMonitoring();
  }

  /// Deja correr los microtasks pendientes: los flujos `unawaited` de
  /// `crearVenta` / `anularVenta` y la entrega de eventos del stream de
  /// conectividad no terminan dentro del `await` de la llamada.
  Future<void> bombear([int veces = 8]) async {
    for (var i = 0; i < veces; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void parar() {
    service.stopMonitoring();
    connectivity.dispose();
  }
}
