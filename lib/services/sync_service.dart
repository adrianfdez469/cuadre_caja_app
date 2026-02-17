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
import '../data/models/venta_model.dart';
import '../data/models/transfer_destination_model.dart';
import '../data/models/categoria_model.dart';

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

  /// Crea una venta (guarda localmente y sincroniza si es posible)
  Future<VentaLocalModel> crearVenta(VentaLocalModel venta) async {
    // Siempre guardar localmente primero
    await ventasLocal.saveVentaPendiente(venta);
    onSyncEvent?.call('Venta guardada');

    // Descontar existencia localmente
    for (final producto in venta.productos) {
      final productos = await productosLocal.getProductos(venta.tiendaId);
      final p = productos.where((x) => x.id == producto.productoTiendaId).firstOrNull;
      if (p != null) {
        await productosLocal.updateExistencia(
          producto.productoTiendaId,
          p.existencia - producto.cantidad,
        );
      }
    }

    // Si hay conexión, sincronizar inmediatamente
    if (isOnline) {
      await _syncSingleVenta(venta);
    } else {
      onSyncEvent?.call('Venta guardada offline - se sincronizará al conectarse');
    }

    return venta;
  }

  /// Sincroniza una venta individual
  Future<bool> _syncSingleVenta(VentaLocalModel venta) async {
    try {
      await ventasLocal.updateSyncState(
        venta.syncId,
        syncState: SyncState.syncing,
      );

      String? usuarioId;
      try {
        final user = await storageService.getUser();
        if (user != null) usuarioId = user['id'] as String?;
      } catch (_) {}
      final result = await ventasRemote.crearVenta(venta, usuarioId: usuarioId);

      await ventasLocal.updateSyncState(
        venta.syncId,
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
      print('❌ Error sincronizando venta ${venta.syncId}: $e');

      await ventasLocal.updateSyncState(
        venta.syncId,
        syncState: SyncState.error,
        syncAttempts: venta.syncAttempts + 1,
        errorMessage: e.toString(),
      );

      onSyncEvent?.call('Error sincronizando venta');
      return false;
    }
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
        return await ventasRemote.getVentas(tiendaId, periodoId);
      } catch (e) {
        print('⚠️ Error cargando ventas del servidor: $e');
      }
    }
    return [];
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
