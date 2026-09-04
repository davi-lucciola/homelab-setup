#!/usr/bin/env bash
# Banco local de versão da infra (.homelab/state.json).
# Deve ser sourced; não executar diretamente.

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
    HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

HOMELAB_STATE_DIR="${HOMELAB_ROOT}/.homelab"
HOMELAB_STATE_FILE="${HOMELAB_STATE_DIR}/state.json"
HOMELAB_VERSION_FILE="${HOMELAB_ROOT}/VERSION"
HOMELAB_STATE_PY="${HOMELAB_ROOT}/scripts/lib/state.py"

_state_python() {
    HOMELAB_STATE_FILE="${HOMELAB_STATE_FILE}" python3 "${HOMELAB_STATE_PY}" "$@"
}

_state_legacy_install_exists() {
    local names=""
    if command -v docker >/dev/null 2>&1; then
        names="$(docker network ls --format '{{.Name}}' 2>/dev/null || true)"
        if [[ -z "$names" ]] && command -v sudo >/dev/null 2>&1; then
            names="$(sudo docker network ls --format '{{.Name}}' 2>/dev/null || true)"
        fi
    fi
    grep -qx 'proxy' <<<"$names"
}

state_bootstrap() {
    mkdir -p "${HOMELAB_STATE_DIR}"
    if [[ -f "${HOMELAB_STATE_FILE}" ]]; then
        return
    fi

    # Sem state.json: install limpo parte de 0; se a rede proxy já existe, isto é v1 legado.
    local initial=0
    if _state_legacy_install_exists; then
        initial=1
    fi

    _state_python init "${initial}"
}

state_get_applied_version() {
    _state_python get-applied
}

state_record_migration() {
    local version="$1"
    local status="$2"
    _state_python record "${version}" "${status}"
}

state_get_target_version() {
    tr -d '[:space:]' <"${HOMELAB_VERSION_FILE}"
}
