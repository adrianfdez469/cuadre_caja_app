import 'package:flutter/foundation.dart';
import 'package:cuadre_caja_app/core/utils/app_logger.dart';
import 'package:uuid/uuid.dart';
import '../core/utils/currency.dart';
import '../core/utils/venta_cancel_policy.dart';
import '../data/models/venta_model.dart';
import '../data/models/cart_model.dart';
import '../data/models/pago_multimoneda_model.dart';
import '../data/models/moneda_model.dart';
import '../services/sync_service.dart';

class VentasProvider extends ChangeNotifier {
  final SyncService _syncService;
  final _uuid = const Uuid();

  List<VentaServerModel> _ventasServidor = [];
  List<VentaLocalModel> _ventasPendientes = [];
  List<VentaUnificadaModel> _ventasUnificado = [];
  bool _isLoading = false;
  bool _isLoadingVentas = false;
  int _cancelacionesPendientes = 0;
  int _ventasConError = 0;

  VentasProvider(this._syncService);

  List<VentaServerModel> get ventasServidor => _ventasServidor;
  List<VentaLocalModel> get ventasPendientes => _ventasPendientes;
  List<VentaUnificadaModel> get ventasUnificado => _ventasUnificado;
  bool get isLoading => _isLoading;
  bool get isLoadingVentas => _isLoadingVentas;

  /// Operaciones que aún no llegaron al servidor: ventas por subir **y**
  /// anulaciones por confirmar. Las dos se pierden al cerrar sesión y las dos
  /// deben contar en el "N sin subir" de la barra superior.
  int get pendingCount => _ventasPendientes.length + _cancelacionesPendientes;

  /// Lo que el servidor **rechazó** (ventas en `error` + anulaciones en
  /// `cancelError`): no se reintenta solo, lo tiene que mirar el cajero. Es el
  /// contador que pinta los avisos en rojo.
  int get errorCount => _ventasConError;

  /// Lo que sólo espera conexión (`pending` + `cancelPending`): se resuelve solo
  /// en el próximo ciclo de sync, así que se avisa en ámbar, no en rojo.
  ///
  /// `pendingCount` es la suma de éste y [errorCount]: la consulta local que
  /// alimenta la cola de subida (`getVentasPendientes`) devuelve `pending` y
  /// `error` juntos a propósito.
  int get porSubirCount =>
      _ventasPendientes.where((v) => v.syncState == SyncState.pending).length +
      _cancelacionesPendientes;

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
    MultimonedaConfig? multimoneda,
    List<PagoLinea>? pagosDetalle,
    List<VueltoLinea>? vueltoDetalle,
    Map<String, double>? tasaSnapshot,
    String? monedaCobro,
  }) async {
    final monedaBase = monedaCobro ?? multimoneda?.monedaBase ?? 'CUP';
    final snapshot = tasaSnapshot ?? multimoneda?.tasasConversion ?? const {};
    final totalBase = multimoneda != null
        ? cart.items.fold<double>(
            0,
            (sum, item) =>
                sum +
                CurrencyUtils.convertToBase(
                  item.precio * item.cantidad,
                  item.monedaPrecioCode ?? multimoneda.monedaBase,
                  multimoneda.tasasConversion,
                  multimoneda.monedaBase,
                ),
          )
        : cart.total;

    var venta = VentaLocalModel(
      syncId: _uuid.v4(),
      tiendaId: tiendaId,
      periodoId: periodoId,
      productos: cart.items.map((item) => VentaProducto(
        productoTiendaId: item.productoTiendaId,
        cantidad: item.cantidad,
        name: item.nombre,
        precio: item.precio,
      )).toList(),
      total: totalBase,
      totalcash: totalcash,
      totaltransfer: totaltransfer,
      transferDestinationId: transferDestinationId,
      wasOffline: isOffline,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      discountCodes: discountCodes,
      monedaCobro: monedaBase,
      pagosDetalle: pagosDetalle ?? const [],
      vueltoDetalle: vueltoDetalle ?? const [],
      tasaSnapshot: snapshot,
    );

    if (pagosDetalle == null || pagosDetalle.isEmpty) {
      venta = VentaMultimonedaBuilder.ensureMultimoneda(
        venta,
        monedaBase: monedaBase,
        tasaSnapshot: snapshot,
      );
    }

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
      logDebug('❌ Error cargando ventas: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresca lista de ventas pendientes (y el contador de anulaciones en cola)
  Future<void> refreshPendientes() async {
    _ventasPendientes = await _syncService.ventasLocal.getVentasPendientes();
    _cancelacionesPendientes =
        await _syncService.ventasLocal.countCancelacionesPendientes();
    _ventasConError = await _syncService.ventasLocal.countVentasConError();
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
      // Las ventas propias ya sincronizadas llegan por la rama del servidor
      // (gana en el dedupe de abajo) pero conservan su fila local: hay que
      // superponerla o se perdería el estado de una anulación en curso y se
      // volvería a ofrecer el botón de anular.
      final localBySyncId = {for (final v in localList) v.syncId: v};
      _ventasUnificado = [
        ...serverList.map((v) => VentaUnificadaModel.fromServer(
              v,
              local: localBySyncId[v.syncId ?? v.id],
            )),
        ...localList
            .where((v) => !serverIds.contains(v.syncId))
            .map((v) => VentaUnificadaModel.fromLocal(v)),
        ...ventasHuerfanas
            .where((v) => !serverIds.contains(v.syncId))
            .map((v) => VentaUnificadaModel.fromLocal(v)),
      ];
      _ventasUnificado.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    } catch (e) {
      logDebug('❌ Error cargando ventas unificado: $e');
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

  /// Pide la anulación de una venta. Si nunca llegó al servidor se borra en el
  /// acto; si está en el servidor, la anulación se encola y solo se completa
  /// cuando el servidor la confirma.
  Future<AnulacionResultado> anularVenta(String syncId) async {
    final resultado = await _syncService.anularVenta(syncId);
    await refreshPendientes();
    notifyListeners();
    return resultado;
  }

  /// Vuelve a poner en cola una anulación que el servidor rechazó.
  Future<void> reintentarAnulacion(String syncId) async {
    await _syncService.reintentarAnulacion(syncId);
    await refreshPendientes();
    notifyListeners();
  }

  /// Desiste de una anulación rechazada: la venta vuelve a ser normal.
  Future<void> descartarAnulacion(String syncId) async {
    await _syncService.descartarAnulacion(syncId);
    await refreshPendientes();
    notifyListeners();
  }

  /// Lee de la base local el estado de sincronización de una venta concreta.
  /// Devuelve `null` si ya no existe (una anulación confirmada borra la fila).
  /// Lo usa la pantalla de cobro para seguir la venta que acaba de registrar.
  Future<VentaLocalModel?> getVentaLocal(String syncId) {
    return _syncService.ventasLocal.getVentaBySyncId(syncId);
  }

  /// Mueve una venta con conflicto de período al período actual y la resetea a pendiente.
  Future<void> updateVentaPeriodo(String syncId, String newPeriodoId) async {
    await _syncService.updateVentaPeriodo(syncId, newPeriodoId);
    await refreshPendientes();
    notifyListeners();
  }
}
