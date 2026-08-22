#!/usr/bin/env bash
# Setup script for Orca / git worktrees.
# Runs after a new worktree is created: copy local files, install Flutter deps.
#
# Env (injected by Orca):
#   ORCA_ROOT_PATH     — main checkout (source of gitignored local files)
#   ORCA_WORKTREE_PATH — new worktree (cwd for setup)
set -euo pipefail

ROOT="${ORCA_ROOT_PATH:-${ROOT_WORKTREE_PATH:-}}"
WT="${ORCA_WORKTREE_PATH:-$(pwd)}"

cd "$WT"

echo "🔧 Worktree setup → $WT"
if [[ -n "$ROOT" ]]; then
  echo "📦 Root checkout → $ROOT"
fi

# --- Copy gitignored local files from the main checkout (if present) ---
copy_if_exists() {
  local rel="$1"
  if [[ -n "$ROOT" && -e "$ROOT/$rel" ]]; then
    mkdir -p "$(dirname "$rel")"
    cp -R "$ROOT/$rel" "$rel"
    echo "  ✅ copied $rel"
  fi
}

copy_if_exists "android/local.properties"   # SDK paths (required for Android builds)
copy_if_exists "android/key.properties"     # signing (optional)
copy_if_exists ".env"
copy_if_exists ".env.local"
copy_if_exists ".claude/settings.local.json"

# Keystores next to key.properties (if any)
if [[ -n "$ROOT" ]]; then
  shopt -s nullglob
  for f in "$ROOT"/android/*.{jks,keystore}; do
    base="$(basename "$f")"
    cp "$f" "android/$base"
    echo "  ✅ copied android/$base"
  done
  shopt -u nullglob
fi

# --- Install dependencies ---
if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ flutter no está en PATH" >&2
  exit 1
fi

flutter pub get

# SQLite migrations viven en DatabaseHelper y corren al arrancar la app.
# No hay paso de migrate en CLI para este proyecto.

echo "✅ Worktree listo (flutter pub get OK)"
