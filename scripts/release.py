#!/usr/bin/env python3
"""Pipeline de release de cuadre_caja_app — la parte determinista.

El skill `app-release` aporta lo que requiere criterio (redactar el changelog en
español, el gate de confirmación, el anuncio de WhatsApp). Todo lo mecánico vive
aquí, con asserts, porque es lo que puede romper la actualización en producción.

Reglas invariantes que este script hace cumplir (no relajarlas):

  * El build number (`+N` de pubspec.yaml = versionCode de Android) SIEMPRE sube.
    Si baja o se repite, Android muestra "No se instaló la app" aunque la descarga
    funcione. Ver docs/ACTUALIZACIONES_DRIVE.md.
  * `appVersion` en app_constants.dart y la parte semver de pubspec.yaml deben
    coincidir exactamente, antes y después del bump.
  * Los archivos de Drive se actualizan SIEMPRE in-place, contra su fileId.
    Nunca borrar y volver a subir: eso acuña un fileId nuevo y rompe el flujo de
    auto-actualización de la app. Las credenciales (OAuth de usuario, por
    proyecto) las resuelve scripts/drive_client.py — ver `auth-login`/`auth-check`.
  * Las entradas viejas del changelog nunca se modifican ni se borran — la app
    (ReleaseInfo.getChangelogSince) muestra todas las versiones intermedias a
    quien está varias versiones atrasado.
  * Un fallo de Drive por permisos/autenticación NO se reintenta y NO aborta el
    release: se anota, se sigue, y se reporta al final (exit code 2).

Uso típico (lo encadena el skill):

    python3 scripts/release.py plan
    python3 scripts/release.py bump --version 1.1.14
    python3 scripts/release.py commit --message "Sube la version a 1.1.14: ..."
    python3 scripts/release.py build
    python3 scripts/release.py upload
    python3 scripts/release.py publish --changelog build/changelog.json
    python3 scripts/release.py report
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from drive_client import (  # noqa: E402
    DriveError,
    UserOAuthClient,
    load_env as drive_env,
    resolve_client,
    run_consent_flow,
    write_env_vars,
)
from drive_client import _looks_like_auth as is_auth_error  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = Path(__file__).resolve().parent / "release_config.json"
PUBSPEC_PATH = REPO_ROOT / "pubspec.yaml"
CONSTANTS_PATH = REPO_ROOT / "lib" / "core" / "constants" / "app_constants.dart"
BUILD_DIR = REPO_ROOT / "build"
STATE_PATH = BUILD_DIR / "release-state.json"
RELEASES_JSON_PATH = BUILD_DIR / "releases.json"

EXIT_OK = 0
EXIT_HARD_FAIL = 1
EXIT_DRIVE_DEGRADED = 2

# `[ \t]*$` y no `\s*$`: `\s` engulliría el salto de línea y pegaría la línea
# siguiente al reemplazar.
PUBSPEC_VERSION_RE = re.compile(
    r"^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$", re.M
)
APP_VERSION_RE = re.compile(
    r"(static\s+const\s+String\s+appVersion\s*=\s*')(\d+\.\d+\.\d+)(';)"
)

class ReleaseError(Exception):
    """Fallo duro: aborta el release (exit code 1)."""


# ---------------------------------------------------------------------------
# Lógica pura (cubierta por scripts/test_release.py)
# ---------------------------------------------------------------------------


def parse_pubspec_version(text: str) -> tuple[str, int]:
    """Devuelve (semver, build) desde el contenido de pubspec.yaml."""
    m = PUBSPEC_VERSION_RE.search(text)
    if not m:
        raise ReleaseError(
            "No se encontró una línea 'version: X.Y.Z+N' válida en pubspec.yaml"
        )
    major, minor, patch, build = m.groups()
    return f"{major}.{minor}.{patch}", int(build)


def parse_constants_version(text: str) -> str:
    """Devuelve el valor de appVersion desde app_constants.dart."""
    m = APP_VERSION_RE.search(text)
    if not m:
        raise ReleaseError(
            "No se encontró la constante appVersion en app_constants.dart"
        )
    return m.group(2)


def version_tuple(version: str) -> tuple[int, int, int]:
    parts = version.lstrip("v").split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise ReleaseError(f"Versión inválida: {version!r} (se espera X.Y.Z)")
    return tuple(int(p) for p in parts)  # type: ignore[return-value]


def next_version(current: str, level: str = "patch") -> str:
    major, minor, patch = version_tuple(current)
    if level == "major":
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    if level == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise ReleaseError(f"Nivel de bump desconocido: {level!r}")


def assert_versions_in_sync(pubspec_version: str, constants_version: str) -> None:
    if pubspec_version != constants_version:
        raise ReleaseError(
            "pubspec.yaml y app_constants.dart están desincronizados: "
            f"pubspec={pubspec_version} appVersion={constants_version}. "
            "Arréglalo a mano antes de releasear."
        )


def assert_version_increases(current: str, new: str) -> None:
    if version_tuple(new) <= version_tuple(current):
        raise ReleaseError(
            f"La versión nueva ({new}) debe ser mayor que la actual ({current})"
        )


def assert_build_increases(current_build: int, new_build: int) -> None:
    if new_build <= current_build:
        raise ReleaseError(
            f"El build number debe subir: {current_build} -> {new_build}. "
            "Un versionCode que no aumenta hace que Android rechace la instalación."
        )


def apply_pubspec_version(text: str, version: str, build: int) -> str:
    new_text, n = PUBSPEC_VERSION_RE.subn(f"version: {version}+{build}", text, count=1)
    if n != 1:
        raise ReleaseError("No se pudo reemplazar la versión en pubspec.yaml")
    return new_text


def apply_constants_version(text: str, version: str) -> str:
    new_text, n = APP_VERSION_RE.subn(rf"\g<1>{version}\g<3>", text, count=1)
    if n != 1:
        raise ReleaseError("No se pudo reemplazar appVersion en app_constants.dart")
    return new_text


def validate_changelog(entries: object, categories: list[str]) -> list[dict]:
    """Valida el changelog.json que redacta el skill.

    Formato: lista de dicts de UNA sola clave, con la clave en `categories`.
    """
    if not isinstance(entries, list) or not entries:
        raise ReleaseError(
            "El changelog debe ser una lista no vacía, p.ej. "
            '[{"Arreglos": "Se arregla ..."}]'
        )
    for i, item in enumerate(entries):
        if not isinstance(item, dict) or len(item) != 1:
            raise ReleaseError(
                f"Ítem {i} del changelog: se espera un objeto de exactamente una "
                f"clave, se recibió {item!r}"
            )
        (key, value), = item.items()
        if key not in categories:
            raise ReleaseError(
                f"Ítem {i} del changelog: categoría {key!r} inválida. "
                f"Usa una de {categories}"
            )
        if not isinstance(value, str) or not value.strip():
            raise ReleaseError(
                f"Ítem {i} del changelog: el texto debe ser una frase no vacía"
            )
    return entries


def merge_releases_json(
    current: dict,
    version: str,
    changelog_entries: list[dict],
    apk_ids: dict[str, str] | None = None,
) -> dict:
    """Devuelve un releases.json nuevo con la versión y el changelog añadidos.

    - `apks` queda intacto salvo que se pasen ids explícitos (caso raro: un
      fileId cambió de verdad porque el archivo se recreó fuera de este flujo).
    - Las entradas de changelog existentes nunca se tocan.
    - Idempotente: reejecutarlo con la misma versión no duplica ni pisa nada.
    """
    result = copy.deepcopy(current)
    result["version"] = version

    apks = result.get("apks")
    if not isinstance(apks, dict):
        apks = {}
    if apk_ids:
        apks = {**apks, **apk_ids}
    result["apks"] = apks

    changelog = result.get("changelog")
    if not isinstance(changelog, dict):
        changelog = {}
    key = f"v{version}"
    if key not in changelog:
        # Prepend para que la entrada nueva quede arriba en el archivo.
        changelog = {key: changelog_entries, **changelog}
    else:
        changelog[key] = changelog_entries
    result["changelog"] = changelog
    return result


def validate_releases_json(
    data: dict, version: str, arch_keys: list[str], categories: list[str]
) -> None:
    """Última barrera antes de subir el archivo del que depende la app."""
    if not isinstance(data, dict):
        raise ReleaseError("releases.json debe ser un objeto JSON")
    if data.get("version") != version:
        raise ReleaseError(
            f"releases.json.version={data.get('version')!r} no coincide con {version!r}"
        )
    apks = data.get("apks")
    if not isinstance(apks, dict):
        raise ReleaseError("releases.json.apks falta o no es un objeto")
    for arch in arch_keys:
        file_id = apks.get(arch)
        if not isinstance(file_id, str) or not file_id.strip():
            raise ReleaseError(f"releases.json.apks['{arch}'] falta o está vacío")
    changelog = data.get("changelog")
    if not isinstance(changelog, dict):
        raise ReleaseError("releases.json.changelog falta o no es un objeto")
    key = f"v{version}"
    if key not in changelog:
        raise ReleaseError(f"releases.json.changelog no contiene la clave {key!r}")
    validate_changelog(changelog[key], categories)


# ---------------------------------------------------------------------------
# Estado / config
# ---------------------------------------------------------------------------


def load_config() -> dict:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def load_state() -> dict:
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
    return {}


def save_state(state: dict, dry_run: bool = False) -> None:
    if dry_run:
        return
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(
        json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def update_state(dry_run: bool = False, **fields) -> dict:
    state = load_state()
    state.update(fields)
    save_state(state, dry_run)
    return state


# ---------------------------------------------------------------------------
# Ejecución de comandos
# ---------------------------------------------------------------------------


def run(cmd: list[str], check: bool = True, capture: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        text=True,
        capture_output=capture,
        check=False,
    )
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise ReleaseError(f"Falló `{' '.join(cmd)}`:\n{detail}")
    return proc


def git(*args: str, check: bool = True) -> str:
    return run(["git", *args], check=check).stdout.strip()


_DRIVE_CLIENT = None


def drive_client():
    """Cliente de Drive cacheado: OAuth de este proyecto, o `gdrive` de fallback."""
    global _DRIVE_CLIENT
    if _DRIVE_CLIENT is None:
        _DRIVE_CLIENT = resolve_client(REPO_ROOT)
    return _DRIVE_CLIENT


def drive_op(
    description: str, action, dry_run: bool, fake_fail: str | None
) -> tuple[bool, str, str]:
    """Ejecuta una operación de Drive. Devuelve (ok, mensaje, kind); nunca lanza.

    Los fallos de Drive no abortan el release: se anotan y el flujo continúa.
    `kind` es 'auth' u 'other' — los de auth no se reintentan.
    """
    if dry_run:
        return True, f"[dry-run] {description}", ""
    if fake_fail == "auth":
        return False, "simulated failure: 403 insufficient permissions", "auth"
    if fake_fail == "other":
        return False, "simulated failure: network unreachable", "other"
    try:
        action()
    except DriveError as exc:
        return False, str(exc), exc.kind
    except OSError as exc:
        return False, f"{type(exc).__name__}: {exc}", "other"
    return True, "ok", ""


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def human_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}GB"


def read_current_versions() -> tuple[str, int, str]:
    pubspec = PUBSPEC_PATH.read_text(encoding="utf-8")
    constants = CONSTANTS_PATH.read_text(encoding="utf-8")
    version, build = parse_pubspec_version(pubspec)
    return version, build, parse_constants_version(constants)


# ---------------------------------------------------------------------------
# Subcomandos
# ---------------------------------------------------------------------------


def cmd_plan(args: argparse.Namespace) -> int:
    version, build, constants_version = read_current_versions()
    assert_versions_in_sync(version, constants_version)

    if args.version:
        new_version = args.version.lstrip("v")
        version_tuple(new_version)
    else:
        new_version = next_version(version, args.bump)
    assert_version_increases(version, new_version)
    new_build = build + 1

    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    dirty = [
        line[3:] for line in git("status", "--porcelain").splitlines() if line.strip()
    ]

    since = args.since
    if not since:
        # Último commit cuyo diff tocó la línea `version:` de pubspec.yaml.
        since = git(
            "log", "-1", "--pretty=%H", "-G", r"^version: [0-9]", "--", "pubspec.yaml",
            check=False,
        )
    rev_range = f"{since}..HEAD" if since else "HEAD"

    commits = []
    raw = git("log", "--pretty=%H%x1f%s%x1f%an%x1e", rev_range, check=False)
    for record in [r for r in raw.split("\x1e") if r.strip()]:
        sha, subject, author = record.strip().split("\x1f")
        stat = git("show", "--stat", "--oneline", "--format=", sha, check=False)
        commits.append(
            {
                "sha": sha[:9],
                "subject": subject,
                "author": author,
                "stat": stat.strip().splitlines(),
            }
        )

    payload = {
        "currentVersion": version,
        "currentBuild": build,
        "nextVersion": new_version,
        "nextBuild": new_build,
        "branch": branch,
        "workingTreeDirty": bool(dirty),
        "dirtyFiles": dirty,
        "sinceCommit": since[:9] if since else None,
        "commitCount": len(commits),
        "commits": commits,
    }
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    if not commits:
        print(
            "\n# Aviso: no hay commits desde el último bump de versión. "
            "Usa --since <ref> para ampliar el rango.",
            file=sys.stderr,
        )
    return EXIT_OK


def cmd_bump(args: argparse.Namespace) -> int:
    pubspec = PUBSPEC_PATH.read_text(encoding="utf-8")
    constants = CONSTANTS_PATH.read_text(encoding="utf-8")
    version, build = parse_pubspec_version(pubspec)
    constants_version = parse_constants_version(constants)

    assert_versions_in_sync(version, constants_version)
    new_version = args.version.lstrip("v")
    version_tuple(new_version)
    assert_version_increases(version, new_version)
    new_build = build + 1
    assert_build_increases(build, new_build)

    new_pubspec = apply_pubspec_version(pubspec, new_version, new_build)
    new_constants = apply_constants_version(constants, new_version)

    # Releer lo que quedaría escrito: el bump nunca puede dejar los dos archivos
    # desincronizados.
    assert_versions_in_sync(
        parse_pubspec_version(new_pubspec)[0], parse_constants_version(new_constants)
    )

    print(f"pubspec.yaml       : {version}+{build} -> {new_version}+{new_build}")
    print(f"app_constants.dart : {constants_version} -> {new_version}")

    if args.dry_run:
        print("[dry-run] no se escribió nada")
        return EXIT_OK

    PUBSPEC_PATH.write_text(new_pubspec, encoding="utf-8")
    CONSTANTS_PATH.write_text(new_constants, encoding="utf-8")
    update_state(
        version=new_version,
        build=new_build,
        previousVersion=version,
        previousBuild=build,
        steps={**load_state().get("steps", {}), "bump": "ok"},
    )
    return EXIT_OK


def cmd_commit(args: argparse.Namespace) -> int:
    version, build, constants_version = read_current_versions()
    assert_versions_in_sync(version, constants_version)

    tracked = ["lib/core/constants/app_constants.dart", "pubspec.yaml"]
    staged = [p for p in git("diff", "--cached", "--name-only").splitlines() if p]
    unrelated = [p for p in staged if p not in tracked]
    if unrelated:
        raise ReleaseError(
            "Hay cambios ya staged que no son del bump de versión: "
            f"{unrelated}. Haz stash o commit aparte antes de releasear."
        )

    changed = [p for p in git("diff", "--name-only", *tracked).splitlines() if p]
    if not changed and not staged:
        print("No hay cambios de versión que commitear (¿ya se hizo?). Se omite.")
        update_state(steps={**load_state().get("steps", {}), "commit": "skipped"})
        return EXIT_OK

    branch = args.branch or git("rev-parse", "--abbrev-ref", "HEAD")
    if branch == "HEAD":
        raise ReleaseError("HEAD está detached: no se puede pushear. Cambia a una rama.")

    print(f"Commit en la rama '{branch}': {args.message}")
    if args.dry_run:
        print(f"[dry-run] git add {' '.join(tracked)}")
        print(f"[dry-run] git commit -m {args.message!r}")
        print(f"[dry-run] git push origin {branch}")
        return EXIT_OK

    run(["git", "add", *tracked])
    run(["git", "commit", "-m", args.message])
    sha = git("rev-parse", "--short", "HEAD")
    run(["git", "push", "origin", branch])
    print(f"Pusheado {sha} a origin/{branch}")

    update_state(
        commit=sha,
        branch=branch,
        commitMessage=args.message,
        steps={**load_state().get("steps", {}), "commit": "ok"},
    )
    return EXIT_OK


def cmd_build(args: argparse.Namespace) -> int:
    config = load_config()
    min_bytes = config.get("minApkBytes", 1_048_576)

    commands = [
        ["flutter", "build", "apk", "--release"],
        ["flutter", "build", "apk", "--release", "--split-per-abi"],
    ]
    for cmd in commands:
        print(f"$ {' '.join(cmd)}")
        if args.dry_run:
            continue
        proc = subprocess.run(cmd, cwd=REPO_ROOT, text=True, check=False)
        if proc.returncode != 0:
            # Único fallo que aborta el release.
            raise ReleaseError(
                f"El build falló (`{' '.join(cmd)}`). No se sube nada a Drive."
            )

    if args.dry_run:
        print("[dry-run] no se verifican los APKs")
        return EXIT_OK

    artifacts = {}
    problems = []
    for arch, spec in config["apks"].items():
        path = REPO_ROOT / spec["path"]
        if not path.exists():
            problems.append(f"{arch}: no se generó {spec['path']}")
            continue
        size = path.stat().st_size
        if size < min_bytes:
            # Un APK de pocos KB suele ser un HTML de error, no un APK.
            problems.append(
                f"{arch}: {spec['path']} pesa solo {human_size(size)} "
                f"(mínimo esperado {human_size(min_bytes)}) — probablemente corrupto"
            )
            continue
        artifacts[arch] = {
            "path": spec["path"],
            "bytes": size,
            "size": human_size(size),
            "sha256": sha256_of(path),
        }
        print(f"  {arch:<12} {human_size(size):>8}  {spec['path']}")

    if problems:
        raise ReleaseError("APKs inválidos tras el build:\n  - " + "\n  - ".join(problems))

    update_state(
        artifacts=artifacts, steps={**load_state().get("steps", {}), "build": "ok"}
    )
    return EXIT_OK


def cmd_upload(args: argparse.Namespace) -> int:
    config = load_config()
    state = load_state()
    uploads = dict(state.get("uploads", {}))
    degraded = False

    client = drive_client()
    print(f"Backend de Drive: {client.describe()}")

    for arch, spec in config["apks"].items():
        path = REPO_ROOT / spec["path"]
        if uploads.get(arch, {}).get("status") == "ok" and args.only_missing:
            print(f"{arch}: ya subido, se omite")
            continue
        if not path.exists() and not args.dry_run:
            uploads[arch] = {
                "status": "failed", "kind": "missing",
                "error": f"no existe {spec['path']}",
            }
            degraded = True
            print(f"{arch}: FALLÓ — no existe {spec['path']}")
            continue

        file_id = spec["fileId"]
        ok, message, kind = drive_op(
            f"update {file_id} <- {spec['path']}",
            lambda fid=file_id, p=path: client.update_file(fid, p),
            args.dry_run,
            args.fake_gdrive_fail,
        )
        if ok:
            uploads[arch] = {"status": "ok", "fileId": file_id}
            print(f"{arch}: OK (fileId {file_id} preservado)")
        else:
            uploads[arch] = {
                "status": "failed",
                "kind": kind,
                "error": message,
                "retry": "python3 scripts/release.py retry-upload",
            }
            degraded = True
            print(f"{arch}: FALLÓ ({kind}) — {message}")
            if kind == "auth":
                # Regla del skill: no reintentar, no buscar alternativas, seguir.
                print("  (fallo de permisos/autenticación: no se reintenta)")

    update_state(
        args.dry_run,
        uploads=uploads,
        driveBackend=client.name,
        steps={**state.get("steps", {}), "upload": "degraded" if degraded else "ok"},
    )
    return EXIT_DRIVE_DEGRADED if degraded else EXIT_OK


def _load_remote_releases_json(
    config: dict, dry_run: bool, fake_fail: str | None
) -> tuple[dict, str]:
    """Descarga releases.json de Drive; si falla por auth usa la copia local."""
    file_id = config["releasesJsonFileId"]
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    client = drive_client()
    # En dry-run, si ya hay copia local no se toca la red.
    skip_download = dry_run and RELEASES_JSON_PATH.exists()
    ok, message, _ = drive_op(
        f"download {file_id}",
        lambda: client.download(file_id, RELEASES_JSON_PATH),
        skip_download,
        fake_fail,
    )
    if ok and RELEASES_JSON_PATH.exists():
        return (
            json.loads(RELEASES_JSON_PATH.read_text(encoding="utf-8")),
            "copia local (dry-run, sin descargar)" if skip_download else "drive",
        )
    if RELEASES_JSON_PATH.exists():
        print(f"No se pudo descargar releases.json ({message}); se usa la copia local.")
        return json.loads(RELEASES_JSON_PATH.read_text(encoding="utf-8")), "local"
    raise ReleaseError(
        "No se pudo descargar releases.json de Drive y no hay copia local en "
        f"{RELEASES_JSON_PATH}. Error: {message}"
    )


def cmd_publish(args: argparse.Namespace) -> int:
    config = load_config()
    state = load_state()
    version = args.app_version or state.get("version")
    if not version:
        version = read_current_versions()[0]

    _, _, constants_version = read_current_versions()
    if version != constants_version:
        raise ReleaseError(
            f"La versión a publicar ({version}) no coincide con appVersion "
            f"({constants_version}). ¿Falta correr `bump`?"
        )

    entries = json.loads(Path(args.changelog).read_text(encoding="utf-8"))
    entries = validate_changelog(entries, config["changelogCategories"])

    current, source = _load_remote_releases_json(
        config, args.dry_run, args.fake_gdrive_fail
    )
    merged = merge_releases_json(current, version, entries)
    validate_releases_json(
        merged, version, list(config["apks"].keys()), config["changelogCategories"]
    )

    preserved = merged["apks"] == current.get("apks")
    print(f"releases.json (origen: {source})")
    print(f"  version : {current.get('version')} -> {merged['version']}")
    print(f"  apks    : {'sin cambios (IDs preservados)' if preserved else 'MODIFICADO'}")
    print(f"  changelog: se añade v{version} con {len(entries)} ítem(s); "
          f"{len(current.get('changelog', {}))} entrada(s) previa(s) intactas")

    payload = json.dumps(merged, indent=2, ensure_ascii=False) + "\n"
    if args.dry_run:
        print("--- releases.json propuesto ---")
        print(payload)
        return EXIT_OK

    RELEASES_JSON_PATH.write_text(payload, encoding="utf-8")
    # Releer del disco: lo que se sube tiene que ser JSON válido, sin excusas.
    json.loads(RELEASES_JSON_PATH.read_text(encoding="utf-8"))

    file_id = config["releasesJsonFileId"]
    client = drive_client()
    ok, message, kind = drive_op(
        f"update {file_id} <- {RELEASES_JSON_PATH}",
        lambda: client.update_file(file_id, RELEASES_JSON_PATH),
        False,
        args.fake_gdrive_fail,
    )
    if ok:
        print(f"releases.json subido in-place (fileId {file_id})")
        update_state(
            releasesJson={"status": "ok", "path": str(RELEASES_JSON_PATH)},
            steps={**state.get("steps", {}), "publish": "ok"},
        )
        return EXIT_OK

    print(f"releases.json: FALLÓ ({kind}) — {message}")
    print(f"  El archivo válido quedó en {RELEASES_JSON_PATH}")
    update_state(
        releasesJson={
            "status": "failed",
            "kind": kind,
            "error": message,
            "path": str(RELEASES_JSON_PATH),
            "retry": "python3 scripts/release.py retry-upload",
        },
        steps={**state.get("steps", {}), "publish": "degraded"},
    )
    return EXIT_DRIVE_DEGRADED


def cmd_retry_upload(args: argparse.Namespace) -> int:
    """Reintenta solo lo de Drive, sin rehacer bump/commit/build."""
    config = load_config()
    state = load_state()
    if not state:
        raise ReleaseError(
            f"No hay estado de release en {STATE_PATH}. Corre el flujo completo."
        )

    upload_args = argparse.Namespace(
        dry_run=args.dry_run,
        fake_gdrive_fail=args.fake_gdrive_fail,
        only_missing=True,
    )
    code = cmd_upload(upload_args)

    releases = state.get("releasesJson", {})
    if releases.get("status") == "ok":
        print("releases.json: ya estaba subido, se omite")
        return code

    path = Path(releases.get("path") or RELEASES_JSON_PATH)
    if not path.exists():
        raise ReleaseError(
            f"No hay un releases.json local en {path}. Vuelve a correr `publish`."
        )
    data = json.loads(path.read_text(encoding="utf-8"))
    validate_releases_json(
        data,
        data.get("version", ""),
        list(config["apks"].keys()),
        config["changelogCategories"],
    )
    file_id = config["releasesJsonFileId"]
    client = drive_client()
    ok, message, kind = drive_op(
        f"update {file_id} <- {path}",
        lambda: client.update_file(file_id, path),
        args.dry_run,
        args.fake_gdrive_fail,
    )
    if ok:
        print("releases.json subido in-place")
        update_state(args.dry_run, releasesJson={"status": "ok", "path": str(path)})
        return code
    print(f"releases.json: FALLÓ ({kind}) — {message}")
    update_state(
        args.dry_run,
        releasesJson={
            "status": "failed", "kind": kind, "error": message,
            "path": str(path), "retry": "python3 scripts/release.py retry-upload",
        },
    )
    return EXIT_DRIVE_DEGRADED


def cmd_auth_login(args: argparse.Namespace) -> int:
    """Autoriza el acceso a tu Google Drive. Interactivo: lo corre una persona."""
    env = drive_env(REPO_ROOT)
    client_id = env.get("GDRIVE_CLIENT_ID")
    client_secret = env.get("GDRIVE_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise ReleaseError(
            "Faltan GDRIVE_CLIENT_ID y/o GDRIVE_CLIENT_SECRET en .env.local.\n"
            "Créalos en Google Cloud Console como cliente OAuth de tipo "
            "'Desktop app' y ponlos ahí:\n"
            "    cp .env.local.example .env.local"
        )
    if not sys.stdin.isatty() and not args.force:
        raise ReleaseError(
            "`auth-login` abre un navegador y requiere una persona delante.\n"
            "Córrelo tú en una terminal interactiva:\n"
            "    python3 scripts/release.py auth-login"
        )

    tokens = run_consent_flow(client_id, client_secret)
    refresh_token = tokens["refresh_token"]

    # Identifica la cuenta autorizada y guárdala: en una máquina con varias
    # cuentas de Google, esto evita publicar desde la equivocada.
    client = UserOAuthClient(client_id, client_secret, refresh_token)
    try:
        email = client.whoami()
    except DriveError:
        email = ""

    values = {"GDRIVE_REFRESH_TOKEN": refresh_token}
    if email:
        values["GDRIVE_ACCOUNT_EMAIL"] = email
    path = write_env_vars(REPO_ROOT, values)

    print(f"\n✅ Autorizado como: {email or '(no se pudo leer el email)'}")
    print(f"   Refresh token guardado en {path} (permisos 600).")
    print("   Es por-proyecto: solo aplica a este repo. No lo commitees.")
    print("\nComprueba el acceso con:  python3 scripts/release.py auth-check")
    return EXIT_OK


def cmd_auth_check(args: argparse.Namespace) -> int:
    """Verifica el acceso a Drive ANTES de gastar media hora en un release."""
    config = load_config()
    try:
        client = drive_client()
    except DriveError as exc:
        raise ReleaseError(f"No se pudieron cargar las credenciales: {exc}") from exc

    print(f"Backend  : {client.describe()}")
    if client.name == "gdrive-cli":
        print(
            "Aviso    : este proyecto no tiene credenciales OAuth propias; se usa el\n"
            "           binario `gdrive`. Autoriza tu cuenta con:\n"
            "               python3 scripts/release.py auth-login"
        )
    else:
        # Con varias cuentas de Google en la máquina, confirma cuál está activa
        # aquí antes de publicar.
        try:
            live = client.whoami()
        except DriveError as exc:
            print(f"Cuenta   : no se pudo verificar ({exc.kind})")
            live = ""
        if live:
            print(f"Cuenta   : {live}")
            if client.account_email and live != client.account_email:
                print(
                    f"           ⚠️  .env.local dice {client.account_email}. "
                    "Vuelve a correr auth-login si no es la que quieres."
                )

    targets = [("releases.json", config["releasesJsonFileId"])]
    targets += [(arch, spec["fileId"]) for arch, spec in config["apks"].items()]

    failures = 0
    for label, file_id in targets:
        try:
            meta = client.get_metadata(file_id)
        except DriveError as exc:
            failures += 1
            print(f"  {label:<14} FALLÓ ({exc.kind}) — {exc}")
            if exc.kind == "auth":
                # Si la credencial no sirve, no sirve para ninguno: no repitas
                # el mismo fallo (y su timeout) una vez por archivo.
                remaining = len(targets) - targets.index((label, file_id)) - 1
                if remaining:
                    print(
                        f"  {'':<14} (se omiten {remaining} archivo(s): "
                        "la credencial no es válida)"
                    )
                break
            continue
        if "raw" in meta:  # gdrive CLI: no devuelve JSON estructurado
            print(f"  {label:<14} OK")
            continue
        can_edit = (meta.get("capabilities") or {}).get("canEdit")
        size = meta.get("size")
        detail = f"{meta.get('name')} ({human_size(int(size))})" if size else meta.get("name")
        if can_edit is False:
            failures += 1
            print(f"  {label:<14} SIN PERMISO DE EDICIÓN — {detail}")
        else:
            print(f"  {label:<14} OK, editable — {detail}")

    if failures:
        print(
            f"\n⚠️  {failures} archivo(s) inaccesible(s).\n"
            "Autoriza (o reautoriza) tu cuenta de Google con:\n"
            "    python3 scripts/release.py auth-login\n"
            "y confirma que esa cuenta puede editar la carpeta:\n"
            f"    https://drive.google.com/drive/folders/{config['driveFolderId']}"
        )
        return EXIT_DRIVE_DEGRADED
    print("\nTodo accesible y editable. El release puede publicar sin intervención.")
    return EXIT_OK


def cmd_report(args: argparse.Namespace) -> int:
    state = load_state()
    if not state:
        print(f"No hay estado de release en {STATE_PATH}", file=sys.stderr)
        return EXIT_HARD_FAIL

    failures = []
    for arch, info in (state.get("uploads") or {}).items():
        if info.get("status") != "ok":
            failures.append((f"APK {arch}", info))
    releases = state.get("releasesJson") or {}
    if releases and releases.get("status") != "ok":
        failures.append(("releases.json", releases))

    payload = {**state, "driveFailures": [name for name, _ in failures]}
    if args.json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return EXIT_DRIVE_DEGRADED if failures else EXIT_OK

    print(f"Versión    : {state.get('version')}+{state.get('build')}")
    print(f"Commit     : {state.get('commit')} en {state.get('branch')}")
    if state.get("commitMessage"):
        print(f"             {state['commitMessage']}")
    print("APKs       :")
    for arch, info in (state.get("artifacts") or {}).items():
        status = (state.get("uploads") or {}).get(arch, {}).get("status", "-")
        print(f"  {arch:<12} {info['size']:>8}  drive={status}")
    print(f"releases.json: {releases.get('status', '-')}")

    if failures:
        print("\n⚠️  FALLOS DE DRIVE — la versión NO está publicada para los usuarios.")
        for name, info in failures:
            print(f"  - {name} ({info.get('kind')}): {info.get('error')}")
        print("\nDiagnóstico y reintento (tras restablecer el acceso):")
        print("  python3 scripts/release.py auth-check")
        if state.get("driveBackend") == "gdrive-cli":
            print("  python3 scripts/release.py auth-login   # autoriza tu cuenta")
        else:
            print("  python3 scripts/release.py auth-login   # si el token caducó")
        print("  python3 scripts/release.py retry-upload")
        print("\nNunca borres y vuelvas a subir los archivos: los fileId deben preservarse.")
        return EXIT_DRIVE_DEGRADED
    return EXIT_OK


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="release.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="command", required=True)

    def add_common(p, drive: bool = False):
        p.add_argument("--dry-run", action="store_true", help="no escribe ni sube nada")
        if drive:
            p.add_argument(
                "--fake-gdrive-fail",
                choices=("auth", "other"),
                help="simula un fallo de gdrive (para probar el camino degradado)",
            )
        return p

    p = sub.add_parser("plan", help="reporta versión siguiente y commits sin releasear")
    p.add_argument("--version", help="versión explícita X.Y.Z")
    p.add_argument("--bump", choices=("patch", "minor", "major"), default="patch")
    p.add_argument("--since", help="ref desde la que listar commits")
    p.set_defaults(func=cmd_plan)

    p = add_common(sub.add_parser("bump", help="sube la versión en los dos archivos"))
    p.add_argument("--version", required=True)
    p.set_defaults(func=cmd_bump)

    p = add_common(sub.add_parser("commit", help="commitea y pushea el bump"))
    p.add_argument("--message", required=True)
    p.add_argument("--branch", help="rama destino (por defecto, la actual)")
    p.set_defaults(func=cmd_commit)

    p = add_common(sub.add_parser("build", help="compila los APKs de release"))
    p.set_defaults(func=cmd_build)

    p = add_common(sub.add_parser("upload", help="sube los APKs a Drive in-place"), drive=True)
    p.add_argument(
        "--only-missing", action="store_true", help="omite los que ya se subieron"
    )
    p.set_defaults(func=cmd_upload)

    p = add_common(sub.add_parser("publish", help="actualiza y sube releases.json"), drive=True)
    p.add_argument("--changelog", required=True, help="ruta al changelog.json")
    p.add_argument("--app-version", help="versión a publicar (por defecto, la del estado)")
    p.set_defaults(func=cmd_publish)

    p = add_common(sub.add_parser("retry-upload", help="reintenta solo Drive"), drive=True)
    p.set_defaults(func=cmd_retry_upload)

    p = sub.add_parser(
        "auth-login",
        help="autoriza tu cuenta de Google en el navegador (una sola vez)",
    )
    p.add_argument(
        "--force", action="store_true", help="permitir sin TTY (no recomendado)"
    )
    p.set_defaults(func=cmd_auth_login)

    p = sub.add_parser(
        "auth-check", help="verifica credenciales y acceso a los archivos de Drive"
    )
    p.set_defaults(func=cmd_auth_check)

    p = sub.add_parser("report", help="resumen del release")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_report)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not hasattr(args, "fake_gdrive_fail"):
        args.fake_gdrive_fail = None
    if not hasattr(args, "dry_run"):
        args.dry_run = False
    try:
        return args.func(args)
    except ReleaseError as exc:
        print(f"\n❌ {exc}", file=sys.stderr)
        return EXIT_HARD_FAIL


if __name__ == "__main__":
    sys.exit(main())
