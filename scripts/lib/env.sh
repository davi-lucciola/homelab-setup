#!/usr/bin/env bash
# Helpers de .env. Deve ser sourced; não executar diretamente.

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
    HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

HOMELAB_ENV_PY="${HOMELAB_ROOT}/scripts/lib/env.py"

_env_python() {
    HOMELAB_ROOT="${HOMELAB_ROOT}" python3 "${HOMELAB_ENV_PY}" "$@"
}

prompt_homelab_env() {
    _env_python prompt
}

ensure_dockge_stacks_dir() {
    _env_python ensure-stacks-dir
}

load_homelab_env() {
    local env_file="${HOMELAB_ROOT}/.env"
    if [[ -f "${env_file}" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "${env_file}"
        set +a
    fi
}
