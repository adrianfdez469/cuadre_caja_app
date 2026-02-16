import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/periodo_model.dart';

class PeriodosRemoteDataSource {
  final ApiClient apiClient;

  PeriodosRemoteDataSource(this.apiClient);

  /// GET /periodo/{tiendaId}/actual
  Future<PeriodoModel?> getPeriodoActual(String tiendaId) async {
    final response = await apiClient.dio.get(
      ApiConstants.periodoActual(tiendaId),
    );

    final data = response.data as Map<String, dynamic>;
    if (data['periodo'] == null) return null;

    return PeriodoModel.fromJson(data);
  }

  /// POST /periodo/{tiendaId}/abrir
  Future<PeriodoModel> abrirPeriodo(String tiendaId) async {
    final response = await apiClient.dio.post(
      ApiConstants.periodoAbrir(tiendaId),
    );

    final data = response.data as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Error abriendo período');
    }

    return PeriodoModel.fromJson(data);
  }
}
