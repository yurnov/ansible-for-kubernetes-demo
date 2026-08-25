#!/usr/bin/env bash
# Verify everything needed for the demo is installed. Read-only, safe to rerun.
# Python-side dependencies (ansible-core, kubernetes package, collection) are
# NOT required here — scripts/01-setup.sh provisions them into ./.venv.
set -euo pipefail

fail=0

check_bin() {
    local bin="$1" hint="$2"
    if command -v "$bin" >/dev/null 2>&1; then
        # kubectl and helm do not accept a bare --version
        local version
        case "$bin" in
            kubectl) version=$(kubectl version --client 2>&1 | head -1) ;;
            helm) version=$(helm version --short 2>&1 | head -1) ;;
            *) version=$("$bin" --version 2>&1 | head -1) ;;
        esac
        printf '  [ok]   %-16s %s\n' "$bin" "$version"
    else
        printf '  [MISS] %-16s -> %s\n' "$bin" "$hint"
        fail=$((fail + 1))
    fi
}

echo "== Required binaries =="
check_bin docker "https://docs.docker.com/get-docker/ (or podman with a docker alias)"
check_bin kind "https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
check_bin kubectl "https://kubernetes.io/docs/tasks/tools/"
check_bin helm "https://helm.sh/docs/intro/install/"
check_bin python3 "your distro's package manager (3.10+ with the venv module)"

echo
echo "== Python venv module =="
if python3 -m venv --help >/dev/null 2>&1; then
    echo "  [ok]   python3 -m venv available"
else
    echo "  [MISS] python3 venv module -> e.g. apt install python3-venv"
    fail=$((fail + 1))
fi

echo
echo "== Ansible (informational — 01-setup.sh provisions ./.venv if needed) =="
if [ -n "${VIRTUAL_ENV:-}" ]; then
    echo "  [info] active venv: $VIRTUAL_ENV"
elif [ -d "$(dirname "$0")/../.venv" ]; then
    echo "  [info] ./.venv exists — activate it: source .venv/bin/activate"
else
    echo "  [info] no venv yet — 01-setup.sh will create ./.venv with ansible-core + deps"
fi

echo
if [ "$fail" -gt 0 ]; then
    echo "$fail check(s) failed — fix the [MISS] lines above, then run scripts/01-setup.sh"
    exit 1
fi
echo "All required checks passed — run scripts/01-setup.sh next."
