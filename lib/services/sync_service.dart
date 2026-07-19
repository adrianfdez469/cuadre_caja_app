import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  bool _isFullSyncRunning = false;
  String? _lastTiendaId;
  String? _lastNegocioId;
  Future<void>? _connectionRestoreFuture;

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

  /// Inicia monitoreo de conectividad y sincronización periódica.
  /// Espera al primer chequeo de conectividad para que isOnline sea correcto antes de cargar datos.
  Future<void> startMonitoring() async {
    await _checkConnectivity();

    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      (result) {
        final wasOffline = !isOnline;
        _connectionStatus = _mapConnectivity(result);

        onConnectionChanged?.call(_connectionStatus);

        if (wasOffline && isOnline) {
          print('🌐 Conexión restaurada - iniciando sincronización');
          _onConnectionRestored();
        }
      },
    );

    // Sincronización periódica cada 30 segundos si hay conexión.
    // Igual que en el reconnect, se valida/renueva la sesión ANTES de
    // sincronizar: si el token no se puede refrescar, el sync no se intenta.
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
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
  /// No existe endpoint /health, así que usamos /auth/refresh como probe: un
  /// `ok` confirma que la sesión sigue viva y deja un token nuevo. Si el token
  /// fue rechazado, intentamos re-login con credenciales guardadas. Solo ante
  /// un rechazo definitivo (no ante fallos de red) se dispara `onAuthRequired`;
  /// esta función es la única dueña de esa decisión.
  Future<bool> _ensureAuthenticated() async {
    final token = await storageService.getToken();
    if (token == null) {
      onAuthRequired?.call(true);
      return false;
    }

    final refresh = await apiClient.refreshToken();
    if (refresh == AuthResult.ok) {
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
      onTokenRefreshed?.call();
      onSyncEvent?.call('Sesión actualizada');
      return true;
    }
    if (relogin == AuthResult.networkError) {
      return false;
    }

    // Rechazo definitivo (sesión muerta y credenciales inválidas/ausentes).
    onAuthRequired?.call(true);
    return false;
  }

  // ==========================================
  // PRODUCTOS - Network-First Cache
  // ==========================================

  /// Carga productos: intenta API primero, fallback a cache
  Future<List<ProductoModel>> loadProductos(String tiendaId) async {
    if (isOnline) {
      try {
        final productos = await productosRemote.getProductos(tiendaId);
        await productosLocal.cacheProductos(tiendaId, productos);
        onSyncEvent?.call('${productos.length} productos sincronizados');
        return productos;
      } catch (e) {
        print('⚠️ Error cargando productos del servidor: $e');
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
    if (isOnline) {
      try {
        final periodo = await periodosRemote.getPeriodoActual(tiendaId);
        if (periodo != null) {
          await periodosLocal.replacePeriodo(tiendaId, periodo);
        }
        return periodo;
      } catch (e) {
        print('⚠️ Error cargando período del servidor: $e');
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

    final productos = await productosLocal.getProductos(venta.tiendaId);
    if (productos.isEmpty) return ventaToSave;

    // Calcular las nuevas existencias solo de los productos tocados (items del
    // carrito + padres/hijos de desagregación) y escribirlas en una sola
    // transacción atómica, en vez de reescribir todo el catálogo por venta.
    final existencias = StockCalculator.existenciasTrasVenta(venta, productos);
    await productosLocal.updateExistencias(existencias);

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
    try {
      // Puede ya estar en syncing (p. ej. tras crearVenta en segundo plano).
      final actual = await ventasLocal.getVentaBySyncId(venta.syncId);
      var toSync = actual ?? venta;

      // Parche para ventas de APK antigua (payload pre-multimoneda / datos incompletos).
      toSync = await _prepareVentaForSync(toSync);
      if (!VentaSyncPayloadPatcher.isPayloadReady(toSync)) {
        const msg =
            'Datos insuficientes para crear la venta: no se pudo completar el payload de sincronización';
        print('❌ Venta ${toSync.syncId} con payload incompleto tras parche');
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
      print('❌ Error sincronizando venta ${venta.syncId}: $errorMessage');

      await ventasLocal.updateSyncState(
        venta.syncId,
        syncState: SyncState.error,
        syncAttempts: venta.syncAttempts + 1,
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
    print(
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
      if (pendientes.isEmpty) {
        return SyncResult(synced: 0, failed: 0, pending: 0);
      }

      print('🔄 Sincronizando ${pendientes.length} ventas pendientes...');
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

      if (refreshInventarioAfter &&
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
      print('⚠️ Error refrescando UI tras sync de venta: $e');
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
    if (isOnline) {
      try {
        final ventas = await ventasRemote.getVentas(tiendaId, periodoId);
        // Cachear lista completa para modo offline
        await ventasLocal.cacheVentasServidor(tiendaId, periodoId, ventas);
        return ventas;
      } catch (e) {
        print('⚠️ Error cargando ventas del servidor: $e');
      }
    }
    // Sin conexión o error: usar cache local de ventas del servidor si existe
    try {
      return await ventasLocal.getVentasServidorCache(tiendaId, periodoId);
    } catch (e) {
      print('⚠️ Error cargando ventas cacheadas: $e');
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

  /// Elimina una venta: en servidor si está sincronizada y hay red; siempre en local y restaura stock
  Future<void> deleteVentaAndRestoreStock(String syncId, String tiendaId) async {
    final venta = await ventasLocal.getVentaBySyncId(syncId);
    if (venta == null) return;

    if (venta.syncState == SyncState.synced && venta.serverId != null && isOnline) {
      try {
        await ventasRemote.cancelarVenta(venta.tiendaId, venta.periodoId, venta.serverId!);
      } catch (e) {
        print('⚠️ Error eliminando venta en servidor: $e');
      }
    }

    for (final p in venta.productos) {
      await productosLocal.incrementExistencia(p.productoTiendaId, p.cantidad);
    }
    await ventasLocal.deleteBySyncId(syncId);
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
    if (isOnline) {
      try {
        final destinos = await transferRemote.getDestinos(tiendaId);
        await transferLocal.cacheDestinos(tiendaId, destinos);
        return destinos;
      } catch (e) {
        print('⚠️ Error cargando destinos: $e');
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

    if (isOnline) {
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
        print('⚠️ Error cargando multimoneda del servidor: $e');
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
      print('⏳ fullSync ya en curso, omitiendo duplicado');
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
        print('⚠️ Error en sincronización completa: $e');
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
