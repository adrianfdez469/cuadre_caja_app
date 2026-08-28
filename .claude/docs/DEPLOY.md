# Deploy / Release

Release APK builds (output in `build/app/outputs/flutter-apk/`):

```bash
flutter build apk --release --split-per-abi          # one APK per ABI (what releases use)
flutter build apk --release --target-platform android-arm64   # single ABI
flutter build apk --release                          # universal (all ABIs, largest)
```

Releasing a new version is driven by **`scripts/release.py`** — the deterministic executor. Subcommands: `auth-check`, `plan` (next version + unshipped commits), `bump`, `commit`, `build`, `upload` (APKs to Drive, in place), `publish` (merge + validate `releases.json`), `report`, `retry-upload`. All of them take `--dry-run`. Drive file IDs live in `scripts/release_config.json`; its pure logic is covered by `python3 scripts/test_release.py`.

Drive access is in **`scripts/drive_client.py`**. It authenticates as the user's own Google account via OAuth, reading `GDRIVE_CLIENT_ID` / `GDRIVE_CLIENT_SECRET` / `GDRIVE_REFRESH_TOKEN` from the gitignored **`.env.local` in the repo root** — credentials are per-project, so different repos can use different Google accounts. The refresh token is minted once by `release.py auth-login`, which is interactive (opens a browser) and refuses to run without a TTY: **the user runs it, never Claude**. Falls back to the `gdrive` binary when unconfigured. Setup is in `docs/ACTUALIZACIONES_DRIVE.md`; `.env.local.example` is the template. Run `auth-check` before a release — it reports which Google account is active and whether all five Drive files are still editable. Note: an OAuth client left in "Testing" status has its refresh token revoked by Google every 7 days, so the app must be published.

The **`app-release` skill** (invoke it for "deploy", "publish", "cut a release") wraps that script with the parts that need judgment: writing the Spanish changelog from the git diffs, the confirmation gate, and the WhatsApp announcement. See `docs/ACTUALIZACIONES_DRIVE.md`. Critical rule the script enforces: every release must **increase** the `+N` build number (Android `versionCode`) or the update won't install. Drive files are always updated in place — a new upload mints a new file ID and breaks self-update.
