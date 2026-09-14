#!/usr/bin/env bash
set -euo pipefail

# v3 → v4: bind LAN, UFW por CIDR, DOCKER-USER, htpasswd. Recreate das stacks
# fica a cargo de scripts/stacks-up.sh.

HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/env.sh
source "${HOMELAB_ROOT}/scripts/lib/env.sh"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

FILTER_SCRIPT="/usr/local/sbin/homelab-docker-filter.sh"
FILTER_UNIT="/etc/systemd/system/homelab-docker-filter.service"
LAN_CIDR_FILE="/etc/homelab/lan-cidr"

echo -e "${BLUE}==> Migração v4: UFW LAN, filtro Docker, htpasswd...${NC}"

ensure_homelab_cidr
load_homelab_env

if [[ -z "${HOMELAB_LAN_CIDR:-}" ]]; then
    echo "HOMELAB_LAN_CIDR vazio; rode ./setup-homelab.sh" >&2
    exit 1
fi

write_homelab_htpasswd

ufw_allow_lan() {
    local port="$1"
    local proto="$2"
    local comment="$3"
    sudo ufw allow from "${HOMELAB_LAN_CIDR}" to any port "${port}" proto "${proto}" comment "${comment}"
}

echo -e "${BLUE}==> UFW: permitir só ${HOMELAB_LAN_CIDR}...${NC}"
ufw_allow_lan 22 tcp 'SSH LAN'
ufw_allow_lan 80 tcp 'HTTP LAN'
ufw_allow_lan 443 tcp 'HTTPS LAN'
ufw_allow_lan 53 tcp 'DNS LAN'
ufw_allow_lan 53 udp 'DNS LAN'

# Remove regras abertas ao mundo (inseridas pelo bootstrap/v2). CIDR já está no lugar.
sudo ufw --force delete allow 22/tcp >/dev/null 2>&1 || true
sudo ufw --force delete allow 80/tcp >/dev/null 2>&1 || true
sudo ufw --force delete allow 443/tcp >/dev/null 2>&1 || true
sudo ufw --force delete allow 53/tcp >/dev/null 2>&1 || true
sudo ufw --force delete allow 53/udp >/dev/null 2>&1 || true
sudo ufw --force delete allow 8053/tcp >/dev/null 2>&1 || true

install_docker_filter() {
    sudo mkdir -p /etc/homelab /usr/local/sbin
    printf '%s\n' "${HOMELAB_LAN_CIDR}" | sudo tee "${LAN_CIDR_FILE}" >/dev/null
    sudo chmod 0644 "${LAN_CIDR_FILE}"

    sudo tee "${FILTER_SCRIPT}" >/dev/null <<'EOF'
#!/usr/bin/env bash
# Filtra tráfego publicado pelo Docker (cadeia DOCKER-USER). Idempotente.
set -euo pipefail

CIDR_FILE="${HOMELAB_LAN_CIDR_FILE:-/etc/homelab/lan-cidr}"
if [[ ! -f "${CIDR_FILE}" ]]; then
    echo "homelab-docker-filter: ${CIDR_FILE} ausente" >&2
    exit 1
fi
CIDR="$(tr -d '[:space:]' <"${CIDR_FILE}")"
if [[ -z "${CIDR}" ]]; then
    echo "homelab-docker-filter: CIDR vazio" >&2
    exit 1
fi

apply_filter() {
    local ipt="$1"
    shift
    if ! command -v "${ipt}" >/dev/null 2>&1; then
        return 0
    fi
    if ! "${ipt}" -nL DOCKER-USER >/dev/null 2>&1; then
        echo "homelab-docker-filter: cadeia DOCKER-USER ausente (${ipt}); Docker ainda não criou."
        return 0
    fi
    "${ipt}" -F DOCKER-USER
    "${ipt}" -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
    for src in "$@"; do
        "${ipt}" -A DOCKER-USER -s "${src}" -j RETURN
    done
    "${ipt}" -A DOCKER-USER -j DROP
}

apply_filter iptables 127.0.0.0/8 "${CIDR}"
# IPv6 publicado pelo Docker: só loopback (LAN v4 é o modelo deste homelab).
apply_filter ip6tables ::1/128

EOF
    sudo chmod 0755 "${FILTER_SCRIPT}"

    sudo tee "${FILTER_UNIT}" >/dev/null <<EOF
[Unit]
Description=Homelab DOCKER-USER filter (LAN only)
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${FILTER_SCRIPT}

[Install]
WantedBy=multi-user.target docker.service
EOF

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl daemon-reload
        sudo systemctl enable homelab-docker-filter.service >/dev/null
        sudo systemctl restart homelab-docker-filter.service
    else
        sudo "${FILTER_SCRIPT}" || true
    fi
}

if sudo -n true 2>/dev/null || sudo true; then
    install_docker_filter
else
    echo "sudo indisponível; pulando filtro DOCKER-USER (rode ./setup-homelab.sh no host)."
fi

echo -e "${GREEN}Migração v4 concluída. Recrie as stacks com ./scripts/stacks-up.sh${NC}"
