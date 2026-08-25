#!/usr/bin/env bash
# Create the demo environment: two kind clusters ("sites"), pre-loaded images,
# pre-pulled Helm chart, installed Ansible deps. Idempotent — safe to rerun.
#
# Takes ~3-5 minutes on first run.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
KUBE_DIR="$REPO_ROOT/.kube"
CHART_DIR="$REPO_ROOT/.charts"
SITES=(site-a site-b)

# Images used by the playbooks; pre-loading them into kind makes the live
# demo work without network access.
IMAGES=(
    nginx:1.27-alpine
    python:3.12-slim
    ghcr.io/stefanprodan/podinfo:6.7.1
)
PODINFO_CHART_VERSION="6.7.1"

mkdir -p "$KUBE_DIR" "$CHART_DIR"

# All Python bits live in a venv — system Python is never touched.
echo "== Python virtualenv =="
if [ -z "${VIRTUAL_ENV:-}" ]; then
    VENV_DIR="$REPO_ROOT/.venv"
    if [ ! -d "$VENV_DIR" ]; then
        echo "  creating $VENV_DIR"
        python3 -m venv "$VENV_DIR"
    fi
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    echo "  using $VENV_DIR — activate it in your shell too: source .venv/bin/activate"
else
    echo "  using already-active venv: $VIRTUAL_ENV"
fi
pip install -q --upgrade pip
pip install -q ansible-core -r "$REPO_ROOT/requirements.txt"

echo
echo "== Ansible collection =="
ansible-galaxy collection install -r "$REPO_ROOT/requirements.yml"

echo
echo "== kind clusters =="
for site in "${SITES[@]}"; do
    if kind get clusters 2>/dev/null | grep -qx "$site"; then
        echo "  cluster '$site' already exists — refreshing kubeconfig"
        kind export kubeconfig --name "$site" --kubeconfig "$KUBE_DIR/$site.yaml"
    else
        echo "  creating cluster '$site'"
        kind create cluster --name "$site" --kubeconfig "$KUBE_DIR/$site.yaml" --wait 120s
    fi
done

echo
echo "== Pre-pulling images and loading them into the clusters =="
for image in "${IMAGES[@]}"; do
    docker pull -q "$image"
    for site in "${SITES[@]}"; do
        kind load docker-image "$image" --name "$site"
    done
done

echo
echo "== Pre-pulling the podinfo chart (offline fallback) =="
helm repo add podinfo https://stefanprodan.github.io/podinfo >/dev/null 2>&1 || true
helm repo update podinfo >/dev/null 2>&1 || true
if [ ! -f "$CHART_DIR/podinfo-$PODINFO_CHART_VERSION.tgz" ]; then
    helm pull podinfo/podinfo --version "$PODINFO_CHART_VERSION" -d "$CHART_DIR" \
        || echo "  (chart pull failed — playbook 02 will need network access)"
fi

echo
echo "== Smoke test =="
for site in "${SITES[@]}"; do
    kubectl --kubeconfig "$KUBE_DIR/$site.yaml" get nodes --no-headers
done

cat <<EOF

Setup complete. Kubeconfigs: $KUBE_DIR/{site-a,site-b}.yaml
Next:
  source $VIRTUAL_ENV/bin/activate   # the venv used by this setup
  cd $REPO_ROOT
  ansible-playbook playbooks/01-resources.yml
EOF
