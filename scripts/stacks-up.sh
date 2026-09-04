#!/usr/bin/env bash
# Sobe as stacks em stacks/ como projetos Compose independentes.
# Pi-hole primeiro (DNS), depois Traefik, depois o restante.
set -euo pipefail

HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/env.sh
source "${HOMELAB_ROOT}/scripts/lib/env.sh"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

ensure_dockge_stacks_dir
load_homelab_env

if [[ -z "${DOCKGE_STACKS_DIR:-}" ]]; then
    echo -e "${RED}DOCKGE_STACKS_DIR vazio; rode ./setup-homelab.sh ou preencha o .env${NC}" >&2
    exit 1
fi

ensure_proxy_network() {
    if docker network inspect proxy >/dev/null 2>&1; then
        return
    fi
    echo -e "${BLUE}==> Criando rede Docker proxy...${NC}"
    docker network create --driver bridge proxy >/dev/null
}

container_project() {
    local name="$1"
    docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "${name}" 2>/dev/null || true
}

up_stack() {
    local stack="$1"
    local dir="${HOMELAB_ROOT}/stacks/${stack}"
    local compose_file="${dir}/compose.yaml"

    if [[ ! -f "${compose_file}" ]]; then
        echo "Stack sem compose.yaml: ${dir}" >&2
        exit 1
    fi

    local existing
    existing="$(container_project "${stack}")"
    if [[ -n "${existing}" && "${existing}" != "${stack}" ]]; then
        echo -e "${BLUE}==> Recriando ${stack} (projeto Compose '${existing}' → '${stack}')...${NC}"
        docker rm -f "${stack}" >/dev/null
    else
        echo -e "${BLUE}==> Subindo stack ${stack}...${NC}"
    fi

    docker compose \
        --project-directory "${dir}" \
        --env-file "${HOMELAB_ROOT}/.env" \
        up -d
}

wait_for_dns() {
    local expected="${HOMELAB_IP:-}"
    local i answer
    echo -e "${BLUE}==> Aguardando Pi-hole FTL na porta 53...${NC}"
    for i in $(seq 1 60); do
        answer="$(dig @127.0.0.1 +time=1 +tries=1 +notcp +short pihole.homelab.internal A 2>/dev/null | grep -E '^[0-9.]+$' | tail -n1 || true)"
        if [[ -n "${expected}" && "${answer}" == "${expected}" ]]; then
            echo -e "${GREEN}FTL respondeu (${answer}).${NC}"
            return 0
        fi
        sleep 1
    done
    echo "Pi-hole não respondeu com ${expected} a tempo." >&2
    return 1
}

list_other_stacks() {
    local d name
    shopt -s nullglob
    for d in "${HOMELAB_ROOT}/stacks"/*/; do
        name="$(basename "${d}")"
        case "${name}" in
            pihole|traefik) continue ;;
        esac
        if [[ -f "${d}compose.yaml" ]]; then
            printf '%s\n' "${name}"
        fi
    done
    shopt -u nullglob
}

ensure_proxy_network

up_stack pihole
wait_for_dns
"${HOMELAB_ROOT}/scripts/check-dns.sh" --dns-only

up_stack traefik

local_stack=""
while IFS= read -r local_stack; do
    [[ -z "${local_stack}" ]] && continue
    up_stack "${local_stack}"
done < <(list_other_stacks)

echo -e "${BLUE}==> Check DNS + HTTP após todas as stacks...${NC}"
"${HOMELAB_ROOT}/scripts/check-dns.sh"

echo -e "${GREEN}Stacks no ar.${NC}"
