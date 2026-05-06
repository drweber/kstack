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

# scripts/test-e2e.sh — run the e2e (cluster-backed) bats tier.
#
# Spins up a kind cluster via tests/e2e/setup_suite.bash, runs the tests,
# and tears the cluster down. Set KSTACK_REUSE_CLUSTER=1 to keep the
# cluster alive across runs for faster iteration.
#
# Requires: bats-core, kind, kubectl, docker.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  echo "bats not found. Install with:" >&2
  echo "  brew install bats-core        # macOS" >&2
  echo "  apt install bats              # Debian/Ubuntu" >&2
  exit 1
fi

exec bats "$REPO_ROOT/tests/e2e"
