import 'package:cuadre_caja_app/providers/auth_provider.dart';
import 'package:cuadre_caja_app/core/network/api_client.dart';
import 'package:cuadre_caja_app/core/network/secure_storage_service.dart';
import 'package:cuadre_caja_app/data/datasources/local/cart_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/local/productos_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/auth_remote_datasource.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/categoria_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSecureStorageService extends Fake implements SecureStorageService {}

class FakeApiClient extends Fake implements ApiClient {}

/// Persistencia de carritos falsa: registra las llamadas a updateCart para poder
/// verificar que el orden de los items se guarda.
class FakeCartLocalDataSource extends Fake implements CartLocalDataSource {
  final List<CartModel> updateCalls = [];

  @override
  Future<void> updateCart(CartModel cart) async => updateCalls.add(cart);

  @override
  Future<void> saveCart(String tiendaId, CartModel cart) async {}

  @override
  Future<void> deleteCart(String cartId) async {}
}

/// Cache local de productos falsa: registra las llamadas a updateCodigos para
/// poder verificar que la asociación de código se persiste.
class FakeProductosLocalDataSource extends Fake
    implements ProductosLocalDataSource {
  final List<({String productoTiendaId, List<CodigoProductoModel> codigos})>
      updateCodigosCalls = [];

  @override
  Future<void> updateCodigos(
    String productoTiendaId,
    List<CodigoProductoModel> codigos,
  ) async {
    updateCodigosCalls.add((productoTiendaId: productoTiendaId, codigos: codigos));
  }
}

class FakeSyncService extends Fake implements SyncService {
  FakeSyncService({
    this.destinations = const [],
    this.productos = const [],
    this.categorias = const [],
    ProductosLocalDataSource? productosLocal,
  }) : _productosLocal = productosLocal ?? FakeProductosLocalDataSource();

  final List<TransferDestinationModel> destinations;
  final List<ProductoModel> productos;
  final List<CategoriaModel> categorias;
  final ProductosLocalDataSource _productosLocal;

  @override
  ProductosLocalDataSource get productosLocal => _productosLocal;

  // SyncProvider registra estos callbacks en su constructor; el fake solo
  // necesita aceptarlos para poder montarlo en widget tests.
  @override
  void Function(ConnectionStatus)? onConnectionChanged;

  @override
  void Function(String message)? onSyncEvent;

  @override
  Future<int> getPendingCount() async => 0;

  @override
  Future<List<TransferDestinationModel>> getTransferDestinationsLocal(
    String tiendaId,
  ) async =>
      destinations;

  @override
  Future<List<TransferDestinationModel>> loadTransferDestinations(
    String tiendaId,
  ) async =>
      destinations;

  @override
  Future<List<ProductoModel>> loadProductos(String tiendaId) async => productos;

  @override
  Future<List<CategoriaModel>> loadCategorias(String tiendaId) async =>
      categorias;
}

AuthProvider createTestAuthProvider() {
  final apiClient = FakeApiClient();
  return AuthProvider(
    authRemote: AuthRemoteDataSource(apiClient),
    storageService: FakeSecureStorageService(),
    apiClient: apiClient,
  );
}
