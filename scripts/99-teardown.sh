#!/usr/bin/env bash
# Delete the demo clusters and generated files. Safe to rerun.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

for site in site-a site-b; do
    if kind get clusters 2>/dev/null | grep -qx "$site"; then
        kind delete cluster --name "$site"
    fi
done

# .venv is kept on purpose — cheap to keep, slow to rebuild. Delete manually
# if you want a truly pristine tree: rm -rf .venv
rm -rf "$REPO_ROOT/.kube" "$REPO_ROOT/.charts"
echo "Demo environment removed."
