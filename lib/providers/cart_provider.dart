import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
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

  /// Agrega producto al carrito activo
  Future<void> addToCart(ProductoModel producto, {double cantidad = 1}) async {
    final cart = activeCart;
    if (cart == null) return;

    final existingIdx = cart.items.indexWhere(
      (i) => i.productoTiendaId == producto.id,
    );

    if (existingIdx >= 0) {
      cart.items[existingIdx].cantidad += cantidad;
    } else {
      cart.items.add(CartItemModel(
        productoTiendaId: producto.id,
        nombre: producto.nombre,
        precio: producto.precio,
        cantidad: cantidad,
      ));
    }

    await _saveActiveCart();
    notifyListeners();
  }

  /// Actualiza cantidad de un item
  Future<void> updateItemCantidad(int itemIndex, double cantidad) async {
    final cart = activeCart;
    if (cart == null || itemIndex >= cart.items.length) return;

    if (cantidad <= 0) {
      cart.items.removeAt(itemIndex);
    } else {
      cart.items[itemIndex].cantidad = cantidad;
    }

    await _saveActiveCart();
    notifyListeners();
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

  /// Elimina un carrito
  Future<void> deleteCart(int index) async {
    if (_carts.length <= 1) return; // No eliminar el último

    final cart = _carts[index];
    _carts.removeAt(index);
    await _cartLocal.deleteCart(cart.id);

    if (_activeCartIndex >= _carts.length) {
      _activeCartIndex = _carts.length - 1;
    }
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
