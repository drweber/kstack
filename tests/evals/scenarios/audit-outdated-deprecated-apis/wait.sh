#!/usr/bin/env bash
# Pin the deprecated-APIs backend to "web" so scripts/main fetches the
# kubernetes.io deprecation guide instead of expecting pluto/kubent.
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PREF_DIR="$REPO_ROOT/.kstack/state/audit-outdated"
mkdir -p "$PREF_DIR"
echo web > "$PREF_DIR/deprecated-apis-backend"
