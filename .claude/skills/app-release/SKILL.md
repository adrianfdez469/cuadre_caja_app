---
name: app-release
description: Automates deploying a new release of this Flutter app — bumping version numbers, committing/pushing to git, building release APKs, uploading them to the app's public Google Drive folder, and updating releases.json (the file the app itself polls to check for and download updates). Use this skill whenever the user asks to "deploy", "release", "publish a new version", "ship an update", "cut a release", or gives you a changelog and wants it turned into a new app version. Also use it if the user just says something like "bump the version and release" or pastes a list of fixes/improvements and wants them shipped.
---

# Flutter App Release

Automates the full release pipeline for this Flutter app: version bump → git commit/push → release builds → Google Drive update → `releases.json` update.

This skill only ever runs on **this** project (`cuadre_caja_app`). Assume the project root is the current working directory — never ask for a path.

The app self-updates by polling `releases.json` in a public (read-only) Google Drive folder. That file holds the current version string, the Drive file IDs for each APK variant, and a changelog. Getting this file exactly right is the most error-prone part of the workflow — treat it carefully.

**Critical Drive rule (read `Step 4` before uploading anything):** every file in the Drive folder — the 4 APKs *and* `releases.json` — has a permanent file ID that must never change. The app polls `releases.json` by its fixed ID, and `releases.json` references each APK by its fixed ID. Uploading a *new* file mints a *new* ID and breaks the update flow. Always update files **in place** ("Manage versions → Upload new version"), never delete-and-re-upload.

## Before starting: gather inputs

Two inputs drive everything downstream: the **version number** and the **changelog**. Neither requires asking the user if they didn't provide it — derive them:

- **Version number** — if the user didn't give one, just **auto-increment the patch** of the current version (read `pubspec.yaml`), e.g. `1.1.6` → `1.1.7`. Only ask if the user hints at a minor/major bump but didn't say which.
- **Changelog** — if the user didn't provide changelog items, **derive them from the recent git history** (the commits made since the last release / not yet shipped). Read the actual changes:

  ```bash
  git log --oneline -15
  git log -5 -p --stat        # inspect actual changes if commit messages are terse
  ```

  Turn those into user-facing changelog sentences (see `Step 5` for wording/categories). Terse or `.`-only commit messages are common in this repo, so read the diffs rather than trusting messages.

Then go straight to the confirmation gate below — do **not** start bumping/building until the user has confirmed.

## Step 0 — Confirmation gate (BEFORE any changes)

Before touching any files, show the user a preview and wait for approval. This preview happens **before Step 1** — nothing is modified, committed, or built until the user responds.

Show:
1. **New version number** (with build number, e.g. `1.1.7+18`).
2. **Changelog text**, exactly as it will appear in `releases.json` — each item with its category (`Mejoras` / `Arreglos` / `Caracteristicas`) and Spanish sentence.

Then explicitly ask the user to either **edit** any of it or **confirm to proceed**. Only continue once they approve. Apply any edits they request and re-show if the changes were substantial.

(APK filenames and sizes don't exist yet — they're produced by the build in Step 3 and reported to the user there, informationally, without a second gate.)

## Step 1 — Bump version numbers

Two files to update, both must match:

- `lib/core/constants/app_constants.dart` — find the `appVersion` constant and set it to the new version string (e.g. `"1.1.6"` → `"1.1.7"`).
- `pubspec.yaml` — the `version:` line follows `major.minor.patch+build`. Set the version part to match, and **increment the build number by exactly 1** (e.g. `1.1.6+17` → `1.1.7+18`).

Use `grep`/`view` first to confirm the exact current strings before editing — don't assume formatting. The build number (`+N`, the Android `versionCode`) **must increase every release** or the update won't install.

## Step 2 — Commit and push

Commit message: plain descriptive text in Spanish, summarizing the changes (not conventional-commits style). Base it on the changelog items. Example style: `Se mejora la rapidez en la venta y se agregan multimonedas`.

```bash
git add lib/core/constants/app_constants.dart pubspec.yaml
git commit -m "<spanish summary of the changes>"
git push origin main
```

Confirm the push succeeded before moving on.

## Step 3 — Build release APKs

Run both build commands from the project root:

```bash
flutter build apk --release
flutter build apk --release --split-per-abi
```

Output APKs land in `build/app/outputs/flutter-apk/`:
- `app-release.apk` → universal
- `app-arm64-v8a-release.apk` → arm64-v8a
- `app-armeabi-v7a-release.apk` → armeabi-v7a
- `app-x86_64-release.apk` → x86_64

If either build fails, stop and surface the error — don't proceed to upload stale/missing APKs.

After a successful build, **report to the user** the 4 generated APKs with each one's **file size** (e.g. `ls -lh build/app/outputs/flutter-apk/`). This is informational — no confirmation gate here (that already happened in Step 0).

## Step 4 — Update files on Google Drive (in place — never delete + re-upload)

Target folder: `https://drive.google.com/drive/folders/16LfxLzdav-PUsn97EcSnTdcNZcZnYukd`

Every file in this folder must keep its **existing file ID**. To do that, replace each file's *contents* via `files.update` targeting the existing fileId. Do **not** delete the old file and upload a new one — that mints a new ID and breaks the app's update flow.

**Why this matters:** the app polls `releases.json` by its fixed ID, and `releases.json` points at each APK by its fixed ID. If APK IDs stay constant, the `apks` block in `releases.json` **never needs to change** — only `version` + `changelog` do (Step 5).

**Upload path: the `gdrive` CLI is set up and authenticated** (`gdrive account list` shows the linked account). Use it to update each file in place — no manual browser steps needed:

```bash
gdrive files update 1NInsC79yo2Gcs6FLOEzjAORF6hEOEaJm build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
gdrive files update 15DrgQE14pvmTyfgToFZT4MXYz7XfrBRA build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
gdrive files update 1EYCDRlMgYn38XKE_DfW1r4LH6r3Dfzzs build/app/outputs/flutter-apk/app-x86_64-release.apk
gdrive files update 1XCEu0G17CpmbzG4x4neYWLD2s50st-VH build/app/outputs/flutter-apk/app-release.apk
```

These file IDs are fixed for this project's Drive folder — if `gdrive files list --parent 16LfxLzdav-PUsn97EcSnTdcNZcZnYukd` ever shows different IDs for these filenames, use the current ones instead (something was re-created outside this flow).

`releases.json`'s ID (`1ekvyYpK0K693H0fYskQO4qMlM1vgkmrv`) is updated the same way in Step 5, after its contents are edited locally.

**File IDs stay constant, so the `apks` block in `releases.json` should not need editing.** Only if an APK's ID ever genuinely changes (a file was accidentally re-created, or it's the very first setup) do you need to capture the new ID (the segment between `/d/` and `/view` in a shareable link, e.g. from `https://drive.google.com/file/d/1NInsC79yo2Gcs6FLOEzjAORF6hEOEaJm/view` the ID is `1NInsC79yo2Gcs6FLOEzjAORF6hEOEaJm`) and map it to its arch key: `arm64-v8a`, `armeabi-v7a`, `x86_64`, `universal`.

## Step 5 — Update releases.json

Fetch the current `releases.json` with `gdrive files download 1ekvyYpK0K693H0fYskQO4qMlM1vgkmrv --destination /tmp` (or overwrite an existing local copy with `--overwrite`). Then edit it locally:

1. **`version`** → set to the new version string (must match `appVersion`, e.g. `"1.1.7"`).
2. **`apks`** → **leave unchanged** if APK IDs were preserved via in-place updates (the normal case). Only replace an ID if that specific APK's ID actually changed (see Step 4).
3. **`changelog`** → add a **new top-level key** `"v<version>"` (e.g. `"v1.1.7"`) as a new entry. Existing entries are never modified or removed — only prepend/add the new one. The value is a list of single-key objects, one per changelog item, using these category keys **exactly** (capitalized, plural):
   - `"Mejoras"` — improvements
   - `"Arreglos"` — bug fixes
   - `"Caracteristicas"` — new features

   Each list item is `{"Mejoras": "<one sentence in Spanish>"}` (or `Arreglos`/`Caracteristicas`), one item per sentence — do not combine multiple changes into one string. This matches the convention used in `v1.1.4`/`v1.1.5`. Text should be in Spanish, matching the tone of existing entries (concise, user-facing descriptions of what changed).

   Example of a well-formed new entry:
   ```json
   "v1.1.7": [
     {"Arreglos": "Se arregla un error al sincronizar ventas offline"},
     {"Mejoras": "Se agrega soporte para impresoras térmicas Bluetooth"}
   ]
   ```

4. Validate the whole file is valid JSON before uploading (e.g. `python3 -m json.tool` on it).

Upload the updated `releases.json` back **in place**, preserving its ID:

```bash
gdrive files update 1ekvyYpK0K693H0fYskQO4qMlM1vgkmrv /tmp/releases.json
```

## Step 6 — Summary

After finishing, give the user a short summary: new version + build number, what was committed, build status with the 4 APK sizes, and confirmation the Drive files + `releases.json` were updated **in place** (IDs preserved) via `gdrive`. Flag anything that failed (e.g. a `gdrive` command errored, or `gdrive account list` shows no linked account) rather than assuming it's done.

## Step 7 — WhatsApp announcement (ready to copy/paste)

After the summary, generate a **marketing announcement in Spanish, ready to paste into the WhatsApp release group**. This is the last thing you output.

Requirements:
- Put it in its own fenced code block so the user can copy the whole thing in one tap. Nothing else inside that block.
- Use **WhatsApp formatting**: `*bold*` for emphasis (WhatsApp uses single asterisks, not `**`), and tasteful emojis. Do **not** use Markdown headings, `**double asterisks**`, or `#` — they don't render in WhatsApp.
- Friendly, upbeat, user-facing tone — this is for shop owners/cashiers, not developers. Translate the changelog into benefits, not technical jargon.
- Content: a short excited opener with the new version number (e.g. `🎉 *Nueva actualización disponible (v1.1.7)* 🎉`), then the highlights grouped naturally (new features / improvements / fixes) as a short bulleted list using emoji bullets (✨ mejoras, 🐛 arreglos, 🚀 nuevo), then a brief closing line telling users the update installs automatically / to open the app to get it.
- Keep it concise — a handful of bullet points, not the full raw changelog. Merge trivial items.

Example shape (adapt wording to the actual changelog):

```
🎉 *¡Nueva actualización disponible!* 🎉
Versión *1.1.7* ya está lista 📲

✨ *Novedades:*
• Ahora puedes cobrar en varias monedas
• Ventas más rápidas en el punto de venta

🐛 *Arreglos:*
• Corregimos un error al sincronizar ventas sin internet

La actualización se instala sola al abrir la app 🙌 ¡Gracias por usar Cuadre Caja!
```

## Notes / assumptions baked into this skill

- Runs only on this project — never ask for a project path.
- If no version is given, auto-increment the patch. If no changelog is given, derive it from recent git commits/diffs.
- Confirmation of version + changelog happens **before** any changes (Step 0). APK sizes are reported after the build, informationally, with no second gate.
- Build number always increments by exactly 1 per release and must increase.
- Commit messages are plain descriptive Spanish text, not conventional commits.
- **Never delete + re-upload Drive files.** Always update in place via "Manage versions" so file IDs (and the app's update links) are preserved.
- Changelog category keys going forward: `Mejoras` / `Arreglos` / `Caracteristicas` (capitalized, plural) — older entries in the file use inconsistent casing/singular forms; don't "fix" old entries, just be consistent going forward.
