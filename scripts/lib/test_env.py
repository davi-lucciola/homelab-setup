#!/usr/bin/env python3
"""Testes unitários dos helpers de .env."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parent))
import env


class CidrTests(unittest.TestCase):
    def test_slash24_from_lan_ip(self) -> None:
        self.assertEqual(env.cidr_from_ip("192.168.15.42"), "192.168.15.0/24")

    def test_rejects_invalid_ip(self) -> None:
        with self.assertRaises(ValueError):
            env.cidr_from_ip("not-an-ip")


class PasswordTests(unittest.TestCase):
    def test_empty_and_admin_are_weak(self) -> None:
        self.assertTrue(env.is_weak_password(""))
        self.assertTrue(env.is_weak_password("  "))
        self.assertTrue(env.is_weak_password("admin"))
        self.assertTrue(env.is_weak_password("Admin"))

    def test_strong_password_ok(self) -> None:
        self.assertFalse(env.is_weak_password("correct horse"))


class ParseAndExportTests(unittest.TestCase):
    def test_parse_ignores_comments(self) -> None:
        text = "# x=1\nHOMELAB_IP=192.168.15.42\nPIHOLE_PASSWORD=s3cret\n"
        values = env.parse_env_values(text)
        self.assertEqual(values["HOMELAB_IP"], "192.168.15.42")
        self.assertEqual(values["PIHOLE_PASSWORD"], "s3cret")
        self.assertNotIn("x", values)

    def test_export_only_known_keys(self) -> None:
        values = {
            "HOMELAB_IP": "10.0.0.5",
            "PIHOLE_PASSWORD": "s3cret",
            "IGNORED": "nope",
            "HOMELAB_BASICAUTH_USER": "homelab",
        }
        lines = env.export_lines(values)
        joined = "\n".join(lines)
        self.assertIn("export HOMELAB_IP=", joined)
        self.assertIn("export PIHOLE_PASSWORD=", joined)
        self.assertIn("export HOMELAB_BASICAUTH_USER=", joined)
        self.assertNotIn("IGNORED", joined)

    def test_export_quotes_shell_metacharacters(self) -> None:
        lines = env.export_lines({"PIHOLE_PASSWORD": "a; rm -rf /"})
        self.assertEqual(lines, ["export PIHOLE_PASSWORD='a; rm -rf /'"])


class WriteEnvTests(unittest.TestCase):
    def test_write_lines_mode_600(self) -> None:
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / ".env"
            env.write_lines(path, ["HOMELAB_IP=192.168.15.42"])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
