#!/usr/bin/env python3
"""Banco local de versão da infra (.homelab/state.json)."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime
from pathlib import Path


def state_path() -> Path:
    raw = os.environ.get("HOMELAB_STATE_FILE")
    if not raw:
        raise SystemExit("HOMELAB_STATE_FILE is not set")
    return Path(raw)


def now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def load(path: Path) -> dict:
    if not path.exists():
        raise SystemExit(f"state file missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(data, indent=2) + "\n"
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(payload, encoding="utf-8")
    tmp.replace(path)


def cmd_init(path: Path, applied_version: int) -> None:
    if path.exists():
        return
    save(
        path,
        {
            "applied_version": applied_version,
            "updated_at": now(),
            "migrations": [],
        },
    )


def cmd_get_applied(path: Path) -> None:
    print(load(path)["applied_version"])


def cmd_record(path: Path, version: int, status: str) -> None:
    data = load(path)
    data.setdefault("migrations", []).append(
        {
            "version": version,
            "applied_at": now(),
            "status": status,
        }
    )
    if status == "ok":
        data["applied_version"] = version
    data["updated_at"] = now()
    save(path, data)


def main(argv: list[str] | None = None) -> None:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        raise SystemExit("usage: state.py init <version> | get-applied | record <version> <status>")

    path = state_path()
    cmd = args[0]
    if cmd == "init":
        cmd_init(path, int(args[1]))
    elif cmd == "get-applied":
        cmd_get_applied(path)
    elif cmd == "record":
        cmd_record(path, int(args[1]), args[2])
    else:
        raise SystemExit(f"unknown state command: {cmd}")


if __name__ == "__main__":
    main()
