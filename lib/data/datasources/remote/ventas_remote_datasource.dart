import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/errors/exceptions.dart';
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

  /// POST /venta/{tiendaId}/{periodoId}. En 4xx/5xx lanza [SyncVentaException].
  Future<VentaCreateResult> crearVenta(VentaLocalModel ventaLocal) async {
    try {
      final response = await apiClient.dio.post(
        ApiConstants.ventas(ventaLocal.tiendaId, ventaLocal.periodoId),
        data: ventaLocal.toApiJson(),
      );

      final data = response.data as Map<String, dynamic>;
      return VentaCreateResult(
        venta: VentaServerModel.fromJson(data['venta'] as Map<String, dynamic>),
        duplicado: data['duplicado'] as bool? ?? false,
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      String message;
      if (body is Map<String, dynamic> && body['error'] != null) {
        message = body['error'] as String;
      } else {
        message = e.message ?? 'Error de conexión al sincronizar la venta';
      }
      throw SyncVentaException(message);
    }
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
