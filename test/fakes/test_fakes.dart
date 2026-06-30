import 'package:cuadre_caja_app/providers/auth_provider.dart';
import 'package:cuadre_caja_app/core/network/api_client.dart';
import 'package:cuadre_caja_app/core/network/secure_storage_service.dart';
import 'package:cuadre_caja_app/data/datasources/local/cart_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/auth_remote_datasource.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSecureStorageService extends Fake implements SecureStorageService {}

class FakeApiClient extends Fake implements ApiClient {}

class FakeCartLocalDataSource extends Fake implements CartLocalDataSource {}

class FakeSyncService extends Fake implements SyncService {
  FakeSyncService({this.destinations = const []});

  final List<TransferDestinationModel> destinations;

  @override
  Future<List<TransferDestinationModel>> loadTransferDestinations(
    String tiendaId,
  ) async =>
      destinations;
}

AuthProvider createTestAuthProvider() {
  final apiClient = FakeApiClient();
  return AuthProvider(
    authRemote: AuthRemoteDataSource(apiClient),
    storageService: FakeSecureStorageService(),
    apiClient: apiClient,
  );
}
