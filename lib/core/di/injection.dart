import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../network/api_client.dart';
import '../network/secure_storage_service.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/local/productos_local_datasource.dart';
import '../../data/datasources/local/ventas_local_datasource.dart';
import '../../data/datasources/local/periodos_local_datasource.dart';
import '../../data/datasources/local/cart_local_datasource.dart';
import '../../data/datasources/local/transfer_destinations_local_datasource.dart';
import '../../data/datasources/local/multimoneda_local_datasource.dart';
import '../../data/datasources/remote/auth_remote_datasource.dart';
import '../../data/datasources/remote/productos_remote_datasource.dart';
import '../../data/datasources/remote/periodos_remote_datasource.dart';
import '../../data/datasources/remote/ventas_remote_datasource.dart';
import '../../data/datasources/remote/transfer_destinations_remote_datasource.dart';
import '../../data/datasources/remote/monedas_remote_datasource.dart';
import '../../data/datasources/remote/tasas_remote_datasource.dart';
import '../../services/sync_service.dart';

class Injection {
  // Core
  late final SecureStorageService secureStorageService;
  late final ApiClient apiClient;
  late final Connectivity connectivity;
  late final DatabaseHelper databaseHelper;

  // Remote
  late final AuthRemoteDataSource authRemoteDataSource;
  late final ProductosRemoteDataSource productosRemoteDataSource;
  late final PeriodosRemoteDataSource periodosRemoteDataSource;
  late final VentasRemoteDataSource ventasRemoteDataSource;
  late final TransferDestinationsRemoteDataSource transferRemoteDataSource;
  late final MonedasRemoteDataSource monedasRemoteDataSource;
  late final TasasRemoteDataSource tasasRemoteDataSource;

  // Local
  late final ProductosLocalDataSource productosLocalDataSource;
  late final VentasLocalDataSource ventasLocalDataSource;
  late final PeriodosLocalDataSource periodosLocalDataSource;
  late final CartLocalDataSource cartLocalDataSource;
  late final TransferDestinationsLocalDataSource transferLocalDataSource;
  late final MultimonedaLocalDataSource multimonedaLocalDataSource;

  // Services
  late final SyncService syncService;

  Future<void> init() async {
    print('🚀 Inicializando dependencias...');

    // Core
    const secureStorage = FlutterSecureStorage();
    secureStorageService = SecureStorageService(secureStorage);
    await secureStorageService.init();

    apiClient = ApiClient(secureStorageService);
    connectivity = Connectivity();
    databaseHelper = DatabaseHelper();

    // Inicializar DB
    await databaseHelper.database;

    // Remote datasources
    authRemoteDataSource = AuthRemoteDataSource(apiClient);
    productosRemoteDataSource = ProductosRemoteDataSource(apiClient);
    periodosRemoteDataSource = PeriodosRemoteDataSource(apiClient);
    ventasRemoteDataSource = VentasRemoteDataSource(apiClient);
    transferRemoteDataSource = TransferDestinationsRemoteDataSource(apiClient);
    monedasRemoteDataSource = MonedasRemoteDataSource(apiClient);
    tasasRemoteDataSource = TasasRemoteDataSource(apiClient);

    // Local datasources
    productosLocalDataSource = ProductosLocalDataSource(databaseHelper);
    ventasLocalDataSource = VentasLocalDataSource(databaseHelper);
    periodosLocalDataSource = PeriodosLocalDataSource(databaseHelper);
    cartLocalDataSource = CartLocalDataSource(databaseHelper);
    transferLocalDataSource = TransferDestinationsLocalDataSource(databaseHelper);
    multimonedaLocalDataSource = MultimonedaLocalDataSource(databaseHelper);

    // Sync service
    syncService = SyncService(
      apiClient: apiClient,
      storageService: secureStorageService,
      connectivity: connectivity,
      productosRemote: productosRemoteDataSource,
      periodosRemote: periodosRemoteDataSource,
      ventasRemote: ventasRemoteDataSource,
      transferRemote: transferRemoteDataSource,
      monedasRemote: monedasRemoteDataSource,
      tasasRemote: tasasRemoteDataSource,
      productosLocal: productosLocalDataSource,
      periodosLocal: periodosLocalDataSource,
      ventasLocal: ventasLocalDataSource,
      transferLocal: transferLocalDataSource,
      multimonedaLocal: multimonedaLocalDataSource,
    );

    print('✅ Dependencias inicializadas');
  }
}

final injection = Injection();
