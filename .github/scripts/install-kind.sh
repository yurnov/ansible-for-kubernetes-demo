#!/usr/bin/env bash
# Install the newest released kind, for CI.
#
# Not helm/kind-action: that action hardcodes the kind and kubectl versions it
# installs, so its defaults are only ever as fresh as its own last release.
# That is what froze the weekly canary on Kubernetes 1.35 while upstream was
# on 1.37 — see https://github.com/yurnov/ansible-for-kubernetes-demo/issues/1.
#
# The node image is deliberately NOT resolved here. `kind create cluster` with
# no --image uses the default image compiled into the kind binary, which is the
# only kindest/node tag that release is actually tested against. Resolving kind
# and the node image separately is how you end up on an untested pair (kind
# v0.31.0 cannot run kindest/node:v1.37.0).
set -euo pipefail

DEST=${DEST:-/usr/local/bin}

case $(uname -m) in
    x86_64)            arch=amd64 ;;
    aarch64|arm64)     arch=arm64 ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# The releases/latest redirect is plain github.com, so it needs no token and is
# not subject to the 60 requests/hour unauthenticated API limit.
url=$(curl -fsSI -o /dev/null -w '%{redirect_url}' \
    https://github.com/kubernetes-sigs/kind/releases/latest)
version=${url##*/}

if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "could not resolve the latest kind version (got '$version')" >&2
    exit 1
fi

echo "Installing kind $version ($arch)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="https://github.com/kubernetes-sigs/kind/releases/download/$version"

curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
    -o "$tmp/kind-linux-$arch" "$base/kind-linux-$arch"
curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
    -o "$tmp/kind-linux-$arch.sha256sum" "$base/kind-linux-$arch.sha256sum"
(cd "$tmp" && sha256sum -c "kind-linux-$arch.sha256sum")

install -m 0755 "$tmp/kind-linux-$arch" "$DEST/kind"
"$DEST/kind" version
