#!/usr/bin/env bash
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
rm -f "$REPO_ROOT/.kstack/state/audit-outdated/deprecated-apis-backend"
