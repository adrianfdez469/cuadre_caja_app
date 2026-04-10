import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/models/venta_model.dart';
import '../data/models/cart_model.dart';
import '../services/sync_service.dart';

class VentasProvider extends ChangeNotifier {
  final SyncService _syncService;
  final _uuid = const Uuid();

  List<VentaServerModel> _ventasServidor = [];
  List<VentaLocalModel> _ventasPendientes = [];
  List<VentaUnificadaModel> _ventasUnificado = [];
  bool _isLoading = false;
  bool _isLoadingVentas = false;

  VentasProvider(this._syncService);

  List<VentaServerModel> get ventasServidor => _ventasServidor;
  List<VentaLocalModel> get ventasPendientes => _ventasPendientes;
  List<VentaUnificadaModel> get ventasUnificado => _ventasUnificado;
  bool get isLoading => _isLoading;
  bool get isLoadingVentas => _isLoadingVentas;
  int get pendingCount => _ventasPendientes.length;

  /// Crea una venta desde el carrito activo
  Future<VentaLocalModel> crearVenta({
    required String tiendaId,
    required String periodoId,
    required CartModel cart,
    required double totalcash,
    required double totaltransfer,
    String? transferDestinationId,
    List<String>? discountCodes,
    required bool isOffline,
  }) async {
    final venta = VentaLocalModel(
      syncId: _uuid.v4(),
      tiendaId: tiendaId,
      periodoId: periodoId,
      productos: cart.items.map((item) => VentaProducto(
        productoTiendaId: item.productoTiendaId,
        cantidad: item.cantidad,
        name: item.nombre,
        precio: item.precio,
      )).toList(),
      total: cart.total,
      totalcash: totalcash,
      totaltransfer: totaltransfer,
      transferDestinationId: transferDestinationId,
      wasOffline: isOffline,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      discountCodes: discountCodes,
    );

    final result = await _syncService.crearVenta(venta);
    await refreshPendientes();
    notifyListeners();
    return result;
  }

  /// Carga ventas del servidor
  Future<void> loadVentasServidor(String tiendaId, String periodoId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _ventasServidor = await _syncService.loadVentas(tiendaId, periodoId);
    } catch (e) {
      print('❌ Error cargando ventas: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresca lista de ventas pendientes
  Future<void> refreshPendientes() async {
    _ventasPendientes = await _syncService.ventasLocal.getVentasPendientes();
    notifyListeners();
  }

  /// Fuerza sincronización
  Future<SyncResult> syncPendientes() async {
    final result = await _syncService.forceSyncVentas();
    await refreshPendientes();
    notifyListeners();
    return result;
  }

  /// Carga lista unificada de ventas del período (servidor + local), orden por fecha desc.
  /// Incluye además ventas en estado error de otros períodos de la misma tienda,
  /// para que el usuario pueda resolver conflictos de período (ej. venta offline con período cerrado).
  Future<void> loadVentasUnificado(String tiendaId, String periodoId) async {
    _isLoadingVentas = true;
    notifyListeners();

    try {
      final serverList = await _syncService.loadVentas(tiendaId, periodoId);
      final localList = await _syncService.ventasLocal.getVentasByPeriodo(periodoId);

      // Ventas en error de otros períodos de la misma tienda (conflicto de período offline)
      final errorOtrosPeriodos = await _syncService.ventasLocal.getVentasErrorByTienda(tiendaId);
      final currentPeriodSyncIds = localList.map((v) => v.syncId).toSet();
      final ventasHuerfanas = errorOtrosPeriodos
          .where((v) => v.periodoId != periodoId && !currentPeriodSyncIds.contains(v.syncId))
          .toList();

      final serverIds = serverList.map((v) => v.syncId ?? v.id).toSet();
      _ventasUnificado = [
        ...serverList.map((v) => VentaUnificadaModel.fromServer(v)),
        ...localList
            .where((v) => !serverIds.contains(v.syncId))
            .map((v) => VentaUnificadaModel.fromLocal(v)),
        ...ventasHuerfanas
            .where((v) => !serverIds.contains(v.syncId))
            .map((v) => VentaUnificadaModel.fromLocal(v)),
      ];
      _ventasUnificado.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    } catch (e) {
      print('❌ Error cargando ventas unificado: $e');
    }

    _isLoadingVentas = false;
    notifyListeners();
  }

  /// Sincroniza una venta por syncId
  Future<bool> syncSingleVenta(String syncId) async {
    final ok = await _syncService.syncSingleVentaBySyncId(syncId);
    await refreshPendientes();
    notifyListeners();
    return ok;
  }

  /// Elimina una venta (servidor si synced y hay red; siempre local y restaura stock)
  Future<void> deleteVenta(String syncId, String tiendaId) async {
    await _syncService.deleteVentaAndRestoreStock(syncId, tiendaId);
    await refreshPendientes();
    notifyListeners();
  }

  /// Mueve una venta con conflicto de período al período actual y la resetea a pendiente.
  Future<void> updateVentaPeriodo(String syncId, String newPeriodoId) async {
    await _syncService.updateVentaPeriodo(syncId, newPeriodoId);
    await refreshPendientes();
    notifyListeners();
  }
}
