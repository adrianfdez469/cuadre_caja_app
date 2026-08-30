import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/producto_pos_rules.dart';
import '../data/models/cart_model.dart';
import '../data/models/producto_model.dart';
import '../data/datasources/local/cart_local_datasource.dart';

class CartProvider extends ChangeNotifier {
  final CartLocalDataSource _cartLocal;
  final _uuid = const Uuid();

  /// Reconoce los nombres autogenerados para derivar el siguiente consecutivo.
  static final _nombreCuenta = RegExp(r'^Cuenta #(\d+)$');

  List<CartModel> _carts = [];
  int _activeCartIndex = 0;
  String? _tiendaId;

  CartProvider(this._cartLocal);

  List<CartModel> get carts => _carts;
  CartModel? get activeCart =>
      _carts.isNotEmpty ? _carts[_activeCartIndex] : null;
  int get activeCartIndex => _activeCartIndex;
  int get cartCount => _carts.length;
  double get activeTotal => activeCart?.total ?? 0;
  int get activeItemCount => activeCart?.itemCount ?? 0;

  /// Cantidad total de ítems en todos los carritos (para badge en pantalla principal).
  int get totalItemCountAcrossCarts =>
      _carts.fold(0, (sum, cart) => sum + cart.itemCount);

  /// Inicializa carritos para una tienda
  Future<void> init(String tiendaId) async {
    _tiendaId = tiendaId;
    _carts = await _cartLocal.getCarts(tiendaId);

    if (_carts.isEmpty) {
      await createCart(AppConstants.defaultCartName);
    }

    _activeCartIndex = 0;
    notifyListeners();
  }

  /// Crea un nuevo carrito
  Future<void> createCart(String nombre) async {
    if (_tiendaId == null) return;

    final cart = CartModel(id: _uuid.v4(), nombre: nombre);
    _carts.add(cart);
    _activeCartIndex = _carts.length - 1;
    await _cartLocal.saveCart(_tiendaId!, cart);
    notifyListeners();
  }

  /// Siguiente nombre libre: el mayor "Cuenta #N" existente + 1. Se calcula
  /// sobre los nombres y no sobre [cartCount], porque al cerrar una cuenta del
  /// medio el tamaño de la lista deja de coincidir con el último número usado.
  /// Las cuentas renombradas a mano ("Mesa 4") no participan del consecutivo.
  String nextCartName() {
    var max = 0;
    for (final cart in _carts) {
      final n = int.tryParse(_nombreCuenta.firstMatch(cart.nombre)?.group(1) ?? '');
      if (n != null && n > max) max = n;
    }
    return 'Cuenta #${max + 1}';
  }

  /// Crea la siguiente cuenta y la deja activa (sin preguntar el nombre).
  Future<void> createNextCart() => createCart(nextCartName());

  /// Cambia al carrito en el índice dado
  void switchCart(int index) {
    if (index >= 0 && index < _carts.length) {
      _activeCartIndex = index;
      notifyListeners();
    }
  }

  /// Salta a la primera cuenta que tenga productos; si ninguna tiene, a la
  /// principal. Se usa al vaciar una cuenta y al cerrar una venta, para no
  /// dejar al cajero parado en una cuenta vacía habiendo otra con venta en
  /// curso.
  ///
  /// **No** se llama desde [clearActiveCart]: `payment_modal` vacía y después
  /// llama a [onPurchaseCompleted], que necesita que el índice activo siga
  /// apuntando a la cuenta que se acaba de vender.
  void selectFirstNonEmptyCart() {
    if (_carts.isEmpty) return;

    var newIndex = 0;
    for (var i = 0; i < _carts.length; i++) {
      if (!_carts[i].isEmpty) {
        newIndex = i;
        break;
      }
    }
    _activeCartIndex = newIndex.clamp(0, _carts.length - 1);
    notifyListeners();
  }

  /// Agrega producto al carrito activo.
  /// [allProductos] opcional: si se pasa, se valida máximo (normales y fracción).
  /// [permitirSinStock]: si es true no se valida el stock local (sin conexión, o
  /// con el ajuste "Vender sin existencias" activo). Ver `VentaSinStockPolicy`.
  /// [moverAlInicio]: coloca la línea en la posición 0 (la inserta ahí si es nueva
  /// o la mueve si ya existía). Lo usan los flujos de escaneo para que lo recién
  /// leído quede siempre visible arriba. Es el ÚNICO punto del provider que
  /// reordena: editar cantidades o eliminar nunca mueve una línea de sitio.
  /// Retorna true si se agregó, false si la cantidad supera el máximo permitido.
  Future<bool> addToCart(
    ProductoModel producto, {
    double cantidad = 1,
    List<ProductoModel>? allProductos,
    bool permitirSinStock = false,
    bool moverAlInicio = false,
  }) async {
    final cart = activeCart;
    if (cart == null) return false;

    final cantidadYaEnCarrito = cart.items
        .where((i) => i.productoTiendaId == producto.id)
        .fold<double>(0, (s, i) => s + i.cantidad);

    if (allProductos != null) {
      final maxPermitido = ProductoPosRules.getMaxQuantity(
        producto,
        allProductos,
        cantidadEnCarrito: cantidadYaEnCarrito,
        permitirSinStock: permitirSinStock,
      );
      // Se valida antes de mutar: un escaneo rechazado no debe reordenar nada.
      if (cantidad > maxPermitido) return false;
    }

    final existingIdx =
        cart.items.indexWhere((i) => i.productoTiendaId == producto.id);

    if (existingIdx >= 0) {
      final item = cart.items[existingIdx];
      item.cantidad += cantidad;
      if (moverAlInicio && existingIdx > 0) {
        cart.items.removeAt(existingIdx);
        cart.items.insert(0, item);
      }
    } else {
      final nuevo = CartItemModel(
        productoTiendaId: producto.id,
        nombre: ProductoPosRules.nombreParaMostrar(producto),
        precio: producto.precio,
        monedaPrecioCode: producto.monedaPrecioCode,
        cantidad: cantidad,
      );
      if (moverAlInicio) {
        cart.items.insert(0, nuevo);
      } else {
        cart.items.add(nuevo);
      }
    }

    await _saveActiveCart();
    notifyListeners();
    return true;
  }

  /// Actualiza cantidad de un item.
  /// [allProductos] opcional: si se pasa, se valida máximo (normales y fracción).
  /// [permitirSinStock]: si es true no se valida el stock local. Ver `VentaSinStockPolicy`.
  /// Retorna true si se actualizó, false si la cantidad supera el máximo.
  Future<bool> updateItemCantidad(
    int itemIndex,
    double cantidad, {
    List<ProductoModel>? allProductos,
    ProductoModel? producto,
    bool permitirSinStock = false,
  }) async {
    final cart = activeCart;
    if (cart == null || itemIndex >= cart.items.length) return false;

    if (cantidad <= 0) {
      cart.items.removeAt(itemIndex);
      await _saveActiveCart();
      notifyListeners();
      return true;
    }

    if (allProductos != null && producto != null) {
      final cantidadOtrosItems = cart.items
          .where((i) => i.productoTiendaId == producto.id && i != cart.items[itemIndex])
          .fold<double>(0, (s, i) => s + i.cantidad);
      final maxPermitido = ProductoPosRules.getMaxQuantity(
        producto,
        allProductos,
        cantidadEnCarrito: cantidadOtrosItems,
        permitirSinStock: permitirSinStock,
      );
      if (cantidad > maxPermitido) return false;
    }

    cart.items[itemIndex].cantidad = cantidad;
    await _saveActiveCart();
    notifyListeners();
    return true;
  }

  /// Elimina un item del carrito
  Future<void> removeItem(int itemIndex) async {
    final cart = activeCart;
    if (cart == null || itemIndex >= cart.items.length) return;

    cart.items.removeAt(itemIndex);
    await _saveActiveCart();
    notifyListeners();
  }

  /// Índice de la línea de un producto en el carrito activo (-1 si no está).
  int indexOfProducto(String productoTiendaId) =>
      activeCart?.items
          .indexWhere((i) => i.productoTiendaId == productoTiendaId) ??
      -1;

  /// Igual que [updateItemCantidad] pero resolviendo el índice en el momento de
  /// la llamada. Con el carrito visible en el escáner, un frame de cámara puede
  /// reordenar la lista entre el build y el tap: mutar por índice incrementaría
  /// el producto equivocado. No reordena.
  Future<bool> updateItemCantidadById(
    String productoTiendaId,
    double cantidad, {
    List<ProductoModel>? allProductos,
    ProductoModel? producto,
    bool permitirSinStock = false,
  }) async {
    final idx = indexOfProducto(productoTiendaId);
    if (idx < 0) return false;
    return updateItemCantidad(
      idx,
      cantidad,
      allProductos: allProductos,
      producto: producto,
      permitirSinStock: permitirSinStock,
    );
  }

  /// Igual que [removeItem] pero resolviendo el índice en el momento de la
  /// llamada. No altera el orden relativo del resto.
  Future<void> removeItemById(String productoTiendaId) async {
    final idx = indexOfProducto(productoTiendaId);
    if (idx < 0) return;
    await removeItem(idx);
  }

  /// Limpia el carrito activo
  Future<void> clearActiveCart() async {
    final cart = activeCart;
    if (cart == null) return;

    cart.items.clear();
    await _saveActiveCart();
    notifyListeners();
  }

  /// Cierra una cuenta, tenga o no productos (la UI confirma antes).
  /// La cuenta principal (índice 0) no se cierra nunca: es la que sobrevive a
  /// cada venta y la que queda cuando no hay ninguna otra.
  Future<void> deleteCart(int index) async {
    if (_carts.length <= 1) return;
    if (index <= 0 || index >= _carts.length) return;

    final cart = _carts[index];
    _carts.removeAt(index);
    await _cartLocal.deleteCart(cart.id);

    if (_activeCartIndex >= _carts.length) {
      _activeCartIndex = _carts.length - 1;
    } else if (index < _activeCartIndex) {
      _activeCartIndex--;
    }
    notifyListeners();
  }

  /// Llamar después de completar una venta: cierra la cuenta vendida si no es
  /// la principal y selecciona la primera de las restantes con ítems.
  Future<void> onPurchaseCompleted() async {
    if (_carts.isEmpty) return;

    final soldIndex = _activeCartIndex;
    if (soldIndex < 0 || soldIndex >= _carts.length) return;

    final soldCart = _carts[soldIndex];
    // Se compara por índice, no por nombre: la cuenta principal es la 0 y el
    // usuario puede renombrarla.
    if (soldIndex != 0 && _carts.length > 1) {
      _carts.removeAt(soldIndex);
      await _cartLocal.deleteCart(soldCart.id);
    }

    selectFirstNonEmptyCart();
  }

  /// Renombra un carrito
  Future<void> renameCart(int index, String nombre) async {
    if (index >= _carts.length) return;

    _carts[index].nombre = nombre;
    await _cartLocal.updateCart(_carts[index]);
    notifyListeners();
  }

  Future<void> _saveActiveCart() async {
    final cart = activeCart;
    if (cart == null) return;
    await _cartLocal.updateCart(cart);
  }

  @visibleForTesting
  void debugSetActiveCart(CartModel cart) {
    if (_carts.isEmpty) {
      _carts = [cart];
    } else {
      _carts[_activeCartIndex] = cart;
    }
    notifyListeners();
  }
}
