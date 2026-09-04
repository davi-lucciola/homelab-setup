#!/usr/bin/env bash
set -euo pipefail

# v0 → v1: baseline legado deste repo (Docker, UFW 22/80/443, grupo docker).
# Isso já é feito pelo bootstrap em setup-homelab.sh; este script só fecha o ledger.

echo "Migração v1: baseline de host já aplicada pelo bootstrap; nada a fazer."
