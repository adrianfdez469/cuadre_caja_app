import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../models/transfer_destination_model.dart';

class TransferDestinationsRemoteDataSource {
  final ApiClient apiClient;

  TransferDestinationsRemoteDataSource(this.apiClient);

  /// GET /transfer-destinations/{tiendaId}
  Future<List<TransferDestinationModel>> getDestinos(String tiendaId) async {
    final response = await apiClient.dio.get(
      ApiConstants.transferDestinations(tiendaId),
    );

    final data = response.data as Map<String, dynamic>;
    final destinosList = data['destinos'] as List<dynamic>? ?? [];

    return destinosList
        .map((d) =>
            TransferDestinationModel.fromJson(d as Map<String, dynamic>))
        .toList();
  }
}
