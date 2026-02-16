import '../../models/transfer_destination_model.dart';
import 'database_helper.dart';

class TransferDestinationsLocalDataSource {
  final DatabaseHelper dbHelper;

  TransferDestinationsLocalDataSource(this.dbHelper);

  Future<void> cacheDestinos(
    String tiendaId,
    List<TransferDestinationModel> destinos,
  ) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('transfer_destinations',
          where: 'tiendaId = ?', whereArgs: [tiendaId]);
      for (final d in destinos) {
        final map = d.toMap();
        map['tiendaId'] = tiendaId;
        await txn.insert('transfer_destinations', map);
      }
    });
  }

  Future<List<TransferDestinationModel>> getDestinos(String tiendaId) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'transfer_destinations',
      where: 'tiendaId = ?',
      whereArgs: [tiendaId],
    );
    return maps.map((m) => TransferDestinationModel.fromMap(m)).toList();
  }
}
