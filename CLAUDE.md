# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cuadre_caja_app` is an **offline-first Android POS (point-of-sale)** app built with Flutter. It is the mobile client for the Ventario/Cuadre Caja platform; the backend lives at `https://cuadrecaja.ventario.cloud/api/app` (see `lib/core/constants/api_constants.dart`). The app must keep selling while the device is offline and reconcile everything with the server once connectivity returns — this constraint drives most of the architecture. UI strings, comments, and docs are in Spanish.

## Commands

```bash
flutter pub get                 # install deps (run after changing pubspec)
flutter analyze                 # lint / static analysis (flutter_lints)
flutter run                     # run on connected device/emulator
flutter test                    # run all tests
flutter test test/core/utils/payment_logic_test.dart   # run a single test file
flutter test --name "substring of test name"           # run tests matching a name
```

Release APK builds (output in `build/app/outputs/flutter-apk/`):

```bash
flutter build apk --release --split-per-abi          # one APK per ABI (what releases use)
flutter build apk --release --target-platform android-arm64   # single ABI
flutter build apk --release                          # universal (all ABIs, largest)
```

Releasing a new version is automated by the **`app-release` skill** (invoke it for "deploy", "publish", "cut a release"). It bumps `version` in `pubspec.yaml`, builds, uploads APKs to a public Google Drive folder, and updates `releases.json` — the file the app polls for self-updates. See `docs/ACTUALIZACIONES_DRIVE.md`. Critical rule: every release must **increase** the `+N` build number (Android `versionCode`) or the update won't install.

## Architecture

Layered, loosely Clean-Architecture-shaped. Data flows: **UI (screens) → Provider → SyncService → DataSources (local + remote)**.

- **`lib/core/di/injection.dart`** — hand-rolled dependency injection. A single `Injection` singleton (`injection`) constructs every datasource, the `ApiClient`, and the `SyncService` in `init()`, called once from `main()` before `runApp`. There is no DI framework — wire new dependencies here.
- **`lib/main.dart`** — sets up `MultiProvider`. Providers are `ChangeNotifier`s that wrap `SyncService`; `SyncService` itself is exposed as a plain `Provider.value`.
- **`lib/services/sync_service.dart`** — **the heart of the app.** The single orchestrator that all providers call. Owns connectivity monitoring, the offline queue, and the online/offline strategy. Everything read-through-cache and write-behind lives here.
- **`lib/data/datasources/local/`** — SQLite (`sqflite`) caches and the offline queue. **`database_helper.dart`** owns the schema and migrations.
- **`lib/data/datasources/remote/`** — thin wrappers over `ApiClient` (Dio) per resource.
- **`lib/providers/`** — one `ChangeNotifier` per domain (auth, productos, cart, ventas, periodo, monedas, sync). Screens `context.watch/read` these.
- **`lib/core/`** — cross-cutting: `network/` (ApiClient, secure storage, connectivity), `constants/`, `utils/` (pure business logic — payments, currency, formatters, POS product rules), `errors/`.

### Offline-first sync model (read carefully before touching sync)

- **Reads** (`loadProductos`, `loadPeriodoActual`, `loadMultimonedaConfig`, …): try the API first, **fall back to the SQLite cache** on failure. `*LocalOnly` / `get*Local` variants read disk only (no network) — used to refresh the POS instantly after a sale.
- **Writes** (`crearVenta`): always persist to SQLite **first** (into `ventas_pendientes` with a client-generated `syncId`/UUID and `syncState`), then attempt to sync. A sale never blocks on the network.
- **The queue**: `ventas_pendientes` is the write-behind queue. A `Timer.periodic` (every 30s) plus a connectivity listener drain it via `_syncPendingVentas`. On reconnect, `_onConnectionRestored` runs **ventas-first, then refreshes server inventory last** so local stock isn't clobbered before pending sales are posted.
- **`fullSync`** does the full reconcile: período/destinos/monedas → pending ventas → server inventory.
- `SyncService` communicates back to the UI through **callbacks** (`onConnectionChanged`, `onSyncEvent`, `onDataRefreshed`, `onAuthRequired`, `onTokenRefreshed`) that providers register — not streams.
- Fracción products (sub-units) are "desagregated" into their parent before stock is decremented — see `crearVenta` and `lib/core/utils/producto_pos_rules.dart`.

### Auth

`ApiClient` (Dio interceptor) attaches the Bearer token from `flutter_secure_storage` and transparently handles **401 → token refresh → retry** once. Token reads have a 5s timeout because `FlutterSecureStorage` can hang on some Android ABIs (notably arm64-v8a). Session restore + refresh happens in `SplashScreen._init()` on launch.

### Database migrations

`DatabaseHelper._databaseVersion` (currently 6) gates the schema. When you change a table, **bump the version and add an `onUpgrade` branch** — users upgrade in place via the Drive updater, so destructive recreation loses their unsynced (`ventas_pendientes`) sales. Key tables: `productos`, `ventas_pendientes` (offline queue), `ventas_servidor_cache`, `periodo_cache`, `transfer_destinations`, `carritos`, `multimoneda_cache`.

### Multi-currency (multimoneda)

Sales can be paid in multiple currencies with exchange-rate snapshots stored on each pending venta (`tasaSnapshotJson`, `pagosDetalleJson`). Rates/currencies come from `/monedas/{negocioId}` and `/tasas-cambio/{negocioId}`. Payment math is isolated in `lib/core/utils/payment_logic.dart` and is the best-tested code in the repo — keep it pure and covered.

### Barcode scanning

Two input paths: the camera (`mobile_scanner`) and external Bluetooth/USB scanner "guns" (keyboard-wedge). `HardwareScannerGate` (a singleton with reason-tagged blocking) suppresses the hardware scanner during certain UI states (modals, etc.); `HardwareScannerListener` / `barcode_scan_processor.dart` handle the wedge input.

## Conventions

- **Tests** cover pure logic (`test/core/utils/`) and payment widgets (`test/screens/pos/payment_modal_test.dart`), using fakes in `test/fakes/`. There is no integration/e2e harness — verify sync behavior manually against the running app.
- Logging goes through `logDebug()` (`lib/core/utils/app_logger.dart`), which wraps `print` in `kDebugMode` and carries the only `// ignore: avoid_print` in the codebase. Messages use emoji prefixes (🚀 ✅ ❌ 🌐 ⚠️). Never call `print()` directly outside `app_logger.dart`.
- IDs for new offline records are client-generated UUIDs (`uuid` package) so they're stable across the offline→online boundary; the server may return its own `serverId` which is stored alongside.
- Reference docs (Spanish) at repo root: `APP_API_CONTRACT.md`, `API_APP_DOCUMENTATION.md`, `ESPECIFICACIONES_PRODUCTOS_POS.md`, `CONFIGURACION.md`, and `docs/ACTUALIZACIONES_DRIVE.md` describe the API contract, POS product rules, and the self-update flow.
