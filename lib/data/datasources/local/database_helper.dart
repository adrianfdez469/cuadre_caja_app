import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = 'cuadre_caja.db';
  static const _databaseVersion = 6;

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE productos (
        id TEXT PRIMARY KEY,
        productoId TEXT NOT NULL,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        precio REAL NOT NULL DEFAULT 0,
        costo REAL NOT NULL DEFAULT 0,
        existencia REAL NOT NULL DEFAULT 0,
        permiteDecimal INTEGER NOT NULL DEFAULT 0,
        categoriaId TEXT,
        categoriaNombre TEXT,
        categoriaColor TEXT,
        proveedor TEXT,
        esFraccion INTEGER NOT NULL DEFAULT 0,
        fraccionDeId TEXT,
        fraccionDeNombre TEXT,
        unidadesPorFraccion INTEGER,
        monedaPrecioCode TEXT,
        tiendaId TEXT NOT NULL,
        codigosJson TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ventas_pendientes (
        syncId TEXT PRIMARY KEY,
        tiendaId TEXT NOT NULL,
        periodoId TEXT NOT NULL,
        productosJson TEXT NOT NULL,
        total REAL NOT NULL,
        totalcash REAL NOT NULL,
        totaltransfer REAL NOT NULL DEFAULT 0,
        transferDestinationId TEXT,
        wasOffline INTEGER NOT NULL DEFAULT 0,
        syncAttempts INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        discountCodes TEXT,
        monedaCobro TEXT NOT NULL DEFAULT 'CUP',
        pagosDetalleJson TEXT,
        vueltoDetalleJson TEXT,
        tasaSnapshotJson TEXT,
        syncState TEXT NOT NULL DEFAULT 'pending',
        errorMessage TEXT,
        serverId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ventas_servidor_cache (
        id TEXT PRIMARY KEY,
        tiendaId TEXT NOT NULL,
        periodoId TEXT NOT NULL,
        ventaJson TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE periodo_cache (
        id TEXT PRIMARY KEY,
        tiendaId TEXT NOT NULL,
        fechaInicio TEXT NOT NULL,
        fechaFin TEXT,
        estaAbierto INTEGER NOT NULL DEFAULT 0,
        totalVentas REAL NOT NULL DEFAULT 0,
        totalGanancia REAL NOT NULL DEFAULT 0,
        totalInversion REAL NOT NULL DEFAULT 0,
        totalTransferencia REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE transfer_destinations (
        id TEXT PRIMARY KEY,
        tiendaId TEXT NOT NULL,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        isDefault INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE carritos (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        itemsJson TEXT NOT NULL DEFAULT '[]',
        tiendaId TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE multimoneda_cache (
        negocioId TEXT PRIMARY KEY,
        configJson TEXT NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');

    // Índices para queries frecuentes
    await db.execute(
        'CREATE INDEX idx_productos_tienda ON productos(tiendaId)');
    await db.execute(
        'CREATE INDEX idx_productos_categoria ON productos(categoriaId)');
    await db.execute(
        'CREATE INDEX idx_ventas_sync ON ventas_pendientes(syncState)');
    await db.execute(
        'CREATE INDEX idx_carritos_tienda ON carritos(tiendaId)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE productos ADD COLUMN codigosJson TEXT');
      } catch (_) {}
    }
    if (oldVersion <= 1) {
      await db.execute('DROP TABLE IF EXISTS productos');
      await db.execute('DROP TABLE IF EXISTS ventas_pendientes');
      await db.execute('DROP TABLE IF EXISTS periodo_cache');
      await db.execute('DROP TABLE IF EXISTS transfer_destinations');
      await db.execute('DROP TABLE IF EXISTS carritos');
      await _onCreate(db, newVersion);
    }
    if (oldVersion < 4) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ventas_servidor_cache (
            id TEXT PRIMARY KEY,
            tiendaId TEXT NOT NULL,
            periodoId TEXT NOT NULL,
            ventaJson TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      for (final sql in [
        "ALTER TABLE ventas_pendientes ADD COLUMN monedaCobro TEXT NOT NULL DEFAULT 'CUP'",
        'ALTER TABLE ventas_pendientes ADD COLUMN pagosDetalleJson TEXT',
        'ALTER TABLE ventas_pendientes ADD COLUMN vueltoDetalleJson TEXT',
        'ALTER TABLE ventas_pendientes ADD COLUMN tasaSnapshotJson TEXT',
      ]) {
        try {
          await db.execute(sql);
        } catch (_) {}
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute(
          'ALTER TABLE productos ADD COLUMN monedaPrecioCode TEXT',
        );
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS multimoneda_cache (
            negocioId TEXT PRIMARY KEY,
            configJson TEXT NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
      } catch (_) {}
    }
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('productos');
    await db.delete('periodo_cache');
    await db.delete('transfer_destinations');
    await db.delete('carritos');
    await db.delete('multimoneda_cache');
    // No borrar ventas_pendientes para no perder ventas sin sincronizar
  }
}
