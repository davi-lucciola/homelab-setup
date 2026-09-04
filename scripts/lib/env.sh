#!/usr/bin/env bash
# Helpers de .env. Deve ser sourced; não executar diretamente.

if [[ -z "${HOMELAB_ROOT:-}" ]]; then
    HOMELAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

ensure_dockge_stacks_dir() {
    local env_file="${HOMELAB_ROOT}/.env"
    local stacks_dir="${HOMELAB_ROOT}/stacks"

    if [[ ! -f "${env_file}" ]]; then
        return 0
    fi

    if grep -q '^DOCKGE_STACKS_DIR=' "${env_file}"; then
        local current
        current="$(grep '^DOCKGE_STACKS_DIR=' "${env_file}" | tail -n1 | cut -d= -f2-)"
        if [[ -z "${current}" ]]; then
            local tmp
            tmp="$(mktemp)"
            awk -v v="${stacks_dir}" '
                BEGIN { done = 0 }
                /^DOCKGE_STACKS_DIR=/ && !done {
                    print "DOCKGE_STACKS_DIR=" v
                    done = 1
                    next
                }
                { print }
            ' "${env_file}" > "${tmp}"
            mv "${tmp}" "${env_file}"
        fi
    else
        printf '\nDOCKGE_STACKS_DIR=%s\n' "${stacks_dir}" >> "${env_file}"
    fi
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
