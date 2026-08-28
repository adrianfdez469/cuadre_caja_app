# Database migrations

`DatabaseHelper._databaseVersion` (currently 6) gates the schema. When you change a table, **bump the version and add an `onUpgrade` branch** — users upgrade in place via the Drive updater, so destructive recreation loses their unsynced (`ventas_pendientes`) sales. Key tables: `productos`, `ventas_pendientes` (offline queue), `ventas_servidor_cache`, `periodo_cache`, `transfer_destinations`, `carritos`, `multimoneda_cache`.
