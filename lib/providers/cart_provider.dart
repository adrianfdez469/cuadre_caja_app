import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/utils/producto_pos_rules.dart';
import '../data/models/cart_model.dart';
import '../data/models/producto_model.dart';
import '../data/datasources/local/cart_local_datasource.dart';

class CartProvider extends ChangeNotifier {
  final CartLocalDataSource _cartLocal;
  final _uuid = const Uuid();

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
      await createCart('Carrito 1');
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

  /// Cambia al carrito en el índice dado
  void switchCart(int index) {
    if (index >= 0 && index < _carts.length) {
      _activeCartIndex = index;
      notifyListeners();
    }
  }

  /// Agrega producto al carrito activo.
  /// [allProductos] opcional: si se pasa, se valida máximo (normales y fracción).
  /// Retorna true si se agregó, false si la cantidad supera el máximo permitido.
  Future<bool> addToCart(
    ProductoModel producto, {
    double cantidad = 1,
    List<ProductoModel>? allProductos,
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
      );
      if (cantidad > maxPermitido) return false;
    }

    if (cantidadYaEnCarrito > 0) {
      final existingIdx = cart.items
          .indexWhere((i) => i.productoTiendaId == producto.id);
      cart.items[existingIdx].cantidad += cantidad;
    } else {
      cart.items.add(CartItemModel(
        productoTiendaId: producto.id,
        nombre: ProductoPosRules.nombreParaMostrar(producto),
        precio: producto.precio,
        monedaPrecioCode: producto.monedaPrecioCode,
        cantidad: cantidad,
      ));
    }

    await _saveActiveCart();
    notifyListeners();
    return true;
  }

  /// Actualiza cantidad de un item.
  /// [allProductos] opcional: si se pasa, se valida máximo (normales y fracción).
  /// Retorna true si se actualizó, false si la cantidad supera el máximo.
  Future<bool> updateItemCantidad(
    int itemIndex,
    double cantidad, {
    List<ProductoModel>? allProductos,
    ProductoModel? producto,
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

  /// Limpia el carrito activo
  Future<void> clearActiveCart() async {
    final cart = activeCart;
    if (cart == null) return;

    cart.items.clear();
    await _saveActiveCart();
    notifyListeners();
  }

  /// Elimina un carrito. Solo se puede eliminar si está vacío y queda al menos uno.
  Future<void> deleteCart(int index) async {
    if (_carts.length <= 1) return;
    if (index < 0 || index >= _carts.length) return;
    if (!_carts[index].isEmpty) return; // Solo eliminar carritos vacíos

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

  /// Llamar después de completar una venta: elimina el carrito vendido si no es
  /// "Carrito 1" y selecciona el primero de los restantes con ítems.
  Future<void> onPurchaseCompleted() async {
    if (_carts.isEmpty) return;

    final soldIndex = _activeCartIndex;
    if (soldIndex < 0 || soldIndex >= _carts.length) return;

    final soldCart = _carts[soldIndex];
    // Si no es el carrito principal y hay más de uno, eliminar el que se acaba de vaciar
    if (soldCart.nombre != 'Carrito 1' && _carts.length > 1) {
      _carts.removeAt(soldIndex);
      await _cartLocal.deleteCart(soldCart.id);
    }

    // Seleccionar el primer carrito que tenga ítems; si ninguno, el primero
    int newIndex = 0;
    for (int i = 0; i < _carts.length; i++) {
      if (!_carts[i].isEmpty) {
        newIndex = i;
        break;
      }
    }
    _activeCartIndex = newIndex.clamp(0, _carts.length - 1);
    notifyListeners();
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
}
