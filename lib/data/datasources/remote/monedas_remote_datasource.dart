import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/moneda_model.dart';

class MonedasRemoteDataSource {
  final ApiClient apiClient;

  MonedasRemoteDataSource(this.apiClient);

  /// GET /api/app/monedas/{negocioId}
  Future<MonedasNegocioResponse> getMonedas(String negocioId) async {
    final response = await apiClient.dio.get(
      ApiConstants.monedas(negocioId),
    );
    return MonedasNegocioResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
