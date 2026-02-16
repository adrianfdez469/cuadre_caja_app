import '../../models/producto_model.dart';
import '../../models/categoria_model.dart';
import 'database_helper.dart';

class ProductosLocalDataSource {
  final DatabaseHelper dbHelper;

  ProductosLocalDataSource(this.dbHelper);

  /// Guarda productos en cache (reemplaza todos para la tienda)
  Future<void> cacheProductos(String tiendaId, List<ProductoModel> productos) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('productos', where: 'tiendaId = ?', whereArgs: [tiendaId]);
      for (final p in productos) {
        final map = p.toMap();
        map['tiendaId'] = tiendaId;
        await txn.insert('productos', map);
      }
    });
    print('💾 ${productos.length} productos cacheados para tienda $tiendaId');
  }

  /// Obtiene todos los productos cacheados para una tienda
  Future<List<ProductoModel>> getProductos(String tiendaId) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'productos',
      where: 'tiendaId = ?',
      whereArgs: [tiendaId],
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => ProductoModel.fromMap(m)).toList();
  }

  /// Obtiene productos filtrados por categoría
  Future<List<ProductoModel>> getProductosByCategoria(
    String tiendaId,
    String categoriaId,
  ) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'productos',
      where: 'tiendaId = ? AND categoriaId = ?',
      whereArgs: [tiendaId, categoriaId],
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => ProductoModel.fromMap(m)).toList();
  }

  /// Busca productos por nombre
  Future<List<ProductoModel>> searchProductos(String tiendaId, String query) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'productos',
      where: 'tiendaId = ? AND nombre LIKE ?',
      whereArgs: [tiendaId, '%$query%'],
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => ProductoModel.fromMap(m)).toList();
  }

  /// Obtiene las categorías únicas de los productos cacheados
  Future<List<CategoriaModel>> getCategorias(String tiendaId) async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT DISTINCT categoriaId as id, categoriaNombre as nombre, categoriaColor as color
      FROM productos
      WHERE tiendaId = ? AND categoriaId IS NOT NULL
      ORDER BY categoriaNombre ASC
    ''', [tiendaId]);
    return maps.map((m) => CategoriaModel.fromMap(m)).toList();
  }

  /// Actualiza existencia de un producto (después de una venta local)
  Future<void> updateExistencia(String productoTiendaId, double nuevaExistencia) async {
    final db = await dbHelper.database;
    await db.update(
      'productos',
      {'existencia': nuevaExistencia},
      where: 'id = ?',
      whereArgs: [productoTiendaId],
    );
  }

  /// Verifica si hay productos cacheados
  Future<bool> hasCache(String tiendaId) async {
    final db = await dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM productos WHERE tiendaId = ?',
      [tiendaId],
    );
    return (result.first['count'] as int) > 0;
  }
}
