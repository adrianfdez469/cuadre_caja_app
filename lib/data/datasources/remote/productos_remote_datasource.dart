import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/producto_model.dart';

class ProductosRemoteDataSource {
  final ApiClient apiClient;

  ProductosRemoteDataSource(this.apiClient);

  /// GET /productos/{tiendaId}
  Future<List<ProductoModel>> getProductos(String tiendaId) async {
    final response = await apiClient.dio.get(
      ApiConstants.productos(tiendaId),
    );

    final data = response.data as Map<String, dynamic>;
    final productosList = data['productos'] as List<dynamic>? ?? [];

    print('📦 Productos recibidos: ${productosList.length}');

    final productos = <ProductoModel>[];
    for (int i = 0; i < productosList.length; i++) {
      try {
        productos.add(
          ProductoModel.fromJson(productosList[i] as Map<String, dynamic>),
        );
      } catch (e) {
        print('⚠️ Error parseando producto #$i: $e');
      }
    }
    return productos;
  }

  /// POST /productos/{productoId}/agregar-codigo
  /// Asocia un código de barras a un producto existente.
  Future<CodigoProductoModel> asociarCodigo(
    String productoId,
    String codigo,
  ) async {
    final response = await apiClient.dio.post(
      ApiConstants.asociarCodigo(productoId),
      data: {'codigo': codigo},
    );
    final body = response.data as Map<String, dynamic>;
    return CodigoProductoModel.fromJson(
      body['codigo'] as Map<String, dynamic>,
    );
  }
}
