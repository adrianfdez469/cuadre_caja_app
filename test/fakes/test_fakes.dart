import 'package:cuadre_caja_app/providers/auth_provider.dart';
import 'package:cuadre_caja_app/core/network/api_client.dart';
import 'package:cuadre_caja_app/core/network/secure_storage_service.dart';
import 'package:cuadre_caja_app/data/datasources/local/cart_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/local/productos_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/local/ventas_local_datasource.dart';
import 'package:cuadre_caja_app/data/datasources/remote/auth_remote_datasource.dart';
import 'package:cuadre_caja_app/data/models/cart_model.dart';
import 'package:cuadre_caja_app/data/models/categoria_model.dart';
import 'package:cuadre_caja_app/data/models/periodo_model.dart';
import 'package:cuadre_caja_app/data/models/producto_model.dart';
import 'package:cuadre_caja_app/data/models/transfer_destination_model.dart';
import 'package:cuadre_caja_app/data/models/venta_model.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSecureStorageService extends Fake implements SecureStorageService {}

class FakeApiClient extends Fake implements ApiClient {}

/// Persistencia de carritos falsa: registra las llamadas a updateCart para poder
/// verificar que el orden de los items se guarda, y mantiene los carritos en
/// memoria para poder ejercitar `init()`, `createCart` y `deleteCart`.
class FakeCartLocalDataSource extends Fake implements CartLocalDataSource {
  final List<CartModel> updateCalls = [];
  final List<CartModel> stored = [];

  @override
  Future<List<CartModel>> getCarts(String tiendaId) async => List.of(stored);

  @override
  Future<void> updateCart(CartModel cart) async => updateCalls.add(cart);

  @override
  Future<void> saveCart(String tiendaId, CartModel cart) async =>
      stored.add(cart);

  @override
  Future<void> deleteCart(String cartId) async =>
      stored.removeWhere((c) => c.id == cartId);
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

/// Local de ventas falso. Por defecto ambas colas están vacías, que es lo que
/// `VentasProvider.refreshPendientes()` consulta tras `crearVenta`; los tests
/// que ejercitan el listado unificado pueblan [delPeriodo].
class FakeVentasLocalDataSource extends Fake implements VentasLocalDataSource {
  FakeVentasLocalDataSource({
    this.pendientes = const [],
    this.delPeriodo = const [],
    this.enErrorDeLaTienda = const [],
    this.cancelacionesPendientes = 0,
  });

  final List<VentaLocalModel> pendientes;
  final List<VentaLocalModel> delPeriodo;
  final List<VentaLocalModel> enErrorDeLaTienda;
  final int cancelacionesPendientes;

  @override
  Future<List<VentaLocalModel>> getVentasPendientes() async => pendientes;

  @override
  Future<int> countCancelacionesPendientes() async => cancelacionesPendientes;

  @override
  Future<List<VentaLocalModel>> getVentasByPeriodo(String periodoId) async =>
      delPeriodo;

  @override
  Future<List<VentaLocalModel>> getVentasErrorByTienda(String tiendaId) async =>
      enErrorDeLaTienda;
}

class FakeSyncService extends Fake implements SyncService {
  FakeSyncService({
    this.destinations = const [],
    this.productos = const [],
    this.categorias = const [],
    this.ventasServidor = const [],
    this.periodoAbierto,
    ProductosLocalDataSource? productosLocal,
    VentasLocalDataSource? ventasLocal,
  })  : _productosLocal = productosLocal ?? FakeProductosLocalDataSource(),
        _ventasLocal = ventasLocal ?? FakeVentasLocalDataSource();

  final List<TransferDestinationModel> destinations;
  final List<ProductoModel> productos;
  final List<CategoriaModel> categorias;

  /// Lo que devuelve el GET de ventas del período.
  final List<VentaServerModel> ventasServidor;

  /// Si se define, `loadPeriodoActual` lo devuelve — necesario para que
  /// `PaymentModal._processPayment()` encuentre un período activo en tests.
  final PeriodoModel? periodoAbierto;

  final ProductosLocalDataSource _productosLocal;
  final VentasLocalDataSource _ventasLocal;

  @override
  ProductosLocalDataSource get productosLocal => _productosLocal;

  @override
  VentasLocalDataSource get ventasLocal => _ventasLocal;

  @override
  Future<PeriodoModel> loadPeriodoActual(String tiendaId) async {
    final periodo = periodoAbierto;
    if (periodo == null) throw UnimplementedError();
    return periodo;
  }

  @override
  Future<VentaLocalModel> crearVenta(VentaLocalModel venta) async => venta;

  @override
  Future<List<VentaServerModel>> loadVentas(
    String tiendaId,
    String periodoId,
  ) async =>
      ventasServidor;

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
