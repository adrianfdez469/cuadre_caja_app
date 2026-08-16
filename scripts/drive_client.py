#!/usr/bin/env python3
"""Acceso a Google Drive para el pipeline de release.

Autenticación por **OAuth de usuario**: el script actúa como tu propia cuenta de
Google. Requiere UNA autorización en el navegador (`release.py auth-login`); a
partir de ahí funciona sola con el refresh token guardado.

Las credenciales se leen del entorno o de `.env.local` **en la raíz de este
repo** — es decir, son por-proyecto. Si trabajas con varias cuentas de Google en
la misma máquina, cada repo tiene su propio token y no se pisan:

    GDRIVE_CLIENT_ID=...            # cliente OAuth de tipo "Desktop app"
    GDRIVE_CLIENT_SECRET=...
    GDRIVE_REFRESH_TOKEN=...        # lo escribe `auth-login`
    GDRIVE_ACCOUNT_EMAIL=...        # informativo, lo escribe `auth-login`

Si no hay nada configurado se cae al binario `gdrive` (el flujo histórico).

Nota sobre caducidad: mientras el cliente OAuth esté en modo "Testing" en Google
Cloud Console, Google revoca el refresh token a los 7 días. Con la app publicada
("In production") el token dura hasta que se revoque a mano.

Nada de esto imprime nunca el client secret, el refresh token ni el access token.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DRIVE_SCOPE = "https://www.googleapis.com/auth/drive"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
API_BASE = "https://www.googleapis.com/drive/v3"
UPLOAD_BASE = "https://www.googleapis.com/upload/drive/v3"

ENV_KEYS = (
    "GDRIVE_CLIENT_ID",
    "GDRIVE_CLIENT_SECRET",
    "GDRIVE_REFRESH_TOKEN",
    "GDRIVE_ACCOUNT_EMAIL",
)

# Errores de Drive con código 403 que NO son de permisos, y por tanto no deben
# tratarse como "fallo de auth, no reintentar".
NON_AUTH_403_REASONS = {"storageQuotaExceeded", "rateLimitExceeded", "userRateLimitExceeded"}


class DriveError(Exception):
    """Fallo al hablar con Drive. `kind` es 'auth' u 'other'."""

    def __init__(self, message: str, kind: str = "other"):
        super().__init__(message)
        self.kind = kind


# ---------------------------------------------------------------------------
# .env.local (por proyecto)
# ---------------------------------------------------------------------------


def parse_env_file(text: str) -> dict[str, str]:
    """Parser mínimo de .env: KEY=VALUE, con `export`, comillas y `#` opcionales."""
    values: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        elif " #" in value:
            value = value.split(" #", 1)[0].strip()
        if key:
            values[key] = value
    return values


def env_path(repo_root: Path) -> Path:
    return repo_root / ".env.local"


def load_env(repo_root: Path) -> dict[str, str]:
    """Variables de `.env.local` de ESTE repo, mezcladas con las del entorno.

    El entorno real gana, para poder sobreescribir puntualmente sin editar nada.
    """
    values: dict[str, str] = {}
    path = env_path(repo_root)
    if path.exists():
        values.update(parse_env_file(path.read_text(encoding="utf-8")))
    for key in ENV_KEYS:
        if os.environ.get(key):
            values[key] = os.environ[key]
    return values


def upsert_env_var(text: str, key: str, value: str) -> str:
    """Escribe KEY=value en un .env, reemplazando la línea si ya existía."""
    lines = text.splitlines()
    replaced = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        candidate = (
            stripped[len("export "):].strip()
            if stripped.startswith("export ")
            else stripped
        )
        if candidate.split("=", 1)[0].strip() == key:
            lines[i] = f"{key}={value}"
            replaced = True
            break
    if not replaced:
        lines.append(f"{key}={value}")
    return "\n".join(lines) + "\n"


def write_env_vars(repo_root: Path, values: dict[str, str]) -> Path:
    """Guarda variables en `.env.local` con permisos 600, preservando el resto."""
    path = env_path(repo_root)
    content = path.read_text(encoding="utf-8") if path.exists() else ""
    for key, value in values.items():
        content = upsert_env_var(content, key, value)
    path.write_text(content, encoding="utf-8")
    os.chmod(path, 0o600)
    return path


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------


def classify_http_error(status: int, body: str) -> str:
    """'auth' u 'other' a partir de una respuesta de error de Google."""
    # El endpoint de token responde 400 (no 401) cuando la credencial está muerta:
    # {"error":"invalid_grant"}. Sin esto se trataría como fallo transitorio.
    low = (body or "").lower()
    if any(
        code in low
        for code in ("invalid_grant", "invalid_client", "unauthorized_client")
    ):
        return "auth"
    if status == 401:
        return "auth"
    if status == 403:
        reason = ""
        try:
            payload = json.loads(body)
            errors = payload.get("error", {}).get("errors") or []
            if errors:
                reason = errors[0].get("reason", "")
            reason = reason or payload.get("error", {}).get("status", "")
        except (json.JSONDecodeError, AttributeError):
            pass
        if reason in NON_AUTH_403_REASONS:
            return "other"
        return "auth"
    return "other"


def _request(req: urllib.request.Request, timeout: int = 900):
    try:
        return urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        kind = classify_http_error(exc.code, body)
        raise DriveError(f"HTTP {exc.code}: {body.strip()[:400]}", kind) from exc
    except urllib.error.URLError as exc:
        raise DriveError(f"Error de red hablando con Drive: {exc.reason}") from exc


# ---------------------------------------------------------------------------
# Cliente OAuth de usuario
# ---------------------------------------------------------------------------


class UserOAuthClient:
    """Actúa como tu cuenta de Google. Sube siempre in-place, por fileId."""

    name = "user-oauth"

    def __init__(
        self,
        client_id: str,
        client_secret: str,
        refresh_token: str,
        account_email: str = "",
    ):
        self._client_id = client_id
        self._client_secret = client_secret
        self._refresh_token = refresh_token
        self.account_email = account_email
        self._token: str | None = None
        self._token_expiry = 0.0

    def describe(self) -> str:
        who = self.account_email or "cuenta sin identificar (corre auth-login)"
        return f"OAuth de usuario — {who}"

    def _fetch_token(self) -> tuple[str, int]:
        data = urllib.parse.urlencode(
            {
                "client_id": self._client_id,
                "client_secret": self._client_secret,
                "refresh_token": self._refresh_token,
                "grant_type": "refresh_token",
            }
        ).encode()
        req = urllib.request.Request(TOKEN_URL, data=data, method="POST")
        try:
            with _request(req, timeout=60) as resp:
                body = json.load(resp)
        except DriveError as exc:
            if exc.kind == "auth":
                raise DriveError(
                    f"{exc}\n"
                    "El refresh token ya no sirve. Vuelve a autorizar con:\n"
                    "    python3 scripts/release.py auth-login\n"
                    "Si esto se repite cada 7 días, el cliente OAuth sigue en modo "
                    "'Testing' en Google Cloud Console: publícalo (OAuth consent "
                    "screen -> Publish app).",
                    "auth",
                ) from exc
            raise
        return body["access_token"], int(body.get("expires_in", 3600))

    def _access_token(self) -> str:
        if self._token and time.time() < self._token_expiry - 60:
            return self._token
        token, expires_in = self._fetch_token()
        self._token = token
        self._token_expiry = time.time() + expires_in
        return token

    def _auth_header(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self._access_token()}"}

    def whoami(self) -> str:
        """Email de la cuenta autorizada — para no publicar con la cuenta equivocada."""
        req = urllib.request.Request(
            f"{API_BASE}/about?fields=user(emailAddress)", headers=self._auth_header()
        )
        with _request(req, timeout=60) as resp:
            return json.load(resp).get("user", {}).get("emailAddress", "")

    def get_metadata(self, file_id: str) -> dict:
        url = (
            f"{API_BASE}/files/{file_id}"
            "?fields=id,name,size,modifiedTime,mimeType,capabilities(canEdit)"
        )
        req = urllib.request.Request(url, headers=self._auth_header())
        with _request(req, timeout=60) as resp:
            return json.load(resp)

    def download(self, file_id: str, destination: Path) -> None:
        url = f"{API_BASE}/files/{file_id}?alt=media"
        req = urllib.request.Request(url, headers=self._auth_header())
        with _request(req) as resp:
            destination.write_bytes(resp.read())

    def update_file(self, file_id: str, path: Path) -> None:
        """Reemplaza el CONTENIDO del archivo, preservando su fileId.

        Upload resumable: los APKs pesan decenas de MB y el upload simple no es
        fiable a ese tamaño.
        """
        size = path.stat().st_size
        start = urllib.request.Request(
            f"{UPLOAD_BASE}/files/{file_id}?uploadType=resumable",
            data=b"{}",
            method="PATCH",
            headers={
                **self._auth_header(),
                "Content-Type": "application/json; charset=UTF-8",
                "X-Upload-Content-Length": str(size),
                "X-Upload-Content-Type": "application/octet-stream",
            },
        )
        with _request(start, timeout=120) as resp:
            session_url = resp.headers.get("Location")
        if not session_url:
            raise DriveError("Drive no devolvió la URL de sesión del upload resumable")

        with path.open("rb") as fh:
            upload = urllib.request.Request(
                session_url,
                data=fh,
                method="PUT",
                headers={
                    "Content-Length": str(size),
                    "Content-Type": "application/octet-stream",
                },
            )
            with _request(upload) as resp:
                resp.read()


# ---------------------------------------------------------------------------
# Fallback: el binario `gdrive`
# ---------------------------------------------------------------------------


class GdriveCliClient:
    """El comportamiento histórico, si no hay credenciales OAuth configuradas."""

    name = "gdrive-cli"
    account_email = ""

    def describe(self) -> str:
        return "binario `gdrive` (fallback)"

    def whoami(self) -> str:
        return ""

    def _run(
        self, args: list[str], timeout: int = 900, timeout_is_auth: bool = False
    ) -> str:
        try:
            proc = subprocess.run(
                ["gdrive", *args], capture_output=True, text=True, check=False, timeout=timeout
            )
        except FileNotFoundError as exc:
            raise DriveError("`gdrive` no está instalado o no está en el PATH") from exc
        except subprocess.TimeoutExpired as exc:
            # Con el token caducado, `gdrive` no falla: se queda esperando el flujo
            # de navegador. En una llamada barata (metadatos) un timeout significa
            # justamente eso, así que se trata como fallo de credenciales.
            raise DriveError(
                f"timeout de {timeout}s ejecutando `gdrive {' '.join(args)}` — "
                "probablemente esperando la autenticación por navegador",
                "auth" if timeout_is_auth else "other",
            ) from exc
        if proc.returncode != 0:
            message = (proc.stderr or proc.stdout or "error desconocido").strip()
            kind = "auth" if _looks_like_auth(message) else "other"
            raise DriveError(message, kind)
        return proc.stdout

    def get_metadata(self, file_id: str) -> dict:
        # Timeout corto: con el token caducado, `gdrive` se cuelga esperando el
        # flujo de navegador en vez de fallar.
        return {
            "raw": self._run(
                ["files", "info", file_id], timeout=30, timeout_is_auth=True
            )
        }

    def download(self, file_id: str, destination: Path) -> None:
        self._run(
            [
                "files", "download", file_id,
                "--destination", str(destination.parent), "--overwrite",
            ]
        )

    def update_file(self, file_id: str, path: Path) -> None:
        self._run(["files", "update", file_id, str(path)])


# Patrones del binario `gdrive`. Incluye "token retrieval": con el token caducado,
# gdrive intenta levantar un listener OAuth y falla por el puerto, no por la red.
_AUTH_PATTERNS = (
    "401", "403", "invalid_grant", "unauthorized", "insufficient permissions",
    "no accounts", "permission denied", "access_denied", "token expired",
    "credentials", "not authenticated", "token retrieval", "refresh token", "oauth",
)


def _looks_like_auth(message: str) -> bool:
    low = (message or "").lower()
    return any(p in low for p in _AUTH_PATTERNS)


# ---------------------------------------------------------------------------
# Consentimiento por navegador (una sola vez)
# ---------------------------------------------------------------------------


def build_auth_url(client_id: str, redirect_uri: str, state: str) -> str:
    """URL de consentimiento.

    `access_type=offline` + `prompt=consent` son obligatorios: sin ellos Google
    devuelve un access token de una hora y NINGÚN refresh token, así que habría
    que pasar por el navegador en cada release.
    """
    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": DRIVE_SCOPE,
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
    }
    return f"{AUTH_URL}?{urllib.parse.urlencode(params)}"


def exchange_code(
    client_id: str, client_secret: str, code: str, redirect_uri: str
) -> dict:
    data = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "code": code,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        }
    ).encode()
    req = urllib.request.Request(TOKEN_URL, data=data, method="POST")
    with _request(req, timeout=120) as resp:
        return json.load(resp)


_CONSENT_PAGE = (
    "<!doctype html><meta charset=utf-8>"
    "<title>Autorización</title>"
    "<body style='font-family:system-ui;padding:3rem;text-align:center'>"
    "<h2>{title}</h2><p>{body}</p></body>"
)


def run_consent_flow(client_id: str, client_secret: str, timeout: int = 300) -> dict:
    """Levanta un servidor local, abre el navegador y captura el código.

    Devuelve la respuesta del token endpoint (incluye `refresh_token`). El
    servidor escucha SOLO en 127.0.0.1 y en un puerto libre elegido por el SO —
    los clientes OAuth de tipo *Desktop app* aceptan cualquier puerto de loopback.
    """
    import http.server
    import secrets
    import threading
    import webbrowser

    state = secrets.token_urlsafe(24)
    captured: dict[str, str] = {}
    done = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            title, body = "Algo salió mal", "Puedes cerrar esta pestaña."
            if query.get("state", [""])[0] != state:
                # Protege contra que otra página del navegador dispare el callback.
                captured["error"] = "state no coincide (posible CSRF)"
            elif "error" in query:
                captured["error"] = query["error"][0]
            elif "code" in query:
                captured["code"] = query["code"][0]
                title = "✅ Listo"
                body = "Ya puedes volver a la terminal y cerrar esta pestaña."
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(_CONSENT_PAGE.format(title=title, body=body).encode())
            done.set()

        def log_message(self, *args):  # silencia el log del servidor
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    redirect_uri = f"http://127.0.0.1:{server.server_port}"
    url = build_auth_url(client_id, redirect_uri, state)

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print("Abriendo el navegador para autorizar el acceso a tu Google Drive.")
    print("Elige la cuenta correcta para ESTE proyecto.")
    print("Si no se abre solo, pega esta URL en el navegador:\n")
    print(f"  {url}\n")
    try:
        webbrowser.open(url)
    except Exception:
        pass

    try:
        if not done.wait(timeout):
            raise DriveError(
                f"Nadie completó la autorización en {timeout}s. Reintenta.", "auth"
            )
    finally:
        server.shutdown()

    if "error" in captured:
        raise DriveError(f"Autorización rechazada: {captured['error']}", "auth")

    tokens = exchange_code(client_id, client_secret, captured["code"], redirect_uri)
    if not tokens.get("refresh_token"):
        raise DriveError(
            "Google no devolvió refresh_token. Revoca el acceso de la app en "
            "https://myaccount.google.com/permissions y reintenta.",
            "auth",
        )
    return tokens


def resolve_client(repo_root: Path):
    """Cliente OAuth si este proyecto tiene credenciales; si no, `gdrive`."""
    env = load_env(repo_root)
    if env.get("GDRIVE_CLIENT_ID") and env.get("GDRIVE_REFRESH_TOKEN"):
        return UserOAuthClient(
            env["GDRIVE_CLIENT_ID"],
            env.get("GDRIVE_CLIENT_SECRET", ""),
            env["GDRIVE_REFRESH_TOKEN"],
            env.get("GDRIVE_ACCOUNT_EMAIL", ""),
        )
    return GdriveCliClient()
