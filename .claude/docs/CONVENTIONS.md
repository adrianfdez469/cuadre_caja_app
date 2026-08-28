# Conventions

- **Tests** cover pure logic (`test/core/utils/`) and payment widgets (`test/screens/pos/payment_modal_test.dart`), using fakes in `test/fakes/`. There is no integration/e2e harness — verify sync behavior manually against the running app.
- Logging goes through `logDebug()` (`lib/core/utils/app_logger.dart`), which wraps `print` in `kDebugMode` and carries the only `// ignore: avoid_print` in the codebase. Messages use emoji prefixes (🚀 ✅ ❌ 🌐 ⚠️). Never call `print()` directly outside `app_logger.dart`.
- IDs for new offline records are client-generated UUIDs (`uuid` package) so they're stable across the offline→online boundary; the server may return its own `serverId` which is stored alongside.
- Reference docs (Spanish) at repo root: `APP_API_CONTRACT.md`, `API_APP_DOCUMENTATION.md`, `ESPECIFICACIONES_PRODUCTOS_POS.md`, `CONFIGURACION.md`, and `docs/ACTUALIZACIONES_DRIVE.md` describe the API contract, POS product rules, and the self-update flow.
