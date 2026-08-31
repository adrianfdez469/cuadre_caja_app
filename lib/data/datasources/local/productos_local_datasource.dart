import 'dart:convert';
import '../../models/producto_model.dart';
import 'package:cuadre_caja_app/core/utils/app_logger.dart';
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
    logDebug('💾 ${productos.length} productos cacheados para tienda $tiendaId');
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

  /// Actualiza las existencias de varios productos en una sola transacción.
  ///
  /// Se usa en el hot path de cada venta: solo escribe los productos que
  /// realmente cambiaron y lo hace de forma atómica (todo o nada), evitando
  /// stock parcialmente actualizado si algo falla a mitad.
  Future<void> updateExistencias(Map<String, double> existencias) async {
    if (existencias.isEmpty) return;
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final e in existencias.entries) {
        batch.update(
          'productos',
          {'existencia': e.value},
          where: 'id = ?',
          whereArgs: [e.key],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Persiste los códigos (barras/QR) de un producto en cache.
  ///
  /// Se usa tras asociar un código nuevo: sin esto la asociación solo vivía en
  /// memoria y se perdía al recargar la cache desde disco (p. ej. offline tras
  /// reiniciar la app), aunque el servidor ya la tuviera.
  Future<void> updateCodigos(
    String productoTiendaId,
    List<CodigoProductoModel> codigos,
  ) async {
    final db = await dbHelper.database;
    await db.update(
      'productos',
      {
        'codigosJson':
            codigos.isEmpty ? null : jsonEncode(codigos.map((c) => c.toJson()).toList()),
      },
      where: 'id = ?',
      whereArgs: [productoTiendaId],
    );
  }

  /// Incrementa existencia (al eliminar una venta y restaurar stock)
  Future<void> incrementExistencia(String productoTiendaId, double cantidad) async {
    final db = await dbHelper.database;
    await db.rawUpdate(
      'UPDATE productos SET existencia = existencia + ? WHERE id = ?',
      [cantidad, productoTiendaId],
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
