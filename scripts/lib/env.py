#!/usr/bin/env python3
"""Helpers de .env do homelab."""

from __future__ import annotations

import getpass
import os
import shlex
import socket
import stat
import subprocess
import sys
from pathlib import Path

FALLBACK_IP = "192.168.15.42"
FALLBACK_AUTH_USER = "homelab"
WEAK_PASSWORDS = frozenset({"admin"})

KNOWN_KEYS = (
    "HOMELAB_IP",
    "HOMELAB_LAN_CIDR",
    "PIHOLE_PASSWORD",
    "HOMELAB_BASICAUTH_USER",
    "HOMELAB_BASICAUTH_PASSWORD",
    "DOCKGE_STACKS_DIR",
)

ENV_MODE = 0o600


def homelab_root() -> Path:
    raw = os.environ.get("HOMELAB_ROOT")
    if raw:
        return Path(raw)
    return Path(__file__).resolve().parent.parent.parent


def env_path() -> Path:
    return homelab_root() / ".env"


def example_path() -> Path:
    return homelab_root() / ".env.example"


def htpasswd_path() -> Path:
    return homelab_root() / "stacks" / "traefik" / ".htpasswd"


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


def chmod_private(path: Path) -> None:
    os.chmod(path, ENV_MODE)


def write_lines(path: Path, lines: list[str]) -> None:
    text = "\n".join(lines)
    if text:
        text += "\n"
    tmp = path.with_name(f"{path.name}.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.chmod(tmp, ENV_MODE)
    tmp.replace(path)
    chmod_private(path)


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


def cidr_from_ip(ip: str) -> str:
    parts = ip.strip().split(".")
    if len(parts) != 4 or not all(p.isdigit() and 0 <= int(p) <= 255 for p in parts):
        raise ValueError(f"IP inválido para CIDR /24: {ip}")
    return f"{parts[0]}.{parts[1]}.{parts[2]}.0/24"


def is_weak_password(value: str | None) -> bool:
    stripped = (value or "").strip()
    return not stripped or stripped.lower() in WEAK_PASSWORDS


def known_env_values(values: dict[str, str]) -> dict[str, str]:
    return {key: values[key] for key in KNOWN_KEYS if key in values}


def export_lines(values: dict[str, str]) -> list[str]:
    out: list[str] = []
    for key in KNOWN_KEYS:
        if key not in values:
            continue
        out.append(f"export {key}={shlex.quote(values[key])}")
    return out


def ensure_env_file() -> tuple[Path, bool]:
    path = env_path()
    if path.exists():
        chmod_private(path)
        return path, False

    example = example_path()
    if example.exists():
        path.write_text(example.read_text(encoding="utf-8"), encoding="utf-8")
    else:
        path.write_text(
            f"HOMELAB_IP={FALLBACK_IP}\n"
            f"HOMELAB_LAN_CIDR={cidr_from_ip(FALLBACK_IP)}\n"
            "PIHOLE_PASSWORD=\n"
            f"HOMELAB_BASICAUTH_USER={FALLBACK_AUTH_USER}\n"
            "HOMELAB_BASICAUTH_PASSWORD=\n"
            "DOCKGE_STACKS_DIR=\n",
            encoding="utf-8",
        )
    chmod_private(path)
    return path, True


def default_ip(values: dict[str, str], created: bool) -> str:
    existing = values.get("HOMELAB_IP", "").strip()
    detected = detect_lan_ip()
    if created:
        return detected or existing or FALLBACK_IP
    return existing or detected or FALLBACK_IP


def default_cidr(values: dict[str, str], ip: str) -> str:
    existing = values.get("HOMELAB_LAN_CIDR", "").strip()
    if existing:
        return existing
    try:
        return cidr_from_ip(ip)
    except ValueError:
        return cidr_from_ip(FALLBACK_IP)


def default_auth_user(values: dict[str, str]) -> str:
    existing = values.get("HOMELAB_BASICAUTH_USER", "").strip()
    return existing or FALLBACK_AUTH_USER


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


def prompt_secret(label: str, existing: str) -> str:
    keep = existing.strip()
    if not sys.stdin.isatty():
        if is_weak_password(keep):
            raise SystemExit(
                f"{label}: senha ausente ou 'admin' sem TTY. Preencha o .env e rode de novo."
            )
        return keep

    while True:
        if keep and not is_weak_password(keep):
            prompt = f"{label} [Enter = manter]: "
        else:
            prompt = f"{label}: "
        try:
            raw = getpass.getpass(prompt)
        except EOFError:
            print()
            raw = ""
        stripped = raw.strip()
        if not stripped:
            if keep and not is_weak_password(keep):
                return keep
            print("Informe uma senha (não use admin).", file=sys.stderr)
            continue
        if is_weak_password(stripped):
            print("Senha fraca: não use admin nem vazio.", file=sys.stderr)
            continue
        return stripped


def apr1_hash(password: str) -> str:
    try:
        proc = subprocess.run(
            ["openssl", "passwd", "-apr1", "-stdin"],
            input=password.encode("utf-8"),
            capture_output=True,
            check=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit("openssl não encontrado; instale openssl (./setup-homelab.sh).") from exc
    except subprocess.CalledProcessError as exc:
        err = exc.stderr.decode("utf-8", errors="replace").strip()
        raise SystemExit(f"openssl passwd falhou: {err or exc.returncode}") from exc
    hashed = proc.stdout.decode("utf-8").strip()
    if not hashed:
        raise SystemExit("openssl passwd não devolveu hash")
    return hashed


def write_htpasswd(user: str, password: str) -> Path:
    name = user.strip()
    if not name or ":" in name:
        raise SystemExit("HOMELAB_BASICAUTH_USER inválido")
    if is_weak_password(password):
        raise SystemExit("HOMELAB_BASICAUTH_PASSWORD ausente ou 'admin'")
    path = htpasswd_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    hashed = apr1_hash(password)
    tmp = path.with_name(f"{path.name}.tmp")
    tmp.write_text(f"{name}:{hashed}\n", encoding="utf-8")
    os.chmod(tmp, ENV_MODE)
    tmp.replace(path)
    chmod_private(path)
    return path


def require_mode(path: Path, mode: int = ENV_MODE) -> None:
    current = stat.S_IMODE(path.stat().st_mode)
    if current != mode:
        os.chmod(path, mode)


def cmd_prompt() -> None:
    path, created = ensure_env_file()
    if created:
        print("Criando .env a partir de .env.example...")
    lines, values = read_env(path)
    ip_default = default_ip(values, created)
    if sys.stdin.isatty():
        print("==> Configuração do .env (Enter = padrão; senhas sem eco)")
    ip = prompt_value("IP LAN do host", ip_default)
    cidr = prompt_value("CIDR da LAN", default_cidr(values, ip))
    password = prompt_secret("Senha do admin do Pi-hole", values.get("PIHOLE_PASSWORD", ""))
    auth_user = prompt_value("Usuário HTTP do Traefik (basicAuth)", default_auth_user(values))
    auth_password = prompt_secret(
        "Senha HTTP do Traefik (basicAuth)",
        values.get("HOMELAB_BASICAUTH_PASSWORD", ""),
    )
    lines = set_key(lines, "HOMELAB_IP", ip)
    lines = set_key(lines, "HOMELAB_LAN_CIDR", cidr)
    lines = set_key(lines, "PIHOLE_PASSWORD", password)
    lines = set_key(lines, "HOMELAB_BASICAUTH_USER", auth_user)
    lines = set_key(lines, "HOMELAB_BASICAUTH_PASSWORD", auth_password)
    write_lines(path, lines)
    write_htpasswd(auth_user, auth_password)


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


def cmd_ensure_cidr() -> None:
    path = env_path()
    if not path.exists():
        raise SystemExit(".env ausente; rode ./setup-homelab.sh")
    lines, values = read_env(path)
    existing = values.get("HOMELAB_LAN_CIDR", "").strip()
    if existing:
        return
    ip = values.get("HOMELAB_IP", "").strip() or FALLBACK_IP
    lines = set_key(lines, "HOMELAB_LAN_CIDR", cidr_from_ip(ip))
    write_lines(path, lines)


def cmd_export() -> None:
    path = env_path()
    if not path.exists():
        return
    _, values = read_env(path)
    for line in export_lines(values):
        print(line)


def cmd_write_htpasswd() -> None:
    path = env_path()
    if not path.exists():
        raise SystemExit(".env ausente; rode ./setup-homelab.sh")
    _, values = read_env(path)
    write_htpasswd(
        values.get("HOMELAB_BASICAUTH_USER", ""),
        values.get("HOMELAB_BASICAUTH_PASSWORD", ""),
    )


def cmd_validate() -> None:
    path = env_path()
    if not path.exists():
        raise SystemExit(".env ausente; rode ./setup-homelab.sh")
    require_mode(path)
    _, values = read_env(path)
    ip = values.get("HOMELAB_IP", "").strip()
    cidr = values.get("HOMELAB_LAN_CIDR", "").strip()
    if not ip:
        raise SystemExit("HOMELAB_IP vazio")
    if not cidr:
        raise SystemExit("HOMELAB_LAN_CIDR vazio; rode ./setup-homelab.sh")
    if is_weak_password(values.get("PIHOLE_PASSWORD", "")):
        raise SystemExit("PIHOLE_PASSWORD ausente ou 'admin'; rode ./setup-homelab.sh")
    user = values.get("HOMELAB_BASICAUTH_USER", "").strip()
    if not user:
        raise SystemExit("HOMELAB_BASICAUTH_USER vazio")
    if is_weak_password(values.get("HOMELAB_BASICAUTH_PASSWORD", "")):
        raise SystemExit("HOMELAB_BASICAUTH_PASSWORD ausente ou 'admin'; rode ./setup-homelab.sh")
    htpasswd = htpasswd_path()
    if not htpasswd.is_file():
        raise SystemExit(f"faltando {htpasswd}; rode ./setup-homelab.sh")
    require_mode(htpasswd)


def main(argv: list[str] | None = None) -> None:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        raise SystemExit(
            "usage: env.py prompt | ensure-stacks-dir | ensure-cidr | export | write-htpasswd | validate"
        )

    cmd = args[0]
    if cmd == "prompt":
        cmd_prompt()
    elif cmd == "ensure-stacks-dir":
        cmd_ensure_stacks_dir()
    elif cmd == "ensure-cidr":
        cmd_ensure_cidr()
    elif cmd == "export":
        cmd_export()
    elif cmd == "write-htpasswd":
        cmd_write_htpasswd()
    elif cmd == "validate":
        cmd_validate()
    else:
        raise SystemExit(f"unknown env command: {cmd}")


if __name__ == "__main__":
    main()
