import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/tasa_model.dart';

class TasasRemoteDataSource {
  final ApiClient apiClient;

  TasasRemoteDataSource(this.apiClient);

  /// GET /api/negocio/{negocioId}/tasas-cambio (mismo JWT, fuera de /api/app).
  Future<TasasVigentesResponse> getTasasCambio(String negocioId) async {
    final response = await apiClient.dio.get(
      ApiConstants.tasasCambioUrl(negocioId),
    );
    return TasasVigentesResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
