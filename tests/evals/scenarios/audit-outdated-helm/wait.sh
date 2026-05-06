#!/usr/bin/env bash
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PREF_DIR="$REPO_ROOT/.kstack/state/audit-outdated"
mkdir -p "$PREF_DIR"
echo skip > "$PREF_DIR/deprecated-apis-backend"
