# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`cuadre_caja_app` is an **offline-first Android POS (point-of-sale)** app built with Flutter. It is the mobile client for the Ventario/Cuadre Caja platform; the backend lives at `https://cuadrecaja.ventario.cloud/api/app` (see `lib/core/constants/api_constants.dart`). The app must keep selling while the device is offline and reconcile everything with the server once connectivity returns — this constraint drives most of the architecture. UI strings, comments, and docs are in Spanish.

## Commands

```bash
flutter pub get                 # install deps (run after changing pubspec)
flutter analyze                 # lint / static analysis (flutter_lints)
flutter run -d macos            # default way to launch/preview the app (macOS desktop), unless told otherwise
flutter run                     # run on connected device/emulator
flutter test                    # run all tests
flutter test test/core/utils/payment_logic_test.dart   # run a single test file
flutter test --name "substring of test name"           # run tests matching a name
```

For release APK builds and the full deploy/release flow (`scripts/release.py`, Drive upload, the `app-release` skill), see **`.claude/docs/DEPLOY.md`**.

## Detailed docs

The topics below used to live inline in this file. They're split out so they only get pulled into context when actually relevant — read the linked file before working on that area:

- **`.claude/docs/DEPLOY.md`** — release builds, `scripts/release.py`, `scripts/drive_client.py`, Drive OAuth, the `app-release` skill.
- **`.claude/docs/ARCHITECTURE.md`** — layers, DI (`injection.dart`), providers, folder structure.
- **`.claude/docs/SYNC.md`** — the offline-first sync model (`sync_service.dart`): read-through-cache, write-behind queue, reconnect ordering. Read this before touching sync.
- **`.claude/docs/AUTH.md`** — `ApiClient` auth interceptor, token refresh, secure storage timeout.
- **`.claude/docs/DATABASE.md`** — SQLite schema/migrations (`database_helper.dart`), key tables.
- **`.claude/docs/MULTIMONEDA.md`** — multi-currency payments, `payment_logic.dart`.
- **`.claude/docs/BARCODE.md`** — barcode scanning (camera + hardware scanner gun).
- **`.claude/docs/CONVENTIONS.md`** — testing, logging (`logDebug`, never `print`), UUID conventions, other reference docs at repo root.
- **`.claude/docs/BACKLOG-UX.md`** — backlog priorizado de UX/accesibilidad del flujo de venta (UX-01…UX-19). Consultar antes de proponer mejoras al POS: puede que ya esté registrado.
