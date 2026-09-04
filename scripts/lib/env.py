#!/usr/bin/env python3
"""Helpers de .env do homelab."""

from __future__ import annotations

import os
import socket
import sys
from pathlib import Path

FALLBACK_IP = "192.168.15.42"
FALLBACK_PASSWORD = "admin"


def homelab_root() -> Path:
    raw = os.environ.get("HOMELAB_ROOT")
    if raw:
        return Path(raw)
    return Path(__file__).resolve().parent.parent.parent


def env_path() -> Path:
    return homelab_root() / ".env"


def example_path() -> Path:
    return homelab_root() / ".env.example"


def parse_env_values(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        if not key or key.startswith("#"):
            continue
        values[key] = value
    return values


def read_env(path: Path) -> tuple[list[str], dict[str, str]]:
    if not path.exists():
        return [], {}
    text = path.read_text(encoding="utf-8")
    return text.splitlines(), parse_env_values(text)


def set_key(lines: list[str], key: str, value: str) -> list[str]:
    out: list[str] = []
    done = False
    prefix = f"{key}="
    for line in lines:
        if not done and line.startswith(prefix):
            out.append(f"{key}={value}")
            done = True
        else:
            out.append(line)
    if not done:
        if out and out[-1] != "":
            out.append("")
        out.append(f"{key}={value}")
    return out


def write_lines(path: Path, lines: list[str]) -> None:
    text = "\n".join(lines)
    if text:
        text += "\n"
    tmp = path.with_name(f"{path.name}.tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def detect_lan_ip() -> str | None:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(1)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
    except OSError:
        return None
    if ip and not ip.startswith("127."):
        return ip
    return None


def ensure_env_file() -> tuple[Path, bool]:
    path = env_path()
    if path.exists():
        return path, False

    example = example_path()
    if example.exists():
        path.write_text(example.read_text(encoding="utf-8"), encoding="utf-8")
    else:
        path.write_text(
            f"HOMELAB_IP={FALLBACK_IP}\n"
            f"PIHOLE_PASSWORD={FALLBACK_PASSWORD}\n"
            "DOCKGE_STACKS_DIR=\n",
            encoding="utf-8",
        )
    return path, True


def default_ip(values: dict[str, str], created: bool) -> str:
    existing = values.get("HOMELAB_IP", "").strip()
    detected = detect_lan_ip()
    if created:
        return detected or existing or FALLBACK_IP
    return existing or detected or FALLBACK_IP


def default_password(values: dict[str, str]) -> str:
    existing = values.get("PIHOLE_PASSWORD", "").strip()
    return existing or FALLBACK_PASSWORD


def prompt_value(label: str, default: str) -> str:
    if not sys.stdin.isatty():
        return default
    try:
        raw = input(f"{label} [{default}]: ")
    except EOFError:
        print()
        return default
    stripped = raw.strip()
    return stripped if stripped else default


def cmd_prompt() -> None:
    path, created = ensure_env_file()
    if created:
        print("Criando .env a partir de .env.example...")
    lines, values = read_env(path)
    ip_default = default_ip(values, created)
    pw_default = default_password(values)
    if sys.stdin.isatty():
        print("==> Configuração do .env (Enter = padrão)")
    ip = prompt_value("IP LAN do host", ip_default)
    password = prompt_value("Senha do admin do Pi-hole", pw_default)
    lines = set_key(lines, "HOMELAB_IP", ip)
    lines = set_key(lines, "PIHOLE_PASSWORD", password)
    write_lines(path, lines)


def cmd_ensure_stacks_dir() -> None:
    path = env_path()
    if not path.exists():
        return
    stacks = str(homelab_root() / "stacks")
    lines, values = read_env(path)
    if values.get("DOCKGE_STACKS_DIR", "").strip():
        return
    lines = set_key(lines, "DOCKGE_STACKS_DIR", stacks)
    write_lines(path, lines)


def main(argv: list[str] | None = None) -> None:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        raise SystemExit("usage: env.py prompt | ensure-stacks-dir")

    cmd = args[0]
    if cmd == "prompt":
        cmd_prompt()
    elif cmd == "ensure-stacks-dir":
        cmd_ensure_stacks_dir()
    else:
        raise SystemExit(f"unknown env command: {cmd}")


if __name__ == "__main__":
    main()
