#!/usr/bin/env bash
# Verifica DNS do Pi-hole (wildcard homelab.internal, UDP/TCP, LAN, forwarding).
# Uso: ./scripts/check-dns.sh [--dns-only]
set -euo pipefail

HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/env.sh
source "${HOMELAB_ROOT}/scripts/lib/env.sh"

load_homelab_env

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

DNS_ONLY=0
if [[ "${1:-}" == "--dns-only" ]]; then
    DNS_ONLY=1
fi

if [[ -z "${HOMELAB_IP:-}" ]]; then
    echo "HOMELAB_IP não definido no .env" >&2
    exit 1
fi

if ! command -v dig >/dev/null 2>&1; then
    echo "dig não encontrado; instale bind9-dnsutils (./setup-homelab.sh)." >&2
    exit 1
fi

FAILS=0
pass() { echo -e "${GREEN}OK${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC} $*"; FAILS=$((FAILS + 1)); }

DIG_OPTS=(+time=2 +tries=1 +noall +answer +short)

ipv4_from_dig() {
    grep -E '^[0-9]+(\.[0-9]+){3}$' | tail -n1
}

expect_ip() {
    local ns="$1" name="$2" proto="$3"
    local extra=()
    local label="UDP"
    if [[ "${proto}" == tcp ]]; then
        extra=(+tcp)
        label="TCP"
    else
        extra=(+notcp)
    fi

    local got
    got="$(dig "@${ns}" "${DIG_OPTS[@]}" "${extra[@]}" "${name}" A 2>/dev/null | ipv4_from_dig || true)"
    if [[ "${got}" == "${HOMELAB_IP}" ]]; then
        pass "${label} @${ns} ${name} → ${got}"
    else
        fail "${label} @${ns} ${name} → '${got}' (esperado ${HOMELAB_IP})"
    fi
}

expect_forward() {
    local name="example.com"
    local got
    got="$(dig @127.0.0.1 "${DIG_OPTS[@]}" +notcp "${name}" A 2>/dev/null | ipv4_from_dig || true)"
    if [[ -n "${got}" ]]; then
        pass "forward @127.0.0.1 ${name} → ${got}"
    else
        fail "forward @127.0.0.1 ${name} não devolveu A"
    fi
}

container_running() {
    local name="$1"
    [[ "$(docker inspect -f '{{.State.Running}}' "${name}" 2>/dev/null || true)" == "true" ]]
}

http_host() {
    local host="$1" path="$2"
    local code="" i
    for i in $(seq 1 20); do
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 -H "Host: ${host}" "http://127.0.0.1${path}" || true)"
        case "${code}" in
            200|301|302|307|308)
                pass "HTTP Host ${host}${path} → ${code}"
                return 0
                ;;
        esac
        sleep 1
    done
    fail "HTTP Host ${host}${path} → '${code}'"
}

# --- Pronto: container e porta 53 ---
if container_running pihole; then
    pass "container pihole running"
else
    fail "container pihole não está running"
fi

if docker port pihole 53/udp >/dev/null 2>&1 && docker port pihole 53/tcp >/dev/null 2>&1; then
    pass "pihole publica 53/udp e 53/tcp"
else
    fail "pihole não publica 53/udp e 53/tcp"
fi

if ss -lunH 'sport = :53' 2>/dev/null | grep -q .; then
    pass "host escuta UDP/53"
else
    fail "nada escuta UDP/53 no host"
fi

if ss -ltnH 'sport = :53' 2>/dev/null | grep -q .; then
    pass "host escuta TCP/53"
else
    fail "nada escuta TCP/53 no host"
fi

# --- Wildcard local UDP+TCP, loopback e LAN ---
WILDCARD_NAMES=(
    pihole.homelab.internal
    traefik.homelab.internal
    dockge.homelab.internal
    "check-$(date +%s).homelab.internal"
)

ns=""
name=""
for ns in 127.0.0.1 "${HOMELAB_IP}"; do
    for name in "${WILDCARD_NAMES[@]}"; do
        expect_ip "${ns}" "${name}" udp
        expect_ip "${ns}" "${name}" tcp
    done
done

# --- Forwarding ---
expect_forward

# --- Resolver do host (resolv.conf) ---
first_ns="$(awk '/^nameserver / && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $2; exit }' /etc/resolv.conf || true)"
if [[ "${first_ns}" == "127.0.0.1" || "${first_ns}" == "${HOMELAB_IP}" ]]; then
    host_got="$(dig "${DIG_OPTS[@]}" +notcp pihole.homelab.internal A 2>/dev/null | ipv4_from_dig || true)"
    if [[ "${host_got}" == "${HOMELAB_IP}" ]]; then
        pass "resolver do host (NS ${first_ns}) pihole.homelab.internal → ${host_got}"
    else
        fail "resolver do host (NS ${first_ns}) pihole.homelab.internal → '${host_got}' (esperado ${HOMELAB_IP})"
    fi
elif [[ -n "${first_ns}" ]]; then
    pass "resolver do host usa ${first_ns} primeiro; wildcard só via Pi-hole (@127.0.0.1). sudo ./setup-homelab.sh aplica o resolv.conf da v3"
else
    fail "resolv.conf sem nameserver IPv4"
fi

# --- Persistência do wildcard / bind mounts ---
if [[ -d "${HOMELAB_ROOT}/stacks/pihole/etc-pihole" ]]; then
    pass "bind mount stacks/pihole/etc-pihole existe"
else
    fail "falta stacks/pihole/etc-pihole"
fi

ftl_lines=""
if container_running pihole; then
    ftl_lines="$(docker exec pihole pihole-FTL --config misc.dnsmasq_lines 2>/dev/null || true)"
fi
if [[ "${ftl_lines}" == *address=/homelab.internal/* ]]; then
    pass "FTL misc.dnsmasq_lines contém address=/homelab.internal/"
else
    fail "FTL misc.dnsmasq_lines sem address=/homelab.internal/ ('${ftl_lines}')"
fi

# --- HTTP via Traefik (opcional) ---
if [[ "${DNS_ONLY}" -eq 0 ]]; then
    if container_running traefik; then
        http_host pihole.homelab.internal /admin/
        http_host traefik.homelab.internal /
        if container_running dockge; then
            http_host dockge.homelab.internal /
        else
            pass "HTTP dockge.homelab.internal pulado (container ausente)"
        fi
    else
        pass "HTTP pulado (traefik ausente); use sem --dns-only depois do proxy"
    fi
fi

if [[ "${FAILS}" -ne 0 ]]; then
    echo -e "${RED}${FAILS} check(s) falharam.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}DNS check OK.${NC}"
