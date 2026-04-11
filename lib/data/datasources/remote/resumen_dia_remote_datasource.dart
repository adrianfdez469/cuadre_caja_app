import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/resumen_dia_model.dart';

class ResumenDiaRemoteDataSource {
  final ApiClient apiClient;

  ResumenDiaRemoteDataSource(this.apiClient);

  Future<ResumenDiaModel> getResumenDia({
    required String tiendaId,
    required String cierreId,
    bool soloConMovimientos = true,
  }) async {
    final response = await apiClient.dio.get(
      ApiConstants.resumenDia(tiendaId),
      queryParameters: {
        'cierreId': cierreId,
        'soloConMovimientos': soloConMovimientos,
      },
    );
    return ResumenDiaModel.fromJson(response.data as Map<String, dynamic>);
  }
}
