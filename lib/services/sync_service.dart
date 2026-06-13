import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/network/api_client.dart';
import '../core/network/secure_storage_service.dart';
import '../data/datasources/local/productos_local_datasource.dart';
import '../data/datasources/local/periodos_local_datasource.dart';
import '../data/datasources/local/ventas_local_datasource.dart';
import '../data/datasources/local/transfer_destinations_local_datasource.dart';
import '../data/datasources/remote/productos_remote_datasource.dart';
import '../data/datasources/remote/periodos_remote_datasource.dart';
import '../data/datasources/remote/ventas_remote_datasource.dart';
import '../data/datasources/remote/transfer_destinations_remote_datasource.dart';
import '../data/models/producto_model.dart';
import '../data/models/periodo_model.dart';
import '../core/errors/exceptions.dart';
import '../data/models/venta_model.dart';
import '../data/models/transfer_destination_model.dart';
import '../data/models/categoria_model.dart';
import '../core/utils/producto_pos_rules.dart';
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

  // Local
  final ProductosLocalDataSource productosLocal;
  final PeriodosLocalDataSource periodosLocal;
  final VentasLocalDataSource ventasLocal;
  final TransferDestinationsLocalDataSource transferLocal;

  // State
  ConnectionStatus _connectionStatus = ConnectionStatus.offline;
  StreamSubscription? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;

  // Callbacks
  void Function(ConnectionStatus)? onConnectionChanged;
  void Function(String message)? onSyncEvent;
  void Function()? onDataRefreshed;
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
    required this.productosLocal,
    required this.periodosLocal,
    required this.ventasLocal,
    required this.transferLocal,
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

    // Sincronización periódica cada 30 segundos si hay conexión
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isOnline && !_isSyncing) {
        _syncPendingVentas();
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

  /// Se ejecuta cuando la conexión se restaura
  Future<void> _onConnectionRestored() async {
    // 1. Refrescar token para tener uno nuevo válido
    try {
      final refreshed = await apiClient.tryRefreshToken();
      if (refreshed) {
        onTokenRefreshed?.call();
        onSyncEvent?.call('Sesión actualizada');
      }
    } catch (_) {
      // Si falla el refresh, intentar con credenciales guardadas
    }

    // 2. Verificar que sigamos autenticados
    final authOk = await _ensureAuthenticated();
    if (!authOk) {
      onAuthRequired?.call(true);
      return;
    }

    // 3. Sincronizar ventas pendientes PRIMERO
    await _syncPendingVentas();

    // 4. Refrescar datos del servidor
    onSyncEvent?.call('Actualizando datos...');
    onDataRefreshed?.call();
  }

  /// Verifica que el token sea válido, intenta refresh si no
  Future<bool> _ensureAuthenticated() async {
    final token = await storageService.getToken();
    if (token == null) {
      onAuthRequired?.call(true);
      return false;
    }

    // Intentar una petición simple para verificar el token
    try {
      final user = await storageService.getUser();
      if (user == null) return false;

      // El interceptor del ApiClient maneja automáticamente el 401 -> refresh
      // Si el refresh falla, intentar re-login
      return true;
    } catch (_) {
      // Intentar re-login con credenciales guardadas
      final relogged = await apiClient.tryReLogin();
      if (!relogged) {
        onAuthRequired?.call(true);
        return false;
      }
      return true;
    }
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
    await ventasLocal.saveVentaPendiente(venta);
    onSyncEvent?.call('Venta guardada');

    final productos = await productosLocal.getProductos(venta.tiendaId);
    if (productos.isEmpty) return venta;

    // 1) Identificar desagregaciones: producto fracción con existencia < cantidad a vender
    final desagregaciones = <_Desagregacion>[];
    for (final cartProd in venta.productos) {
      final candidatos = productos.where((x) => x.id == cartProd.productoTiendaId).toList();
      final p = candidatos.isEmpty ? null : candidatos.first;
      if (p == null) continue;
      if (!ProductoPosRules.isFraccion(p)) continue;
      if (p.existencia >= cartProd.cantidad) continue;
      final need = cartProd.cantidad - p.existencia;
      final upf = (p.unidadesPorFraccion ?? 1).toDouble();
      final n = (need / upf).ceil().clamp(1, 0x7fffffff);
      final padreId = p.fraccionDe?.id;
      if (padreId == null) continue;
      desagregaciones.add(_Desagregacion(
        padreProductoId: padreId,
        cantidad: n,
        hijoProductoTiendaId: p.id,
        unidadesPorFraccion: upf,
      ));
    }

    // 2) Calcular nuevas existencias: aplicar desagregaciones y luego restar vendido
    final existencias = {for (final p in productos) p.id: p.existencia};

    for (final d in desagregaciones) {
      final padres = productos.where((x) => x.productoId == d.padreProductoId).toList();
      final padre = padres.isEmpty ? null : padres.first;
      if (padre != null) {
        existencias[padre.id] = (existencias[padre.id] ?? padre.existencia) - d.cantidad;
      }
      existencias[d.hijoProductoTiendaId] =
          (existencias[d.hijoProductoTiendaId] ?? 0) + (d.cantidad * d.unidadesPorFraccion);
    }

    for (final cartProd in venta.productos) {
      final prev = existencias[cartProd.productoTiendaId] ?? 0;
      existencias[cartProd.productoTiendaId] = prev - cartProd.cantidad;
    }

    for (final e in existencias.entries) {
      await productosLocal.updateExistencia(e.key, e.value);
    }

    if (isOnline) {
      // Marcar "syncing" antes de programar la red para que otras rutas no
      // intenten la misma venta en paralelo (p. ej. sync periódico).
      await ventasLocal.updateSyncState(
        venta.syncId,
        syncState: SyncState.syncing,
      );
      // No esperar al servidor: la venta ya está guardada y el stock actualizado.
      unawaited(_syncSingleVenta(venta));
    } else {
      onSyncEvent?.call('Venta guardada offline - se sincronizará al conectarse');
    }

    return venta;
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

  /// Parchea ventas pendientes de APK antigua y persiste los cambios localmente.
  Future<VentaLocalModel> _prepareVentaForSync(VentaLocalModel venta) async {
    if (!VentaSyncPayloadPatcher.needsPatch(venta)) return venta;

    final productos = await productosLocal.getProductos(venta.tiendaId);
    final patchResult = VentaSyncPayloadPatcher.patch(
      venta,
      productos: productos,
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

  /// Sincroniza todas las ventas pendientes
  Future<SyncResult> _syncPendingVentas() async {
    if (_isSyncing) return SyncResult(synced: 0, failed: 0, pending: 0);

    _isSyncing = true;
    int synced = 0;
    int failed = 0;

    try {
      final pendientes = await ventasLocal.getVentasPendientes();
      if (pendientes.isEmpty) {
        _isSyncing = false;
        return SyncResult(synced: 0, failed: 0, pending: 0);
      }

      print('🔄 Sincronizando ${pendientes.length} ventas pendientes...');
      onSyncEvent?.call('Sincronizando ${pendientes.length} ventas...');

      for (final venta in pendientes) {
        final ok = await _syncSingleVenta(venta);
        if (ok) {
          synced++;
        } else {
          failed++;
        }
      }

      if (synced > 0) {
        onSyncEvent?.call('$synced ventas sincronizadas');
        // No borrar ventas sincronizadas para poder mostrarlas en lista unificada
      }
      if (failed > 0) {
        onSyncEvent?.call('$failed ventas con error');
      }
    } finally {
      _isSyncing = false;
    }

    final remaining = await ventasLocal.countPendientes();
    return SyncResult(synced: synced, failed: failed, pending: remaining);
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
      onAuthRequired?.call(true);
      return SyncResult(synced: 0, failed: 0, pending: 0);
    }

    return await _syncPendingVentas();
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
    return await _syncSingleVenta(venta);
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
  // SYNC COMPLETO (al iniciar o reconectar)
  // ==========================================

  /// Sincronización completa: ventas pendientes + refrescar datos
  Future<void> fullSync(String tiendaId) async {
    if (!isOnline) {
      onSyncEvent?.call('Sin conexión - usando datos locales');
      return;
    }

    onSyncEvent?.call('Sincronizando...');

    // 1. Ventas pendientes primero
    await _syncPendingVentas();

    // 2. Refrescar productos y período en paralelo
    try {
      await Future.wait([
        loadProductos(tiendaId),
        loadPeriodoActual(tiendaId),
        loadTransferDestinations(tiendaId),
      ]);
      onSyncEvent?.call('Datos actualizados ✓');
    } catch (e) {
      print('⚠️ Error en sincronización completa: $e');
      onSyncEvent?.call('Error parcial en sincronización');
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

class _Desagregacion {
  final String padreProductoId;
  final int cantidad;
  final String hijoProductoTiendaId;
  final double unidadesPorFraccion;

  _Desagregacion({
    required this.padreProductoId,
    required this.cantidad,
    required this.hijoProductoTiendaId,
    required this.unidadesPorFraccion,
  });
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
