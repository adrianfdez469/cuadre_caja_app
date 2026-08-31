import 'dart:async';
import 'package:cuadre_caja_app/core/utils/app_logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/network/secure_storage_service.dart';
import '../data/datasources/local/productos_local_datasource.dart';
import '../data/datasources/local/periodos_local_datasource.dart';
import '../data/datasources/local/ventas_local_datasource.dart';
import '../data/datasources/local/transfer_destinations_local_datasource.dart';
import '../data/datasources/local/multimoneda_local_datasource.dart';
import '../data/datasources/remote/productos_remote_datasource.dart';
import '../data/datasources/remote/periodos_remote_datasource.dart';
import '../data/datasources/remote/ventas_remote_datasource.dart';
import '../data/datasources/remote/transfer_destinations_remote_datasource.dart';
import '../data/datasources/remote/monedas_remote_datasource.dart';
import '../data/datasources/remote/tasas_remote_datasource.dart';
import '../data/models/producto_model.dart';
import '../data/models/periodo_model.dart';
import '../data/models/moneda_model.dart';
import '../data/models/tasa_model.dart';
import '../core/errors/exceptions.dart';
import '../data/models/venta_model.dart';
import '../data/models/transfer_destination_model.dart';
import '../data/models/categoria_model.dart';
import '../core/utils/stock_calculator.dart';
import '../core/utils/venta_cancel_policy.dart';
import 'venta_sync_payload_patcher.dart';

enum ConnectionStatus { online, offline }

class SyncService {
  final ApiClient apiClient;
  final SecureStorageService storageService;
  final Connectivity connectivity;

  // Remote
  final ProductosRemoteDataSource productosRemote;
  final PeriodosRemoteDataSource periodosRemote;
  final VentasRemoteDataSource ventasRemote;
  final TransferDestinationsRemoteDataSource transferRemote;
  final MonedasRemoteDataSource monedasRemote;
  final TasasRemoteDataSource tasasRemote;

  // Local
  final ProductosLocalDataSource productosLocal;
  final PeriodosLocalDataSource periodosLocal;
  final VentasLocalDataSource ventasLocal;
  final TransferDestinationsLocalDataSource transferLocal;
  final MultimonedaLocalDataSource multimonedaLocal;

  // State
  ConnectionStatus _connectionStatus = ConnectionStatus.offline;
  StreamSubscription? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isCancelling = false;
  bool _isFullSyncRunning = false;
  String? _lastTiendaId;
  String? _lastNegocioId;
  Future<void>? _connectionRestoreFuture;

  // Cache del probe de alcanzabilidad para no sondear en cada lectura.
  bool? _serverReachable;
  DateTime? _reachableCheckedAt;
  static const Duration _reachableTtl = Duration(seconds: 15);

  // Throttle de validación de sesión. /auth/refresh valida que la sesión siga
  // viva (/health solo confirma que el servidor responde, no la validez del
  // token), pero reconfirmarlo en cada ciclo de sync (cada 30s) inunda la red y
  // el log con "Token refrescado exitosamente". Basta revalidar cada
  // [_authValidityTtl]: el token sigue vigente entre validaciones y, si expirara
  // antes, el interceptor de ApiClient lo refresca on-demand ante un 401.
  DateTime? _lastAuthAt;
  static const Duration _authValidityTtl = Duration(minutes: 5);

  // Callbacks
  void Function(ConnectionStatus)? onConnectionChanged;
  void Function(String message)? onSyncEvent;
  /// Llamado tras fullSync al reconectar para refrescar la UI (sin volver a sincronizar).
  Future<void> Function()? onDataRefreshed;
  void Function(bool needsLogin)? onAuthRequired;
  /// Llamado cuando se refresca el token al reconectar (para actualizar AuthProvider).
  void Function()? onTokenRefreshed;

  SyncService({
    required this.apiClient,
    required this.storageService,
    required this.connectivity,
    required this.productosRemote,
    required this.periodosRemote,
    required this.ventasRemote,
    required this.transferRemote,
    required this.monedasRemote,
    required this.tasasRemote,
    required this.productosLocal,
    required this.periodosLocal,
    required this.ventasLocal,
    required this.transferLocal,
    required this.multimonedaLocal,
  });

  ConnectionStatus get connectionStatus => _connectionStatus;
  bool get isOnline => _connectionStatus == ConnectionStatus.online;

  /// ¿El servidor responde de verdad? `isOnline` (connectivity_plus) solo indica
  /// que hay red; esto sondea el servidor con timeout corto y cachea el resultado
  /// por [_reachableTtl] para no bloquear cada lectura. Si no hay red, `false` sin
  /// sondear. Las lecturas usan esto para ir directo a cache cuando no se alcanza
  /// el servidor, en vez de esperar el timeout completo del request.
  Future<bool> _isServerReachable() async {
    if (!isOnline) return false;
    final now = DateTime.now();
    final cached = _serverReachable;
    final at = _reachableCheckedAt;
    if (cached != null && at != null && now.difference(at) < _reachableTtl) {
      return cached;
    }
    final reachable = await apiClient.isServerReachable();
    _serverReachable = reachable;
    _reachableCheckedAt = now;
    return reachable;
  }

  /// Inicia monitoreo de conectividad y sincronización periódica.
  /// Espera al primer chequeo de conectividad para que isOnline sea correcto antes de cargar datos.
  Future<void> startMonitoring() async {
    // El proceso acaba de arrancar: no hay ningún sync en vuelo, así que
    // cualquier venta en "syncing" es un remanente de un proceso anterior que
    // murió a mitad de sincronizar. Devolverla a "pending" para que se reintente
    // (si no, quedaría atascada: getVentasPendientes() excluye "syncing" y el
    // stock local ya se descontó, pero la venta nunca llegaría al servidor).
    try {
      final recuperadas = await ventasLocal.resetStaleSyncing();
      if (recuperadas > 0) {
        logDebug('♻️ $recuperadas venta(s) recuperada(s) de estado syncing');
      }
    } catch (e) {
      logDebug('⚠️ Error recuperando ventas en syncing: $e');
    }

    await _checkConnectivity();

    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      (result) {
        final wasOffline = !isOnline;
        _connectionStatus = _mapConnectivity(result);
        // La red cambió: invalidar el probe cacheado para re-sondear.
        _serverReachable = null;

        onConnectionChanged?.call(_connectionStatus);

        if (wasOffline && isOnline) {
          logDebug('🌐 Conexión restaurada - iniciando sincronización');
          _onConnectionRestored();
        }
      },
    );

    // Sincronización periódica cada hora si hay conexión.
    // Igual que en el reconnect, se valida/renueva la sesión ANTES de
    // sincronizar: si el token no se puede refrescar, el sync no se intenta.
    _syncTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      if (isOnline && !_isSyncing && !_isFullSyncRunning) {
        if (await _ensureAuthenticated()) {
          await _syncPendingVentas();
        }
      }
    });
  }

  void stopMonitoring() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
  }

  Future<void> _checkConnectivity() async {
    final result = await connectivity.checkConnectivity();
    _connectionStatus = _mapConnectivity(result);
    _serverReachable = null;
    onConnectionChanged?.call(_connectionStatus);
  }

  ConnectionStatus _mapConnectivity(dynamic result) {
    if (result is List) {
      return result.any((r) => r != ConnectivityResult.none)
          ? ConnectionStatus.online
          : ConnectionStatus.offline;
    }
    return result != ConnectivityResult.none
        ? ConnectionStatus.online
        : ConnectionStatus.offline;
  }

  /// Se ejecuta cuando la conexión se restaura.
  /// Ventas primero; inventario del servidor al final (vía fullSync).
  Future<void> _onConnectionRestored() {
    _connectionRestoreFuture ??= _runConnectionRestored().whenComplete(() {
      _connectionRestoreFuture = null;
    });
    return _connectionRestoreFuture!;
  }

  Future<void> _runConnectionRestored() async {
    // Validar/renovar la sesión (refresh -> re-login). _ensureAuthenticated ya
    // dispara onAuthRequired ante un rechazo definitivo; aquí solo abortamos.
    final authOk = await _ensureAuthenticated();
    if (!authOk) return;

    // 3. fullSync: ventas pendientes, inventario al final y refresco de UI
    final ctx = await _resolveSyncContext();
    if (ctx != null) {
      await fullSync(ctx.tiendaId, negocioId: ctx.negocioId);
    }
  }

  Future<({String tiendaId, String? negocioId})?> _resolveSyncContext() async {
    if (_lastTiendaId != null && _lastTiendaId!.isNotEmpty) {
      return (tiendaId: _lastTiendaId!, negocioId: _lastNegocioId);
    }
    final user = await storageService.getUser();
    if (user == null) return null;
    final tiendaId = user['localActual']?['id'] as String?;
    if (tiendaId == null || tiendaId.isEmpty) return null;
    final negocioId = user['negocio']?['id'] as String?;
    return (tiendaId: tiendaId, negocioId: negocioId);
  }

  /// Valida la sesión contra el servidor y la renueva si es posible.
  ///
  /// `/health` solo confirma que el servidor responde, no que el token siga
  /// siendo válido, así que usamos /auth/refresh como probe de sesión: un `ok`
  /// confirma que la sesión sigue viva y deja un token nuevo. Si el token fue
  /// rechazado, intentamos re-login con credenciales guardadas. Solo ante un
  /// rechazo definitivo (no ante fallos de red) se dispara `onAuthRequired`;
  /// esta función es la única dueña de esa decisión.
  Future<bool> _ensureAuthenticated() async {
    final token = await storageService.getToken();
    if (token == null) {
      _lastAuthAt = null;
      onAuthRequired?.call(true);
      return false;
    }

    // La sesión se validó/renovó hace poco: darla por buena sin volver a golpear
    // /auth/refresh en cada ciclo. Si el token expirara entre validaciones, el
    // interceptor de ApiClient lo refresca al primer 401. Un fallo de red o un
    // rechazo (más abajo) limpia _lastAuthAt para forzar revalidación inmediata.
    final lastAuth = _lastAuthAt;
    if (lastAuth != null &&
        DateTime.now().difference(lastAuth) < _authValidityTtl) {
      return true;
    }

    final refresh = await apiClient.refreshToken();
    if (refresh == AuthResult.ok) {
      _lastAuthAt = DateTime.now();
      onTokenRefreshed?.call();
      onSyncEvent?.call('Sesión actualizada');
      return true;
    }
    if (refresh == AuthResult.networkError) {
      // Red inestable / portal cautivo: no podemos validar, pero tampoco
      // expulsamos al usuario. Se reintentará en el próximo ciclo.
      return false;
    }

    // refresh == authRejected: la sesión ya no sirve. Intentar re-login.
    final relogin = await apiClient.reLogin();
    if (relogin == AuthResult.ok) {
      _lastAuthAt = DateTime.now();
      onTokenRefreshed?.call();
      onSyncEvent?.call('Sesión actualizada');
      return true;
    }
    if (relogin == AuthResult.networkError) {
      return false;
    }

    // Rechazo definitivo (sesión muerta y credenciales inválidas/ausentes).
    _lastAuthAt = null;
    onAuthRequired?.call(true);
    return false;
  }

  // ==========================================
  // PRODUCTOS - Network-First Cache
  // ==========================================

  /// Carga productos: intenta API primero, fallback a cache
  Future<List<ProductoModel>> loadProductos(String tiendaId) async {
    if (await _isServerReachable()) {
      try {
        final serverProductos = await productosRemote.getProductos(tiendaId);
        await productosLocal.cacheProductos(tiendaId, serverProductos);
        // Reconciliar: re-aplicar sobre el snapshot del servidor los decrementos
        // de las ventas que aún no se sincronizaron, para no pisar su stock
        // optimista. Sin esto, refrescar inventario "inflaba" el stock de otras
        // ventas pendientes hasta que sincronizaran.
        final ajustados =
            await _reconciliarInventario(tiendaId, serverProductos);
        onSyncEvent?.call('${serverProductos.length} productos sincronizados');
        return ajustados;
      } catch (e) {
        logDebug('⚠️ Error cargando productos del servidor: $e');
        onSyncEvent?.call('Error de red, usando datos locales');
      }
    }

    // Fallback a cache local
    final cached = await productosLocal.getProductos(tiendaId);
    if (cached.isNotEmpty) {
      onSyncEvent?.call('Usando ${cached.length} productos en cache');
    }
    return cached;
  }

  /// Re-aplica sobre el [snapshot] recién traído del servidor las operaciones de
  /// [tiendaId] que el servidor todavía no conoce, y persiste el resultado.
  /// Devuelve la lista con las existencias ya ajustadas para la UI.
  ///
  /// ```
  /// existencia_local = snapshot_servidor − Σ(ventas pendientes)
  ///                                      + Σ(anulaciones pendientes)
  /// ```
  ///
  /// Las anulaciones pendientes son imprescindibles en la fórmula: esas ventas
  /// **sí** están en el snapshot del servidor (se vendieron y sincronizaron) y
  /// **no** están en `getVentasPendientes()`, así que sin sumarlas cada refresco
  /// de inventario revertiría en silencio el stock que la anulación ya devolvió.
  ///
  /// No clampea a 0: permitir existencias negativas offline es intencional
  /// (el POS sigue vendiendo sin stock hasta que las ventas sincronicen).
  Future<List<ProductoModel>> _reconciliarInventario(
    String tiendaId,
    List<ProductoModel> snapshot,
  ) async {
    final pendientes = (await ventasLocal.getVentasPendientes())
        .where((v) => v.tiendaId == tiendaId)
        .toList();
    final anulaciones =
        await ventasLocal.getCancelacionesPendientesByTienda(tiendaId);
    if (pendientes.isEmpty && anulaciones.isEmpty) return snapshot;

    final ajustes = StockCalculator.replayVentas(
      snapshot,
      pendientes,
      anulaciones: anulaciones,
    );
    if (ajustes.isEmpty) return snapshot;

    await productosLocal.updateExistencias(ajustes);
    return snapshot
        .map((p) => ajustes.containsKey(p.id)
            ? p.copyWith(existencia: ajustes[p.id])
            : p)
        .toList();
  }

  /// Solo lectura desde disco (sin red). Útil tras una venta para refrescar el POS al instante.
  Future<List<ProductoModel>> loadProductosLocalOnly(String tiendaId) async {
    return productosLocal.getProductos(tiendaId);
  }

  /// Obtiene categorías (extraídas de productos cacheados)
  Future<List<CategoriaModel>> loadCategorias(String tiendaId) async {
    return await productosLocal.getCategorias(tiendaId);
  }

  // ==========================================
  // PERÍODO - Network-First Cache
  // ==========================================

  /// Carga período actual: intenta API primero, fallback a cache
  Future<PeriodoModel?> loadPeriodoActual(String tiendaId) async {
    if (await _isServerReachable()) {
      try {
        final periodo = await periodosRemote.getPeriodoActual(tiendaId);
        if (periodo != null) {
          await periodosLocal.replacePeriodo(tiendaId, periodo);
        }
        return periodo;
      } catch (e) {
        logDebug('⚠️ Error cargando período del servidor: $e');
      }
    }

    return await periodosLocal.getPeriodo(tiendaId);
  }

  /// Abre un nuevo período (requiere conexión)
  Future<PeriodoModel> abrirPeriodo(String tiendaId) async {
    final periodo = await periodosRemote.abrirPeriodo(tiendaId);
    await periodosLocal.replacePeriodo(tiendaId, periodo);
    return periodo;
  }

  // ==========================================
  // VENTAS - Offline-First
  // ==========================================

  /// Crea una venta (guarda localmente y sincroniza si es posible).
  /// Aplica desagregaciones para productos fracción antes de descontar existencias.
  Future<VentaLocalModel> crearVenta(VentaLocalModel venta) async {
    // Decidir la conectividad una sola vez: si estamos online, la venta se
    // persiste directamente en estado "syncing" para que el sync periódico
    // (_syncTimer) no la tome como pendiente mientras crearVenta aún trabaja.
    // getVentasPendientes() excluye "syncing", así que esto cierra la ventana
    // de carrera que permitía un doble-post de la misma venta.
    final willSync = isOnline;
    final ventaToSave =
        willSync ? venta.copyWith(syncState: SyncState.syncing) : venta;

    await ventasLocal.saveVentaPendiente(ventaToSave);
    onSyncEvent?.call('Venta guardada');

    // Calcular las nuevas existencias solo de los productos tocados (items del
    // carrito + padres/hijos de desagregación) y escribirlas en una sola
    // transacción atómica, en vez de reescribir todo el catálogo por venta.
    // Si no hay productos cacheados no se puede ajustar el stock, pero la venta
    // igual debe sincronizarse: no retornar temprano aquí, o una venta "syncing"
    // quedaría atascada sin que se dispare su sync.
    final productos = await productosLocal.getProductos(venta.tiendaId);
    if (productos.isNotEmpty) {
      final existencias = StockCalculator.existenciasTrasVenta(venta, productos);
      await productosLocal.updateExistencias(existencias);
    }

    if (willSync) {
      // La venta ya está en "syncing" y el stock actualizado: no esperar al
      // servidor.
      unawaited(() async {
        await _syncSingleVenta(ventaToSave);
        await _refreshInventarioFromServer(venta.tiendaId);
      }());
    } else {
      onSyncEvent?.call('Venta guardada offline - se sincronizará al conectarse');
    }

    return ventaToSave;
  }

  /// Sincroniza una venta individual
  Future<bool> _syncSingleVenta(VentaLocalModel venta) async {
    // Estado más reciente en BD (puede diferir del parámetro): se mantiene fuera
    // del try para que el catch incremente syncAttempts sobre el valor releído,
    // no sobre el desactualizado del parámetro.
    var toSync = venta;
    try {
      // Puede ya estar en syncing (p. ej. tras crearVenta en segundo plano).
      final actual = await ventasLocal.getVentaBySyncId(venta.syncId);
      toSync = actual ?? venta;

      // Parche para ventas de APK antigua (payload pre-multimoneda / datos incompletos).
      toSync = await _prepareVentaForSync(toSync);
      if (!VentaSyncPayloadPatcher.isPayloadReady(toSync)) {
        const msg =
            'Datos insuficientes para crear la venta: no se pudo completar el payload de sincronización';
        logDebug('❌ Venta ${toSync.syncId} con payload incompleto tras parche');
        await ventasLocal.updateSyncState(
          toSync.syncId,
          syncState: SyncState.error,
          syncAttempts: toSync.syncAttempts + 1,
          errorMessage: msg,
        );
        onSyncEvent?.call('Venta con datos incompletos');
        return false;
      }

      if (toSync.syncState != SyncState.syncing) {
        await ventasLocal.updateSyncState(
          toSync.syncId,
          syncState: SyncState.syncing,
          errorMessage: '',
        );
      }

      final result = await ventasRemote.crearVenta(toSync);

      await ventasLocal.updateSyncState(
        toSync.syncId,
        syncState: SyncState.synced,
        serverId: result.venta.id,
      );

      if (result.duplicado) {
        onSyncEvent?.call('Venta ya registrada (duplicado)');
      } else {
        onSyncEvent?.call('Venta sincronizada ✓');
      }
      return true;
    } catch (e) {
      final errorMessage = e is SyncVentaException ? e.message : e.toString();
      logDebug('❌ Error sincronizando venta ${toSync.syncId}: $errorMessage');

      await ventasLocal.updateSyncState(
        toSync.syncId,
        syncState: SyncState.error,
        syncAttempts: toSync.syncAttempts + 1,
        errorMessage: errorMessage,
      );

      onSyncEvent?.call('Error sincronizando venta');
      return false;
    }
  }

  /// Parchea ventas pendientes con payload incompleto y persiste los cambios localmente.
  Future<VentaLocalModel> _prepareVentaForSync(VentaLocalModel venta) async {
    if (!VentaSyncPayloadPatcher.needsPatch(venta)) return venta;

    final productos = await productosLocal.getProductos(venta.tiendaId);
    final multimoneda = await multimonedaLocal.getConfig(
      (await storageService.getUser())?['negocio']?['id'] as String? ?? '',
    );
    final patchResult = VentaSyncPayloadPatcher.patch(
      venta,
      productos: productos,
      monedaBase: multimoneda?.monedaBase,
      tasaSnapshot: multimoneda?.tasasVigentes,
    );

    if (!patchResult.wasPatched) return venta;

    var patched = patchResult.venta;
    if (patched.syncState == SyncState.error) {
      patched = patched.copyWith(errorMessage: null);
    }

    await ventasLocal.updateVentaPendiente(patched);
    logDebug(
      '🔧 Venta ${patched.syncId} parcheada (${patchResult.fixesApplied.join(", ")})',
    );
    onSyncEvent?.call('Venta actualizada para sincronizar');
    return patched;
  }

  /// Sincroniza todas las ventas pendientes.
  /// Tras el intento (éxito o fallo), actualiza inventario del servidor si hubo pendientes.
  /// [refreshInventarioAfter]: en fullSync se desactiva porque el inventario se refresca al final.
  Future<SyncResult> _syncPendingVentas({
    String? inventarioTiendaId,
    bool refreshInventarioAfter = true,
  }) async {
    if (_isSyncing) return SyncResult(synced: 0, failed: 0, pending: 0);

    _isSyncing = true;
    int synced = 0;
    int failed = 0;
    String? tiendaId = inventarioTiendaId;

    try {
      final pendientes = await ventasLocal.getVentasPendientes();

      if (pendientes.isNotEmpty) {
        logDebug('🔄 Sincronizando ${pendientes.length} ventas pendientes...');
        onSyncEvent?.call('Sincronizando ${pendientes.length} ventas...');

        for (final venta in pendientes) {
          tiendaId ??= venta.tiendaId;
          final ok = await _syncSingleVenta(venta);
          if (ok) {
            synced++;
          } else {
            failed++;
          }
        }

        if (synced > 0) {
          onSyncEvent?.call('$synced ventas sincronizadas');
        }
        if (failed > 0) {
          onSyncEvent?.call('$failed ventas con error');
        }
      }

      // Después de subir las ventas: una venta puede haberse creado y anulado
      // en el mismo ciclo, y su anulación necesita el serverId que acaba de
      // asignarle el POST. Va aquí y no antes por eso.
      final cancelaciones = await _syncPendingCancelaciones();
      tiendaId ??= cancelaciones.tiendaId;

      // Sin ventas ni anulaciones no hay nada que reconciliar: no se molesta al
      // servidor con un refresco de inventario.
      if (refreshInventarioAfter &&
          (pendientes.isNotEmpty || cancelaciones.anuladas > 0) &&
          tiendaId != null &&
          tiendaId.isNotEmpty) {
        await _refreshInventarioFromServer(tiendaId);
      }
    } finally {
      _isSyncing = false;
    }

    final remaining = await ventasLocal.countPendientes();
    return SyncResult(synced: synced, failed: failed, pending: remaining);
  }

  /// Inventario del servidor → BD local. Siempre el último paso tras sync de ventas.
  Future<void> _refreshInventarioFromServer(String tiendaId) async {
    if (!isOnline || tiendaId.isEmpty) return;
    onSyncEvent?.call('Actualizando inventario...');
    await loadProductos(tiendaId);
    try {
      await onDataRefreshed?.call();
    } catch (e) {
      logDebug('⚠️ Error refrescando UI tras sync de venta: $e');
    }
  }

  /// Fuerza sincronización manual
  Future<SyncResult> forceSyncVentas() async {
    if (!isOnline) {
      return SyncResult(
        synced: 0,
        failed: 0,
        pending: await ventasLocal.countPendientes(),
      );
    }

    final authOk = await _ensureAuthenticated();
    if (!authOk) {
      // _ensureAuthenticated ya decidió si expulsar (onAuthRequired) o solo
      // posponer por red inestable.
      return SyncResult(synced: 0, failed: 0, pending: 0);
    }

    return await _syncPendingVentas(
      inventarioTiendaId: (await _resolveSyncContext())?.tiendaId,
    );
  }

  /// Obtiene ventas del servidor para el período actual
  Future<List<VentaServerModel>> loadVentas(
    String tiendaId,
    String periodoId,
  ) async {
    if (await _isServerReachable()) {
      try {
        final ventas = await ventasRemote.getVentas(tiendaId, periodoId);
        // Cachear lista completa para modo offline
        await ventasLocal.cacheVentasServidor(tiendaId, periodoId, ventas);
        return ventas;
      } catch (e) {
        logDebug('⚠️ Error cargando ventas del servidor: $e');
      }
    }
    // Sin conexión o error: usar cache local de ventas del servidor si existe
    try {
      return await ventasLocal.getVentasServidorCache(tiendaId, periodoId);
    } catch (e) {
      logDebug('⚠️ Error cargando ventas cacheadas: $e');
      return [];
    }
  }

  /// Sincroniza una sola venta por syncId (solo si está pendiente o error)
  Future<bool> syncSingleVentaBySyncId(String syncId) async {
    if (!isOnline) return false;
    final venta = await ventasLocal.getVentaBySyncId(syncId);
    if (venta == null) return false;
    if (venta.syncState == SyncState.synced || venta.syncState == SyncState.syncing) {
      return true;
    }
    final ok = await _syncSingleVenta(venta);
    await _refreshInventarioFromServer(venta.tiendaId);
    return ok;
  }

  /// Pide la anulación de una venta.
  ///
  /// Una venta que nunca llegó al servidor se borra en el acto. Una que sí está
  /// en el servidor **no** se borra hasta que el servidor confirme el DELETE: se
  /// marca `cancelPending`, se devuelve el stock de forma optimista y la
  /// anulación entra en la cola, igual que una venta entra en la cola de subida.
  /// Con conexión, el drenaje arranca de inmediato en segundo plano.
  ///
  /// Nunca informa de éxito por algo que el servidor no confirmó: ese era el
  /// fallo que hacía divergir la caja local del servidor al anular sin conexión.
  Future<AnulacionResultado> anularVenta(String syncId) async {
    final venta = await ventasLocal.getVentaBySyncId(syncId);
    final plan = VentaCancelPolicy.planFor(venta);

    switch (plan) {
      case AnulacionPlan.sinFilaLocal:
        return AnulacionResultado.noPermitida;

      case AnulacionPlan.yaEnCurso:
        return AnulacionResultado.yaEnCurso;

      case AnulacionPlan.subidaEnVuelo:
        return AnulacionResultado.subidaEnVuelo;

      case AnulacionPlan.borradoLocal:
        await _devolverStock(venta!);
        await ventasLocal.deleteBySyncId(syncId);
        onSyncEvent?.call('Venta eliminada');
        return AnulacionResultado.borrada;

      case AnulacionPlan.encolar:
        await ventasLocal.updateSyncState(
          syncId,
          syncState: SyncState.cancelPending,
          errorMessage: '',
        );
        await _devolverStock(venta!);

        if (isOnline) {
          // Igual que `crearVenta`: no se bloquea la UI esperando al servidor.
          unawaited(() async {
            await _syncPendingCancelaciones();
            await _refreshInventarioFromServer(venta.tiendaId);
          }());
        } else {
          onSyncEvent?.call('Anulación pendiente - se aplicará al reconectar');
        }
        return AnulacionResultado.encolada;
    }
  }

  /// Vuelve a pedir una anulación que el servidor rechazó: reaplica la
  /// devolución de stock (el rechazo la revirtió) y la devuelve a la cola.
  Future<void> reintentarAnulacion(String syncId) async {
    final venta = await ventasLocal.getVentaBySyncId(syncId);
    if (venta == null || venta.syncState != SyncState.cancelError) return;

    await ventasLocal.updateSyncState(
      syncId,
      syncState: SyncState.cancelPending,
      errorMessage: '',
    );
    await _devolverStock(venta);

    if (isOnline) {
      unawaited(() async {
        await _syncPendingCancelaciones();
        await _refreshInventarioFromServer(venta.tiendaId);
      }());
    }
  }

  /// Desiste de una anulación rechazada: la venta vuelve a ser una venta normal.
  /// El stock no se toca porque el rechazo ya lo revirtió.
  Future<void> descartarAnulacion(String syncId) async {
    final venta = await ventasLocal.getVentaBySyncId(syncId);
    if (venta == null || venta.syncState != SyncState.cancelError) return;

    await ventasLocal.updateSyncState(
      syncId,
      syncState: SyncState.synced,
      errorMessage: '',
    );
  }

  /// Devuelve al stock local lo vendido en [venta].
  Future<void> _devolverStock(VentaLocalModel venta) async {
    final productos = await productosLocal.getProductos(venta.tiendaId);
    if (productos.isEmpty) return;
    await productosLocal.updateExistencias(
      StockCalculator.existenciasTrasRestauracion(venta, productos),
    );
  }

  /// Inverso de [_devolverStock]: la anulación no prosperó, la venta sigue viva.
  Future<void> _revertirDevolucionDeStock(VentaLocalModel venta) async {
    final productos = await productosLocal.getProductos(venta.tiendaId);
    if (productos.isEmpty) return;
    await productosLocal.updateExistencias(
      StockCalculator.existenciasTrasRollbackDeAnulacion(venta, productos),
    );
  }

  /// Drena la cola de anulaciones: pide al servidor el DELETE de cada venta que
  /// el cajero anuló. Se ejecuta **después** de subir las ventas pendientes (una
  /// venta puede crearse y anularse en el mismo ciclo) y **antes** de refrescar
  /// el inventario del servidor.
  Future<({int anuladas, String? tiendaId})> _syncPendingCancelaciones() async {
    // El drenaje se dispara desde varios sitios a la vez (el fire-and-forget de
    // `anularVenta`, el timer de 30s, la reconexión). Sin este guard, dos
    // pasadas podrían leer la misma fila `cancelPending` antes de que ninguna la
    // marque `cancelling` y mandar el DELETE dos veces.
    if (_isCancelling) return (anuladas: 0, tiendaId: null);
    _isCancelling = true;

    try {
      final pendientes = await ventasLocal.getCancelacionesPendientes();
      if (pendientes.isEmpty) return (anuladas: 0, tiendaId: null);

      logDebug('🔄 Anulando ${pendientes.length} ventas...');
      onSyncEvent?.call('Anulando ${pendientes.length} ventas...');

      var anuladas = 0;
      for (final venta in pendientes) {
        final serverId = venta.serverId;
        if (serverId == null || serverId.isEmpty) {
          // No debería ocurrir (solo se encola con serverId), pero si pasa la
          // venta no existe en el servidor: la anulación ya está cumplida.
          await ventasLocal.deleteBySyncId(venta.syncId);
          anuladas++;
          continue;
        }

        await ventasLocal.updateSyncState(
          venta.syncId,
          syncState: SyncState.cancelling,
        );

        try {
          await ventasRemote.cancelarVenta(
            venta.tiendaId,
            venta.periodoId,
            serverId,
          );
          await ventasLocal.deleteBySyncId(venta.syncId);
          anuladas++;
        } catch (e) {
          if (_esVentaInexistente(e)) {
            // Ya no está en el servidor: la anulación está cumplida.
            await ventasLocal.deleteBySyncId(venta.syncId);
            anuladas++;
          } else {
            await _marcarAnulacionFallida(venta, e);
          }
        }
      }

      if (anuladas > 0) {
        onSyncEvent?.call('$anuladas ventas anuladas ✓');
      }
      return (anuladas: anuladas, tiendaId: pendientes.first.tiendaId);
    } finally {
      _isCancelling = false;
    }
  }

  /// El servidor rechazó la anulación: se revierte el stock devuelto y la venta
  /// vuelve a la lista marcada, con el motivo real a la vista.
  ///
  /// No se reintenta sola: los motivos habituales (403 sin permiso, 400 período
  /// cerrado) son permanentes, y reintentar cada 30s solo generaría ruido. El
  /// cajero decide desde la lista si reintentar o descartar.
  Future<void> _marcarAnulacionFallida(VentaLocalModel venta, Object e) async {
    final motivo = _mensajeDeErrorDeAnulacion(e);
    logDebug('❌ Anulación de ${venta.syncId} rechazada: $motivo');

    await _revertirDevolucionDeStock(venta);
    await ventasLocal.updateSyncState(
      venta.syncId,
      syncState: SyncState.cancelError,
      syncAttempts: venta.syncAttempts + 1,
      errorMessage: motivo,
    );
    onSyncEvent?.call('No se pudo anular una venta');
  }

  /// Un 404 significa que la venta ya no está en el servidor: el objetivo de la
  /// anulación ya se cumplió, así que no es un fallo.
  bool _esVentaInexistente(Object e) =>
      e is DioException && e.response?.statusCode == 404;

  String _mensajeDeErrorDeAnulacion(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) return data['error'] as String;
      final code = e.response?.statusCode;
      if (code != null) return 'El servidor rechazó la anulación (HTTP $code)';
    }
    return e.toString();
  }

  // ==========================================
  // TRANSFER DESTINATIONS - Network-First Cache
  // ==========================================

  /// Lee destinos desde SQLite (sin red). Para UI / cobro.
  Future<List<TransferDestinationModel>> getTransferDestinationsLocal(
    String tiendaId,
  ) =>
      transferLocal.getDestinos(tiendaId);

  /// Refresca destinos desde la API y cachea. Usar solo en sync (`fullSync`).
  Future<List<TransferDestinationModel>> loadTransferDestinations(
    String tiendaId,
  ) async {
    if (await _isServerReachable()) {
      try {
        final destinos = await transferRemote.getDestinos(tiendaId);
        await transferLocal.cacheDestinos(tiendaId, destinos);
        return destinos;
      } catch (e) {
        logDebug('⚠️ Error cargando destinos: $e');
      }
    }
    return await transferLocal.getDestinos(tiendaId);
  }

  // ==========================================
  // MULTIMONEDA - Network-First Cache
  // ==========================================

  /// Lee config multimoneda desde SQLite (sin red).
  Future<MultimonedaConfig?> getMultimonedaConfigLocal(String negocioId) =>
      multimonedaLocal.getConfig(negocioId);

  /// Carga monedas + tasas: intenta API primero, fallback a cache.
  Future<MultimonedaConfig> loadMultimonedaConfig(
    String negocioId, {
    String? fallbackMonedaBase,
  }) async {
    final baseFallback = fallbackMonedaBase ?? 'CUP';

    if (await _isServerReachable()) {
      try {
        final results = await Future.wait([
          monedasRemote.getMonedas(negocioId),
          tasasRemote.getTasasCambio(negocioId),
        ]);
        final monedasResp = results[0] as MonedasNegocioResponse;
        final tasasResp = results[1] as TasasVigentesResponse;

        final config = MultimonedaConfig(
          negocioId: negocioId,
          monedaBase: tasasResp.monedaBase.isNotEmpty
              ? tasasResp.monedaBase
              : baseFallback,
          tasasVigentes: tasasResp.vigentes,
          tasasConversion: tasasResp.tasasCup,
          monedas: monedasResp.monedas,
          tasasActualizadoEn: tasasResp.actualizadoEn,
        );
        await multimonedaLocal.saveConfig(config);
        onSyncEvent?.call(
          '${config.monedasActivas.length} monedas · base ${config.monedaBase}',
        );
        return config;
      } catch (e) {
        logDebug('⚠️ Error cargando multimoneda del servidor: $e');
        onSyncEvent?.call('Error de red, usando monedas en cache');
      }
    }

    final cached = await multimonedaLocal.getConfig(negocioId);
    if (cached != null) {
      onSyncEvent?.call('Usando monedas en cache (${cached.monedaBase})');
      return cached;
    }

    return MultimonedaConfig(
      negocioId: negocioId,
      monedaBase: baseFallback,
    );
  }

  // ==========================================
  // SYNC COMPLETO (al iniciar o reconectar)
  // ==========================================

  /// Sincronización completa: período/destinos/monedas → ventas pendientes → inventario.
  Future<void> fullSync(String tiendaId, {String? negocioId}) async {
    if (!isOnline) {
      onSyncEvent?.call('Sin conexión - usando datos locales');
      return;
    }

    _lastTiendaId = tiendaId;
    if (negocioId != null && negocioId.isNotEmpty) {
      _lastNegocioId = negocioId;
    }

    if (_isFullSyncRunning) {
      logDebug('⏳ fullSync ya en curso, omitiendo duplicado');
      return;
    }

    _isFullSyncRunning = true;
    try {
      onSyncEvent?.call('Sincronizando...');

      // 1. Período, destinos y multimoneda (sin inventario)
      try {
        final futures = <Future<void>>[
          loadPeriodoActual(tiendaId).then((_) {}),
          loadTransferDestinations(tiendaId).then((_) {}),
        ];
        if (negocioId != null && negocioId.isNotEmpty) {
          futures.add(loadMultimonedaConfig(negocioId).then((_) {}));
        }
        await Future.wait(futures);
        onSyncEvent?.call('Datos actualizados ✓');
      } catch (e) {
        logDebug('⚠️ Error en sincronización completa: $e');
        onSyncEvent?.call('Error parcial en sincronización');
      }

      // 2. Ventas pendientes (sin refrescar inventario aquí)
      await _syncPendingVentas(
        inventarioTiendaId: tiendaId,
        refreshInventarioAfter: false,
      );

      // 3. Inventario del servidor — último paso para reflejar cantidades reales
      await _refreshInventarioFromServer(tiendaId);
    } finally {
      _isFullSyncRunning = false;
    }
  }

  /// Mueve una venta a un nuevo período y la resetea a pendiente para re-sync.
  Future<void> updateVentaPeriodo(String syncId, String newPeriodoId) async {
    await ventasLocal.updateVentaPeriodo(syncId, newPeriodoId);
  }

  /// Info de ventas pendientes
  Future<int> getPendingCount() async {
    return await ventasLocal.countPendientes();
  }
}

class SyncResult {
  final int synced;
  final int failed;
  final int pending;

  SyncResult({
    required this.synced,
    required this.failed,
    required this.pending,
  });
}
