# Architecture

Layered, loosely Clean-Architecture-shaped. Data flows: **UI (screens) → Provider → SyncService → DataSources (local + remote)**.

- **`lib/core/di/injection.dart`** — hand-rolled dependency injection. A single `Injection` singleton (`injection`) constructs every datasource, the `ApiClient`, and the `SyncService` in `init()`, called once from `main()` before `runApp`. There is no DI framework — wire new dependencies here.
- **`lib/main.dart`** — sets up `MultiProvider`. Providers are `ChangeNotifier`s that wrap `SyncService`; `SyncService` itself is exposed as a plain `Provider.value`.
- **`lib/services/sync_service.dart`** — **the heart of the app.** The single orchestrator that all providers call. Owns connectivity monitoring, the offline queue, and the online/offline strategy. Everything read-through-cache and write-behind lives here. See `SYNC.md` for the detailed offline-first model.
- **`lib/data/datasources/local/`** — SQLite (`sqflite`) caches and the offline queue. **`database_helper.dart`** owns the schema and migrations (see `DATABASE.md`).
- **`lib/data/datasources/remote/`** — thin wrappers over `ApiClient` (Dio) per resource.
- **`lib/providers/`** — one `ChangeNotifier` per domain (auth, productos, cart, ventas, periodo, monedas, sync). Screens `context.watch/read` these.
- **`lib/core/`** — cross-cutting: `network/` (ApiClient, secure storage, connectivity — see `AUTH.md`), `constants/`, `utils/` (pure business logic — payments, currency, formatters, POS product rules), `errors/`.
