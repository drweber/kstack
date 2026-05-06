#!/usr/bin/env bash

# Copyright 2026 The Kubetail Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# scripts/test.sh — run the bats test suite.
#
# Default: runs the fast tiers (unit + integration) on every supported OS.
# With --all: additionally runs the e2e tier (requires kind + docker).
#
# Requires bats-core (brew install bats-core, or apt install bats).
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

RUN_E2E=0
for arg in "$@"; do
  case "$arg" in
    --all) RUN_E2E=1 ;;
    -h|--help)
      cat <<EOF
Usage: scripts/test.sh [--all]

  (no flag)  Run fast tiers: tests/unit + tests/integration
  --all      Also run tests/e2e via scripts/test-e2e.sh (requires kind)
EOF
      exit 0
      ;;
    *)
      echo "unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

if ! command -v bats >/dev/null 2>&1; then
  echo "bats not found. Install with:" >&2
  echo "  brew install bats-core        # macOS" >&2
  echo "  apt install bats              # Debian/Ubuntu" >&2
  exit 1
fi

bats "$REPO_ROOT/tests/unit" "$REPO_ROOT/tests/integration"

if [ "$RUN_E2E" = "1" ]; then
  exec "$(dirname "$0")/test-e2e.sh"
fi
