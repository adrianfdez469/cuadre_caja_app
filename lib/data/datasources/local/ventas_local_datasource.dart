import '../../models/venta_model.dart';
import 'database_helper.dart';

class VentasLocalDataSource {
  final DatabaseHelper dbHelper;

  VentasLocalDataSource(this.dbHelper);

  /// Guarda una venta pendiente localmente
  Future<void> saveVentaPendiente(VentaLocalModel venta) async {
    final db = await dbHelper.database;
    await db.insert(
      'ventas_pendientes',
      venta.toMap(),
    );
    print('💾 Venta ${venta.syncId} guardada localmente');
  }

  /// Obtiene todas las ventas pendientes de sincronización
  Future<List<VentaLocalModel>> getVentasPendientes() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'ventas_pendientes',
      where: 'syncState IN (?, ?)',
      whereArgs: [SyncState.pending.name, SyncState.error.name],
      orderBy: 'createdAt ASC',
    );
    return maps.map((m) => VentaLocalModel.fromMap(m)).toList();
  }

  /// Obtiene todas las ventas locales (cualquier estado)
  Future<List<VentaLocalModel>> getAllVentas() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'ventas_pendientes',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => VentaLocalModel.fromMap(m)).toList();
  }

  /// Actualiza el estado de sincronización de una venta
  Future<void> updateSyncState(
    String syncId, {
    required SyncState syncState,
    int? syncAttempts,
    String? errorMessage,
    String? serverId,
  }) async {
    final db = await dbHelper.database;
    final updates = <String, dynamic>{'syncState': syncState.name};
    if (syncAttempts != null) updates['syncAttempts'] = syncAttempts;
    if (errorMessage != null) updates['errorMessage'] = errorMessage;
    if (serverId != null) updates['serverId'] = serverId;

    await db.update(
      'ventas_pendientes',
      updates,
      where: 'syncId = ?',
      whereArgs: [syncId],
    );
  }

  /// Elimina ventas ya sincronizadas (limpieza)
  Future<void> clearSyncedVentas() async {
    final db = await dbHelper.database;
    await db.delete(
      'ventas_pendientes',
      where: 'syncState = ?',
      whereArgs: [SyncState.synced.name],
    );
  }

  /// Cuenta ventas pendientes
  Future<int> countPendientes() async {
    final db = await dbHelper.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM ventas_pendientes WHERE syncState IN ('pending', 'error')",
    );
    return result.first['count'] as int;
  }

  /// Verifica si hay ventas pendientes
  Future<bool> hasPendientes() async {
    return (await countPendientes()) > 0;
  }
}
