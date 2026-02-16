import '../../models/periodo_model.dart';
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
    print('💾 Período ${periodo.id} cacheado');
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

  /// Reemplaza el período cacheado para una tienda
  Future<void> replacePeriodo(String tiendaId, PeriodoModel periodo) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('periodo_cache', where: 'tiendaId = ?', whereArgs: [tiendaId]);
      await txn.insert('periodo_cache', periodo.toMap());
    });
  }
}
