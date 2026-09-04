import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = 'cuadre_caja.db';
  static const _databaseVersion = 8;

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
      CREATE TABLE IF NOT EXISTS productos (
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
      CREATE TABLE IF NOT EXISTS ventas_pendientes (
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
        errorCode TEXT,
        serverId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ventas_servidor_cache (
        id TEXT PRIMARY KEY,
        tiendaId TEXT NOT NULL,
        periodoId TEXT NOT NULL,
        ventaJson TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS periodo_cache (
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
      CREATE TABLE IF NOT EXISTS transfer_destinations (
        id TEXT PRIMARY KEY,
        tiendaId TEXT NOT NULL,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        isDefault INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS carritos (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        itemsJson TEXT NOT NULL DEFAULT '[]',
        tiendaId TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS multimoneda_cache (
        negocioId TEXT PRIMARY KEY,
        configJson TEXT NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');

    // Índices para queries frecuentes
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_tienda ON productos(tiendaId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos(categoriaId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ventas_sync ON ventas_pendientes(syncState)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_carritos_tienda ON carritos(tiendaId)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE productos ADD COLUMN codigosJson TEXT');
      } catch (_) {}
    }
    if (oldVersion <= 1) {
      // Reset de v1: las tablas de solo-cache se recrean (son re-descargables),
      // pero ventas_pendientes NO se destruye — contiene ventas sin sincronizar.
      // Se aparta, se recrea el esquema actual y se copian las columnas comunes
      // (lo que no exista en el esquema viejo queda con su valor por defecto).
      await db.execute('DROP TABLE IF EXISTS productos');
      await db.execute('DROP TABLE IF EXISTS periodo_cache');
      await db.execute('DROP TABLE IF EXISTS transfer_destinations');
      await db.execute('DROP TABLE IF EXISTS carritos');

      final teniaPendientes = await _tableExists(db, 'ventas_pendientes');
      if (teniaPendientes) {
        await db.execute('DROP TABLE IF EXISTS ventas_pendientes_old');
        await db.execute(
            'ALTER TABLE ventas_pendientes RENAME TO ventas_pendientes_old');
      }

      await _onCreate(db, newVersion);

      if (teniaPendientes) {
        await _copyCommonColumns(
            db, 'ventas_pendientes_old', 'ventas_pendientes');
        await db.execute('DROP TABLE ventas_pendientes_old');
      }
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
    if (oldVersion < 7) {
      // Los carritos pasaron a llamarse cuentas: 'Carrito 1' -> 'Cuenta #1'.
      // 'Carrito ' son 8 caracteres, asi que substr(nombre, 9) deja el numero.
      // El LIKE respeta los nombres que el usuario haya puesto a mano.
      try {
        await db.execute(
          "UPDATE carritos SET nombre = 'Cuenta #' || substr(nombre, 9) "
          "WHERE nombre LIKE 'Carrito %'",
        );
      } catch (_) {}
    }
    if (oldVersion < 8) {
      // El `code` con el que el API rechaza una venta. El texto del error ya se
      // guarda en errorMessage, pero es para el cajero y puede cambiar; el code
      // es lo que decide si vale la pena reintentar.
      try {
        await db.execute(
          'ALTER TABLE ventas_pendientes ADD COLUMN errorCode TEXT',
        );
      } catch (_) {}
    }
  }

  Future<bool> _tableExists(Database db, String name) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    );
    return rows.isNotEmpty;
  }

  Future<List<String>> _columnNames(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Copia las filas de [from] a [to] usando solo las columnas presentes en
  /// ambas tablas. Sirve para preservar datos al recrear una tabla con un
  /// esquema más nuevo sin conocer el esquema viejo de antemano.
  Future<void> _copyCommonColumns(Database db, String from, String to) async {
    final fromCols = await _columnNames(db, from);
    final toCols = await _columnNames(db, to);
    final comunes = fromCols.where(toCols.contains).toList();
    if (comunes.isEmpty) return;
    final cols = comunes.join(', ');
    await db.execute('INSERT INTO $to ($cols) SELECT $cols FROM $from');
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('productos');
    await db.delete('periodo_cache');
    await db.delete('transfer_destinations');
    await db.delete('carritos');
    await db.delete('multimoneda_cache');
    await db.delete('ventas_servidor_cache');
    // No borrar ventas_pendientes para no perder ventas sin sincronizar
  }
}
