#!/usr/bin/env bash
# Pre-seed the deprecated-APIs backend preference to "skip" so /audit-outdated
# doesn't enter the needs_setup prompt-the-user flow during scoring (the
# eval has no user to pick a backend). The dev install lives at
# <repo>/.kstack/, so the preference file is at
# <repo>/.kstack/state/audit-outdated/deprecated-apis-backend.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PREF_DIR="$REPO_ROOT/.kstack/state/audit-outdated"

mkdir -p "$PREF_DIR"
echo skip > "$PREF_DIR/deprecated-apis-backend"
