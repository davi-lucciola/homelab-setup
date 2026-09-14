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

ensure_homelab_cidr() {
    _env_python ensure-cidr
}

write_homelab_htpasswd() {
    _env_python write-htpasswd
}

validate_homelab_env() {
    _env_python validate
}

# Exporta só chaves conhecidas (sem source cego do .env).
load_homelab_env() {
    local exported
    exported="$(_env_python export)"
    if [[ -n "${exported}" ]]; then
        eval "${exported}"
    fi
}
