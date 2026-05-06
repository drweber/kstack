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

# scripts/lint.sh — shellcheck every shell file in the repo that's expected
# to pass clean. Called by CI and runnable locally.
#
# Requires shellcheck (brew install shellcheck, or apt install shellcheck).
# `.bats` files are intentionally excluded for now — they have SC2164/SC2314
# findings that need to be cleaned up before they can join the lint set.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found. Install with:" >&2
  echo "  brew install shellcheck       # macOS" >&2
  echo "  apt install shellcheck        # Debian/Ubuntu" >&2
  exit 1
fi

# Keep this list in sync with CLAUDE.md ("lint" description).
exec shellcheck --severity=warning --external-sources \
  scripts/install \
  src/bin/check-update src/bin/dismiss-update src/bin/entrypoint src/bin/uninstall src/bin/upgrade \
  src/lib/*.sh scripts/*.sh \
  src/skills/cluster-status/scripts/main \
  src/skills/cluster-status/scripts/lib/*.sh \
  src/skills/events/scripts/main \
  src/skills/metrics/scripts/main \
  src/skills/audit-outdated/scripts/main \
  src/skills/audit-outdated/scripts/version-skew \
  src/skills/audit-outdated/scripts/deprecated-apis \
  src/skills/audit-outdated/scripts/lib/*.sh \
  tests/test_helper.bash \
  tests/e2e/setup_suite.bash \
  tests/e2e/lib/*.sh \
  tests/evals/lib/*.sh
