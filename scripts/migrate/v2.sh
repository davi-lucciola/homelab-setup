#!/usr/bin/env bash
set -euo pipefail

# v1 → v2: DNS local (Pi-hole) no host.
# Idempotente. A rede Docker `proxy` fica a cargo do compose.yaml da raiz.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==> Migração v2: UFW DNS/admin e systemd-resolved...${NC}"

sudo ufw allow 53/tcp comment 'DNS'
sudo ufw allow 53/udp comment 'DNS'
sudo ufw allow 8053/tcp comment 'Pi-hole admin'

if systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
    echo -e "${BLUE}==> Desabilitando DNSStubListener do systemd-resolved (porta 53)...${NC}"
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf.d/homelab.conf >/dev/null <<'EOF'
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
    sudo systemctl restart systemd-resolved

    # Sem o stub em 127.0.0.53, o resolv.conf precisa apontar para o resolved real
    # (ou 127.0.0.1, onde o Pi-hole publica a porta 53).
    if [[ -L /etc/resolv.conf ]] || [[ -f /etc/resolv.conf ]]; then
        if [[ -f /run/systemd/resolve/resolv.conf ]]; then
            sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        fi
    fi
    echo -e "${GREEN}systemd-resolved ajustado (DNSStubListener=no, DNS=127.0.0.1).${NC}"
else
    echo "systemd-resolved não encontrado; pulando ajuste de stub DNS."
fi

echo -e "${GREEN}Migração v2 concluída.${NC}"
