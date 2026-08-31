import '../../models/periodo_model.dart';
import 'package:cuadre_caja_app/core/utils/app_logger.dart';
import 'database_helper.dart';

class PeriodosLocalDataSource {
  final DatabaseHelper dbHelper;

  PeriodosLocalDataSource(this.dbHelper);

  /// Guarda/actualiza período en cache
  Future<void> cachePeriodo(PeriodoModel periodo) async {
    final db = await dbHelper.database;
    await db.insert(
      'periodo_cache',
      periodo.toMap(),
    );
    logDebug('💾 Período ${periodo.id} cacheado');
  }

  /// Obtiene período cacheado para una tienda
  Future<PeriodoModel?> getPeriodo(String tiendaId) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'periodo_cache',
      where: 'tiendaId = ?',
      whereArgs: [tiendaId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return PeriodoModel.fromMap(maps.first);
  }

  /// Borra el período cacheado de una tienda.
  ///
  /// Se usa cuando el servidor confirma que **no** hay período abierto. Sin
  /// esto la fila vieja sobrevivía marcada como abierta y, al leer del cache,
  /// el POS resucitaba un período que ya se cerró desde la web.
  Future<void> deletePeriodo(String tiendaId) async {
    final db = await dbHelper.database;
    await db.delete('periodo_cache', where: 'tiendaId = ?', whereArgs: [tiendaId]);
    logDebug('🗑️ Período cacheado de $tiendaId eliminado (el servidor dice que no hay abierto)');
  }

  /// Reemplaza el período cacheado para una tienda
  Future<void> replacePeriodo(String tiendaId, PeriodoModel periodo) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('periodo_cache', where: 'tiendaId = ?', whereArgs: [tiendaId]);
      await txn.insert('periodo_cache', periodo.toMap());
    });
  }
}
