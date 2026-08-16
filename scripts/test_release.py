#!/usr/bin/env python3
"""Tests de la lógica que puede romper producción.

Correr con:  python3 scripts/test_release.py
"""

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import drive_client  # noqa: E402
import release  # noqa: E402

CATEGORIES = ["Mejoras", "Arreglos", "Caracteristicas"]
ARCHS = ["arm64-v8a", "armeabi-v7a", "x86_64", "universal"]

BASE_RELEASES = {
    "version": "1.1.13",
    "apks": {
        "arm64-v8a": "ID_ARM64",
        "armeabi-v7a": "ID_ARMV7",
        "x86_64": "ID_X8664",
        "universal": "ID_UNIVERSAL",
    },
    "changelog": {
        "v1.1.13": [{"Mejoras": "Carrito integrado en el escáner"}],
        "v1.1.12": [{"Mejoras": "Nuevo icono de la app"}],
    },
}


class TestVersionParsing(unittest.TestCase):
    def test_parse_pubspec_version(self):
        text = "name: cuadre_caja_app\nversion: 1.1.13+24\n\nenvironment:\n"
        self.assertEqual(release.parse_pubspec_version(text), ("1.1.13", 24))

    def test_parse_pubspec_version_missing(self):
        with self.assertRaises(release.ReleaseError):
            release.parse_pubspec_version("name: foo\n")

    def test_parse_constants_version(self):
        text = "  static const String appVersion = '1.1.13';\n"
        self.assertEqual(release.parse_constants_version(text), "1.1.13")

    def test_apply_pubspec_version(self):
        text = "version: 1.1.13+24\n"
        self.assertEqual(
            release.apply_pubspec_version(text, "1.1.14", 25), "version: 1.1.14+25\n"
        )

    def test_apply_constants_version(self):
        text = "  static const String appVersion = '1.1.13';\n"
        self.assertEqual(
            release.apply_constants_version(text, "1.1.14"),
            "  static const String appVersion = '1.1.14';\n",
        )

    def test_next_version(self):
        self.assertEqual(release.next_version("1.1.13"), "1.1.14")
        self.assertEqual(release.next_version("1.1.13", "minor"), "1.2.0")
        self.assertEqual(release.next_version("1.1.13", "major"), "2.0.0")


class TestVersionAsserts(unittest.TestCase):
    def test_sync_ok(self):
        release.assert_versions_in_sync("1.1.13", "1.1.13")

    def test_sync_mismatch(self):
        with self.assertRaises(release.ReleaseError):
            release.assert_versions_in_sync("1.1.13", "1.1.12")

    def test_version_must_increase(self):
        release.assert_version_increases("1.1.13", "1.1.14")
        release.assert_version_increases("1.1.13", "1.2.0")
        with self.assertRaises(release.ReleaseError):
            release.assert_version_increases("1.1.13", "1.1.13")
        with self.assertRaises(release.ReleaseError):
            release.assert_version_increases("1.1.13", "1.1.12")

    def test_build_must_increase(self):
        release.assert_build_increases(24, 25)
        with self.assertRaises(release.ReleaseError):
            release.assert_build_increases(24, 24)
        with self.assertRaises(release.ReleaseError):
            release.assert_build_increases(24, 23)


class TestChangelogValidation(unittest.TestCase):
    def test_valid(self):
        entries = [{"Arreglos": "Se arregla algo"}, {"Mejoras": "Algo mejor"}]
        self.assertEqual(release.validate_changelog(entries, CATEGORIES), entries)

    def test_empty_rejected(self):
        with self.assertRaises(release.ReleaseError):
            release.validate_changelog([], CATEGORIES)

    def test_bad_category(self):
        with self.assertRaises(release.ReleaseError):
            release.validate_changelog([{"mejora": "minúscula y singular"}], CATEGORIES)

    def test_multi_key_item(self):
        with self.assertRaises(release.ReleaseError):
            release.validate_changelog([{"Mejoras": "a", "Arreglos": "b"}], CATEGORIES)

    def test_empty_text(self):
        with self.assertRaises(release.ReleaseError):
            release.validate_changelog([{"Mejoras": "   "}], CATEGORIES)


class TestMergeReleasesJson(unittest.TestCase):
    def setUp(self):
        self.entries = [{"Arreglos": "Se arregla la sincronización offline"}]

    def test_version_updated(self):
        merged = release.merge_releases_json(BASE_RELEASES, "1.1.14", self.entries)
        self.assertEqual(merged["version"], "1.1.14")

    def test_apks_untouched(self):
        merged = release.merge_releases_json(BASE_RELEASES, "1.1.14", self.entries)
        self.assertEqual(merged["apks"], BASE_RELEASES["apks"])

    def test_old_changelog_preserved(self):
        merged = release.merge_releases_json(BASE_RELEASES, "1.1.14", self.entries)
        self.assertEqual(
            merged["changelog"]["v1.1.13"], BASE_RELEASES["changelog"]["v1.1.13"]
        )
        self.assertEqual(
            merged["changelog"]["v1.1.12"], BASE_RELEASES["changelog"]["v1.1.12"]
        )
        self.assertEqual(merged["changelog"]["v1.1.14"], self.entries)

    def test_new_entry_first(self):
        merged = release.merge_releases_json(BASE_RELEASES, "1.1.14", self.entries)
        self.assertEqual(list(merged["changelog"])[0], "v1.1.14")

    def test_does_not_mutate_input(self):
        original = {
            "version": BASE_RELEASES["version"],
            "apks": dict(BASE_RELEASES["apks"]),
            "changelog": {k: list(v) for k, v in BASE_RELEASES["changelog"].items()},
        }
        release.merge_releases_json(BASE_RELEASES, "1.1.14", self.entries)
        self.assertEqual(BASE_RELEASES, original)

    def test_idempotent(self):
        once = release.merge_releases_json(BASE_RELEASES, "1.1.14", self.entries)
        twice = release.merge_releases_json(once, "1.1.14", self.entries)
        self.assertEqual(once, twice)

    def test_explicit_apk_ids_merge_not_replace(self):
        merged = release.merge_releases_json(
            BASE_RELEASES, "1.1.14", self.entries, {"x86_64": "NUEVO_ID"}
        )
        self.assertEqual(merged["apks"]["x86_64"], "NUEVO_ID")
        self.assertEqual(merged["apks"]["arm64-v8a"], "ID_ARM64")


class TestValidateReleasesJson(unittest.TestCase):
    def merged(self):
        return release.merge_releases_json(
            BASE_RELEASES, "1.1.14", [{"Mejoras": "Algo"}]
        )

    def test_valid(self):
        release.validate_releases_json(self.merged(), "1.1.14", ARCHS, CATEGORIES)

    def test_version_mismatch(self):
        with self.assertRaises(release.ReleaseError):
            release.validate_releases_json(self.merged(), "1.1.15", ARCHS, CATEGORIES)

    def test_missing_arch(self):
        data = self.merged()
        del data["apks"]["x86_64"]
        with self.assertRaises(release.ReleaseError):
            release.validate_releases_json(data, "1.1.14", ARCHS, CATEGORIES)

    def test_empty_arch_id(self):
        data = self.merged()
        data["apks"]["universal"] = ""
        with self.assertRaises(release.ReleaseError):
            release.validate_releases_json(data, "1.1.14", ARCHS, CATEGORIES)

    def test_missing_changelog_key(self):
        data = self.merged()
        del data["changelog"]["v1.1.14"]
        with self.assertRaises(release.ReleaseError):
            release.validate_releases_json(data, "1.1.14", ARCHS, CATEGORIES)


class TestAuthErrorClassification(unittest.TestCase):
    def test_auth_errors(self):
        for msg in (
            "Error: 403 insufficient permissions",
            "invalid_grant: token has been expired or revoked",
            "HTTP 401 Unauthorized",
            "no accounts found, run `gdrive account add`",
            # Caso real observado: token caducado -> gdrive intenta abrir el
            # listener de OAuth y falla por el puerto, no por la red.
            "Error: Failed getting file: Token retrieval failed: error creating "
            "server listener: Address already in use (os error 48)",
        ):
            self.assertTrue(release.is_auth_error(msg), msg)

    def test_non_auth_errors(self):
        for msg in (
            "no such file or directory: build/app/outputs/flutter-apk/app-release.apk",
            "network unreachable",
            "",
        ):
            self.assertFalse(release.is_auth_error(msg), msg)


class TestEnvParsing(unittest.TestCase):
    def test_basic(self):
        text = "GDRIVE_CLIENT_ID=cid.apps.googleusercontent.com\n"
        self.assertEqual(
            drive_client.parse_env_file(text),
            {"GDRIVE_CLIENT_ID": "cid.apps.googleusercontent.com"},
        )

    def test_comments_blanks_and_export(self):
        text = "\n# comentario\nexport FOO=bar\n\nBAZ=qux # al final\n"
        self.assertEqual(
            drive_client.parse_env_file(text), {"FOO": "bar", "BAZ": "qux"}
        )

    def test_quotes_stripped(self):
        text = "A=\"con espacios\"\nB='simple'\n"
        self.assertEqual(
            drive_client.parse_env_file(text), {"A": "con espacios", "B": "simple"}
        )

    def test_value_with_equals_and_json(self):
        # Un refresh token puede contener "=" y "/": no debe truncarse.
        text = "GDRIVE_REFRESH_TOKEN=1//abc==def/ghi\n"
        self.assertEqual(
            drive_client.parse_env_file(text),
            {"GDRIVE_REFRESH_TOKEN": "1//abc==def/ghi"},
        )

    def test_ignores_garbage_lines(self):
        self.assertEqual(drive_client.parse_env_file("sin igual\n"), {})


class TestHttpErrorClassification(unittest.TestCase):
    def test_401_is_auth(self):
        self.assertEqual(drive_client.classify_http_error(401, ""), "auth")

    def test_403_permission_is_auth(self):
        body = '{"error":{"errors":[{"reason":"insufficientFilePermissions"}]}}'
        self.assertEqual(drive_client.classify_http_error(403, body), "auth")

    def test_403_quota_is_not_auth(self):
        # Cuota llena no es un problema de credenciales: reintentar tiene sentido.
        body = '{"error":{"errors":[{"reason":"storageQuotaExceeded"}]}}'
        self.assertEqual(drive_client.classify_http_error(403, body), "other")

    def test_403_rate_limit_is_not_auth(self):
        body = '{"error":{"errors":[{"reason":"rateLimitExceeded"}]}}'
        self.assertEqual(drive_client.classify_http_error(403, body), "other")

    def test_403_unparseable_body_defaults_to_auth(self):
        self.assertEqual(drive_client.classify_http_error(403, "<html>"), "auth")

    def test_500_is_other(self):
        self.assertEqual(drive_client.classify_http_error(500, ""), "other")

    def test_400_invalid_grant_is_auth(self):
        # Caso real: el endpoint de token responde 400, no 401, con la credencial
        # muerta o inexistente.
        body = '{"error":"invalid_grant","error_description":"Invalid grant: account not found"}'
        self.assertEqual(drive_client.classify_http_error(400, body), "auth")

    def test_400_invalid_client_is_auth(self):
        self.assertEqual(
            drive_client.classify_http_error(400, '{"error":"invalid_client"}'), "auth"
        )

    def test_400_plain_is_other(self):
        self.assertEqual(
            drive_client.classify_http_error(400, '{"error":"badRequest"}'), "other"
        )


class TestAuthUrl(unittest.TestCase):
    def params(self):
        import urllib.parse

        url = drive_client.build_auth_url("cid.apps.googleusercontent.com", "http://127.0.0.1:5000", "st")
        return urllib.parse.parse_qs(urllib.parse.urlparse(url).query)

    def test_offline_and_consent_are_present(self):
        # Sin estos dos, Google no devuelve refresh_token y habría que pasar por
        # el navegador en cada release.
        p = self.params()
        self.assertEqual(p["access_type"], ["offline"])
        self.assertEqual(p["prompt"], ["consent"])

    def test_core_params(self):
        p = self.params()
        self.assertEqual(p["response_type"], ["code"])
        self.assertEqual(p["scope"], [drive_client.DRIVE_SCOPE])
        self.assertEqual(p["state"], ["st"])
        self.assertEqual(p["redirect_uri"], ["http://127.0.0.1:5000"])

    def test_points_at_google(self):
        url = drive_client.build_auth_url("cid", "http://127.0.0.1:1", "s")
        self.assertTrue(url.startswith(drive_client.AUTH_URL + "?"))


class TestUpsertEnvVar(unittest.TestCase):
    def test_appends_when_absent(self):
        out = drive_client.upsert_env_var("FOO=bar\n", "GDRIVE_REFRESH_TOKEN", "tok")
        self.assertEqual(out, "FOO=bar\nGDRIVE_REFRESH_TOKEN=tok\n")

    def test_replaces_when_present(self):
        out = drive_client.upsert_env_var(
            "A=1\nGDRIVE_REFRESH_TOKEN=viejo\nB=2\n", "GDRIVE_REFRESH_TOKEN", "nuevo"
        )
        self.assertEqual(out, "A=1\nGDRIVE_REFRESH_TOKEN=nuevo\nB=2\n")

    def test_replaces_exported_form(self):
        out = drive_client.upsert_env_var(
            "export GDRIVE_REFRESH_TOKEN=viejo\n", "GDRIVE_REFRESH_TOKEN", "nuevo"
        )
        self.assertEqual(out, "GDRIVE_REFRESH_TOKEN=nuevo\n")

    def test_does_not_match_prefix(self):
        out = drive_client.upsert_env_var(
            "GDRIVE_REFRESH_TOKEN_OLD=x\n", "GDRIVE_REFRESH_TOKEN", "nuevo"
        )
        self.assertIn("GDRIVE_REFRESH_TOKEN_OLD=x", out)
        self.assertIn("GDRIVE_REFRESH_TOKEN=nuevo", out)

    def test_empty_file(self):
        self.assertEqual(drive_client.upsert_env_var("", "K", "v"), "K=v\n")

    def test_roundtrip_with_parser(self):
        out = drive_client.upsert_env_var("A=1\n", "GDRIVE_REFRESH_TOKEN", "tok")
        self.assertEqual(
            drive_client.parse_env_file(out), {"A": "1", "GDRIVE_REFRESH_TOKEN": "tok"}
        )


class TestBackendResolution(unittest.TestCase):
    """resolve_client lee .env.local del repo_root que se le pase."""

    def setUp(self):
        import tempfile

        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        # Aísla del entorno real de la máquina.
        self._saved = {
            k: os.environ.pop(k)
            for k in list(os.environ)
            if k.startswith("GDRIVE_")
        }

    def tearDown(self):
        os.environ.update(self._saved)
        self._tmp.cleanup()

    def write_env(self, content: str):
        (self.root / ".env.local").write_text(content)

    def test_no_config_falls_back_to_cli(self):
        self.assertEqual(drive_client.resolve_client(self.root).name, "gdrive-cli")

    def test_user_oauth_when_id_and_refresh_present(self):
        self.write_env("GDRIVE_CLIENT_ID=cid\nGDRIVE_CLIENT_SECRET=sec\nGDRIVE_REFRESH_TOKEN=tok\n")
        self.assertEqual(drive_client.resolve_client(self.root).name, "user-oauth")

    def test_client_id_without_refresh_token_is_not_enough(self):
        self.write_env("GDRIVE_CLIENT_ID=cid\nGDRIVE_CLIENT_SECRET=sec\n")
        self.assertEqual(drive_client.resolve_client(self.root).name, "gdrive-cli")

    def test_account_email_is_carried_into_client(self):
        self.write_env(
            "GDRIVE_CLIENT_ID=cid\nGDRIVE_CLIENT_SECRET=sec\n"
            "GDRIVE_REFRESH_TOKEN=tok\nGDRIVE_ACCOUNT_EMAIL=yo@gmail.com\n"
        )
        client = drive_client.resolve_client(self.root)
        self.assertEqual(client.account_email, "yo@gmail.com")
        self.assertIn("yo@gmail.com", client.describe())

    def test_credentials_are_per_project(self):
        """El .env.local de otro repo no debe filtrarse a este."""
        import tempfile

        with tempfile.TemporaryDirectory() as other:
            other_root = Path(other)
            (other_root / ".env.local").write_text(
                "GDRIVE_CLIENT_ID=de-otro-proyecto\nGDRIVE_REFRESH_TOKEN=tok\n"
            )
            self.assertEqual(drive_client.resolve_client(other_root).name, "user-oauth")
            # Este repo sigue sin credenciales propias.
            self.assertEqual(drive_client.resolve_client(self.root).name, "gdrive-cli")


class TestWriteEnvVars(unittest.TestCase):
    def setUp(self):
        import tempfile

        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_creates_with_600_perms(self):
        path = drive_client.write_env_vars(self.root, {"GDRIVE_REFRESH_TOKEN": "tok"})
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o600")
        self.assertEqual(
            drive_client.parse_env_file(path.read_text()),
            {"GDRIVE_REFRESH_TOKEN": "tok"},
        )

    def test_preserves_existing_keys(self):
        (self.root / ".env.local").write_text(
            "GDRIVE_CLIENT_ID=cid\nGDRIVE_CLIENT_SECRET=sec\n"
        )
        drive_client.write_env_vars(
            self.root,
            {"GDRIVE_REFRESH_TOKEN": "tok", "GDRIVE_ACCOUNT_EMAIL": "yo@gmail.com"},
        )
        values = drive_client.parse_env_file((self.root / ".env.local").read_text())
        self.assertEqual(values["GDRIVE_CLIENT_ID"], "cid")
        self.assertEqual(values["GDRIVE_CLIENT_SECRET"], "sec")
        self.assertEqual(values["GDRIVE_REFRESH_TOKEN"], "tok")
        self.assertEqual(values["GDRIVE_ACCOUNT_EMAIL"], "yo@gmail.com")

    def test_reauth_replaces_old_token(self):
        drive_client.write_env_vars(self.root, {"GDRIVE_REFRESH_TOKEN": "viejo"})
        drive_client.write_env_vars(self.root, {"GDRIVE_REFRESH_TOKEN": "nuevo"})
        text = (self.root / ".env.local").read_text()
        self.assertNotIn("viejo", text)
        self.assertEqual(
            drive_client.parse_env_file(text), {"GDRIVE_REFRESH_TOKEN": "nuevo"}
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
