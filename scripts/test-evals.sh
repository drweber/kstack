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

# scripts/test-evals.sh — run the kstack eval harness.
#
# For each scenario under tests/evals/scenarios/:
#   1. Plant fixtures in a dedicated namespace.
#   2. Wait for the planted state to stabilize.
#   3. Invoke the skill via `claude -p` N times.
#   4. Score each run with keyword/structured/judge rules.
#   5. Scenario passes iff >= pass_threshold runs pass.
#
# Requires: kind, kubectl, docker, claude, jq, yq, bash.
# Requires: ANTHROPIC_API_KEY in the environment, OR Claude Code app auth
#           (set KSTACK_EVAL_USE_CLI_AUTH=1 to skip the API key check and
#           rely on the locally-running Claude Code app for credentials).
#
# Env overrides:
#   KSTACK_EVAL_MAX_RUNS      force `runs` per scenario (CI sets this to 1 or 3)
#   KSTACK_EVAL_BUDGET_USD    hard cap on cumulative Claude API spend
#   KSTACK_KIND_CLUSTER       kind cluster name (default: kstack-test)
#   KSTACK_REUSE_CLUSTER      adopt existing cluster; skip teardown
#                             (default: 1 — set to 0 to force teardown)
#   KSTACK_EVAL_USE_CLI_AUTH=1  skip ANTHROPIC_API_KEY check; use Claude Code app auth
#
# Flags:
#   --scenario <id>           run only a single scenario by directory name
#   --include-placeholder     also run scenarios flagged `placeholder: true`
#   -h | --help               print this message
set -eu

# Eval runs iterate fast — reuse the kind cluster across invocations by
# default. Override with KSTACK_REUSE_CLUSTER=0 to force teardown on exit.
export KSTACK_REUSE_CLUSTER="${KSTACK_REUSE_CLUSTER:-1}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVAL_DIR="$REPO_ROOT/tests/evals"
SCENARIO_ROOT="$EVAL_DIR/scenarios"
ARTIFACTS_ROOT="$EVAL_DIR/artifacts"

SINGLE_SCENARIO=""
INCLUDE_PLACEHOLDER=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scenario)
      SINGLE_SCENARIO="${2:-}"; shift 2 ;;
    --include-placeholder)
      INCLUDE_PLACEHOLDER=1; shift ;;
    -h|--help)
      sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

_die() { echo "error: $*" >&2; exit 1; }
_have() { command -v "$1" >/dev/null 2>&1; }

if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ "${KSTACK_EVAL_USE_CLI_AUTH:-0}" != "1" ]; then
  echo "# ANTHROPIC_API_KEY not set — skipping eval tier" >&2
  echo "# (set KSTACK_EVAL_USE_CLI_AUTH=1 to use Claude Code app auth instead)" >&2
  exit 0
fi

for cmd in kind kubectl docker claude jq yq; do
  if ! _have "$cmd"; then
    echo "# missing required command: $cmd — skipping eval tier" >&2
    echo "# install kind, kubectl, docker, claude, jq, yq to run evals" >&2
    exit 0
  fi
done

# shellcheck source=../tests/e2e/lib/kind-cluster.sh
. "$REPO_ROOT/tests/e2e/lib/kind-cluster.sh"
# shellcheck source=../tests/evals/lib/runner.sh
. "$EVAL_DIR/lib/runner.sh"

mkdir -p "$ARTIFACTS_ROOT"
export EVAL_ARTIFACTS_DIR="$ARTIFACTS_ROOT"
export EVAL_INCLUDE_PLACEHOLDER="$INCLUDE_PLACEHOLDER"
export EVAL_BUDGET_USD="${KSTACK_EVAL_BUDGET_USD:-}"

KUBECONFIG_PATH="$ARTIFACTS_ROOT/.kubeconfig"
kstack_kind_up "$KUBECONFIG_PATH"

cleanup() {
  kstack_kind_down
}
trap cleanup EXIT

declare -a scenarios=()
if [ -n "$SINGLE_SCENARIO" ]; then
  scenarios=("$SCENARIO_ROOT/$SINGLE_SCENARIO")
  [ -d "${scenarios[0]}" ] || _die "no such scenario: $SINGLE_SCENARIO"
else
  while IFS= read -r dir; do
    scenarios+=("$dir")
  done < <(find "$SCENARIO_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
fi

if [ "${#scenarios[@]}" -eq 0 ]; then
  echo "# no scenarios found under $SCENARIO_ROOT" >&2
  exit 0
fi

echo "# running ${#scenarios[@]} scenario(s)"
failures=0
for dir in "${scenarios[@]}"; do
  if ! eval_run_scenario "$dir"; then
    failures=$((failures + 1))
  fi
done

printf '\n== summary ==\n'
printf 'scenarios: %d   failures: %d   cumulative_cost_usd: %s\n' \
  "${#scenarios[@]}" "$failures" "${EVAL_TOTAL_COST_USD:-0}"

[ "$failures" -eq 0 ]
