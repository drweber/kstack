#!/usr/bin/env bash
# Remove the deprecated-APIs backend preference seeded by wait.sh so the
# eval doesn't leak host state across scenarios.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
rm -f "$REPO_ROOT/.kstack/state/audit-outdated/deprecated-apis-backend"
