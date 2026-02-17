import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/venta_model.dart';

class VentaCreateResult {
  final VentaServerModel venta;
  final bool duplicado;

  VentaCreateResult({required this.venta, required this.duplicado});
}

class VentasRemoteDataSource {
  final ApiClient apiClient;

  VentasRemoteDataSource(this.apiClient);

  /// POST /venta/{tiendaId}/{periodoId}. [usuarioId] opcional para el body.
  Future<VentaCreateResult> crearVenta(
    VentaLocalModel ventaLocal, {
    String? usuarioId,
  }) async {
    final response = await apiClient.dio.post(
      ApiConstants.ventas(ventaLocal.tiendaId, ventaLocal.periodoId),
      data: ventaLocal.toApiJson(usuarioId: usuarioId),
    );

    final data = response.data as Map<String, dynamic>;
    return VentaCreateResult(
      venta: VentaServerModel.fromJson(data['venta'] as Map<String, dynamic>),
      duplicado: data['duplicado'] as bool? ?? false,
    );
  }

  /// GET /venta/{tiendaId}/{periodoId}
  Future<List<VentaServerModel>> getVentas(
    String tiendaId,
    String periodoId,
  ) async {
    final response = await apiClient.dio.get(
      ApiConstants.ventas(tiendaId, periodoId),
    );

    final data = response.data as Map<String, dynamic>;
    final ventasList = data['ventas'] as List<dynamic>? ?? [];

    return ventasList
        .map((v) => VentaServerModel.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  /// GET /venta/{tiendaId}/{periodoId}/{ventaId}
  Future<VentaServerModel> getVentaDetalle(
    String tiendaId,
    String periodoId,
    String ventaId,
  ) async {
    final response = await apiClient.dio.get(
      ApiConstants.ventaDetalle(tiendaId, periodoId, ventaId),
    );

    final data = response.data as Map<String, dynamic>;
    return VentaServerModel.fromJson(data['venta'] as Map<String, dynamic>);
  }

  /// DELETE /venta/{tiendaId}/{periodoId}/{ventaId}
  Future<void> cancelarVenta(
    String tiendaId,
    String periodoId,
    String ventaId,
  ) async {
    await apiClient.dio.delete(
      ApiConstants.ventaDetalle(tiendaId, periodoId, ventaId),
    );
  }
}
