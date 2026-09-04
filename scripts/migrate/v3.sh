#!/usr/bin/env bash
set -euo pipefail

# v2 → v3: Portainer → Dockge. Não derruba o Pi-hole; o recreate fica a cargo
# de scripts/stacks-up.sh (Pi-hole primeiro, depois check de DNS).
# Também aponta o resolver do host para 127.0.0.1 (Pi-hole): o v2 deixou o
# symlink do systemd-resolved com 1.1.1.1/8.8.8.8 na frente.

HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/env.sh
source "${HOMELAB_ROOT}/scripts/lib/env.sh"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==> Migração v3: rede proxy, resolver local, remover Portainer...${NC}"

ensure_dockge_stacks_dir

if ! docker network inspect proxy >/dev/null 2>&1; then
    echo -e "${BLUE}==> Criando rede Docker proxy...${NC}"
    docker network create --driver bridge proxy >/dev/null
else
    echo "Rede proxy já existe."
fi

if sudo -n true 2>/dev/null; then
    if systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
        echo -e "${BLUE}==> Resolver do host: Pi-hole em 127.0.0.1 primeiro...${NC}"
        sudo mkdir -p /etc/systemd/resolved.conf.d
        sudo tee /etc/systemd/resolved.conf.d/homelab.conf >/dev/null <<'EOF'
[Resolve]
DNS=127.0.0.1
FallbackDNS=
DNSStubListener=no
EOF
        sudo systemctl restart systemd-resolved
    fi

    # resolv.conf estático: o arquivo uplink do resolved mistura Cloudflare/Google
    # na frente e o glibc/dig ignoram o 127.0.0.1. Stub já está desligado (v2).
    sudo tee /etc/resolv.conf >/dev/null <<'EOF'
# Homelab: Pi-hole em 127.0.0.1 (gerado pela migração v3)
nameserver 127.0.0.1
options timeout:2 attempts:2
EOF
else
    echo "sudo indisponível neste contexto; pulando ajuste de resolv.conf (rode ./setup-homelab.sh no host)."
fi

if docker inspect portainer >/dev/null 2>&1; then
    echo -e "${BLUE}==> Removendo container portainer...${NC}"
    docker rm -f portainer >/dev/null
else
    echo "Container portainer não encontrado; pulando."
fi

if docker volume inspect portainer_data >/dev/null 2>&1; then
    echo -e "${BLUE}==> Removendo volume portainer_data...${NC}"
    docker volume rm portainer_data >/dev/null
else
    echo "Volume portainer_data não encontrado; pulando."
fi

echo -e "${GREEN}Migração v3 concluída. Suba as stacks com ./scripts/stacks-up.sh${NC}"
