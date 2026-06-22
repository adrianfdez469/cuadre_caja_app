import 'package:sqflite/sqflite.dart';
import '../../models/moneda_model.dart';
import 'database_helper.dart';

class MultimonedaLocalDataSource {
  final DatabaseHelper dbHelper;

  MultimonedaLocalDataSource(this.dbHelper);

  Future<void> saveConfig(MultimonedaConfig config) async {
    final db = await dbHelper.database;
    await db.insert(
      'multimoneda_cache',
      {
        'negocioId': config.negocioId,
        'configJson': config.toCacheString(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<MultimonedaConfig?> getConfig(String negocioId) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'multimoneda_cache',
      where: 'negocioId = ?',
      whereArgs: [negocioId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return MultimonedaConfig.fromCacheString(
      maps.first['configJson'] as String?,
    );
  }

  Future<void> clear(String negocioId) async {
    final db = await dbHelper.database;
    await db.delete(
      'multimoneda_cache',
      where: 'negocioId = ?',
      whereArgs: [negocioId],
    );
  }
}
