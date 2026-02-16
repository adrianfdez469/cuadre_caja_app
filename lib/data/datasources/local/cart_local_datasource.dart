import '../../models/cart_model.dart';
import 'database_helper.dart';

class CartLocalDataSource {
  final DatabaseHelper dbHelper;

  CartLocalDataSource(this.dbHelper);

  /// Obtiene todos los carritos de una tienda
  Future<List<CartModel>> getCarts(String tiendaId) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'carritos',
      where: 'tiendaId = ?',
      whereArgs: [tiendaId],
    );
    return maps.map((m) => CartModel.fromMap(m)).toList();
  }

  /// Guarda o actualiza un carrito
  Future<void> saveCart(String tiendaId, CartModel cart) async {
    final db = await dbHelper.database;
    final map = cart.toMap();
    map['tiendaId'] = tiendaId;

    await db.insert(
      'carritos',
      map,
    );
  }

  /// Actualiza un carrito existente
  Future<void> updateCart(CartModel cart) async {
    final db = await dbHelper.database;
    await db.update(
      'carritos',
      cart.toMap(),
      where: 'id = ?',
      whereArgs: [cart.id],
    );
  }

  /// Elimina un carrito
  Future<void> deleteCart(String cartId) async {
    final db = await dbHelper.database;
    await db.delete('carritos', where: 'id = ?', whereArgs: [cartId]);
  }

  /// Elimina todos los carritos de una tienda
  Future<void> clearCarts(String tiendaId) async {
    final db = await dbHelper.database;
    await db.delete('carritos', where: 'tiendaId = ?', whereArgs: [tiendaId]);
  }
}
