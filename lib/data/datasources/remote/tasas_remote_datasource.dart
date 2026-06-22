import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/tasa_model.dart';

class TasasRemoteDataSource {
  final ApiClient apiClient;

  TasasRemoteDataSource(this.apiClient);

  /// GET /api/app/tasas-cambio/{negocioId}
  Future<TasasVigentesResponse> getTasasCambio(String negocioId) async {
    final response = await apiClient.dio.get(
      ApiConstants.tasasCambio(negocioId),
    );
    return TasasVigentesResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
