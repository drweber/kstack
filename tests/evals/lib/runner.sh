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

# tests/evals/lib/runner.sh — per-scenario loop for the kstack eval harness.
#
# Sourced by scripts/test-evals.sh. Assumes a kind cluster is already up
# and $KUBECONFIG points at it. Expects `kubectl`, `yq`, `jq`, and
# `claude` on PATH.
#
# Exports:
#   EVAL_ARTIFACTS_DIR    where each scenario's artifacts are written
#   EVAL_TOTAL_COST_USD   running sum of judge + skill invocation costs
#   EVAL_BUDGET_USD       optional hard cap; runner exits early once hit

_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_RUNNER_REPO_ROOT="$(cd "$_RUNNER_DIR/../../.." && pwd)"
# shellcheck source=claude-cli.sh
. "$_RUNNER_DIR/claude-cli.sh"
# shellcheck source=scoring.sh
. "$_RUNNER_DIR/scoring.sh"

EVAL_TOTAL_COST_USD="${EVAL_TOTAL_COST_USD:-0}"

_eval_log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2
}

_eval_timeout() {
  # Portable timeout: GNU timeout, then gtimeout (brew install coreutils on macOS),
  # then fall back to running without a timeout (dev machines only).
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    "$@"
  fi
}

_eval_scenario_field() {
  local scenario_file="$1" path="$2" default="${3:-}"
  local value
  value=$(yq -r "$path // \"\"" "$scenario_file")
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

_eval_add_cost() {
  local delta="$1"
  EVAL_TOTAL_COST_USD=$(awk -v a="$EVAL_TOTAL_COST_USD" -v b="$delta" \
    'BEGIN { printf "%.6f", a + b }')
}

_eval_run_teardown() {
  local id="$1" dir="$2" namespace="$3" artifact_dir="$4"
  [ -x "$dir/teardown.sh" ] || return 0
  _eval_log "[$id] running teardown.sh"
  _eval_timeout 60 "$dir/teardown.sh" "$namespace" \
    > "$artifact_dir/teardown.log" 2>&1 \
    || _eval_log "[$id] teardown.sh failed — see $artifact_dir/teardown.log"
}

_eval_budget_exceeded() {
  [ -n "${EVAL_BUDGET_USD:-}" ] || return 1
  awk -v s="$EVAL_TOTAL_COST_USD" -v b="$EVAL_BUDGET_USD" \
    'BEGIN { exit !(s >= b) }'
}

eval_run_scenario() {
  # Args: $1 = scenario dir (absolute path).
  # Prints a one-line summary to stdout; returns 0 on pass, nonzero on fail.
  local dir="$1"
  local id scenario_file expected_file
  id=$(basename "$dir")
  scenario_file="$dir/scenario.yaml"
  expected_file="$dir/expected.yaml"

  if [ ! -f "$scenario_file" ] || [ ! -f "$expected_file" ]; then
    _eval_log "[$id] missing scenario.yaml or expected.yaml — skipping"
    return 2
  fi

  local placeholder
  placeholder=$(_eval_scenario_field "$scenario_file" '.placeholder' 'false')
  if [ "$placeholder" = "true" ] && [ "${EVAL_INCLUDE_PLACEHOLDER:-0}" != "1" ]; then
    _eval_log "[$id] placeholder scenario — skipping (pass --include-placeholder to run)"
    return 0
  fi

  local namespace runs pass_threshold wait_seconds model allowed_tools
  namespace=$(_eval_scenario_field "$scenario_file" '.namespace' "eval-$id")
  runs=$(_eval_scenario_field "$scenario_file" '.runs' "${KSTACK_EVAL_MAX_RUNS:-3}")
  if [ -n "${KSTACK_EVAL_MAX_RUNS:-}" ]; then
    runs="$KSTACK_EVAL_MAX_RUNS"
  fi
  pass_threshold=$(_eval_scenario_field "$scenario_file" '.pass_threshold' '')
  if [ -z "$pass_threshold" ]; then
    # Default: majority of runs must pass (rounded up).
    pass_threshold=$(( (runs + 1) / 2 ))
  fi
  wait_seconds=$(_eval_scenario_field "$scenario_file" '.wait_seconds' '60')
  model=$(_eval_scenario_field "$scenario_file" '.claude_flags.model' '')
  if [ -n "${KSTACK_EVAL_MODEL:-}" ]; then
    model="$KSTACK_EVAL_MODEL"
  fi
  allowed_tools=$(_eval_scenario_field "$scenario_file" '.claude_flags.allowed_tools' 'Bash,Read,Grep')

  local artifact_dir="$EVAL_ARTIFACTS_DIR/$id"
  rm -rf "$artifact_dir"
  mkdir -p "$artifact_dir"

  # Wipe the kstack kube-cache so the agent's first cache-aware fetch in
  # this scenario picks up the planted fixture instead of a snapshot left
  # behind by an earlier scenario in the same session.
  rm -rf "$_RUNNER_REPO_ROOT/.kstack/cache/kube" 2>/dev/null || true

  _eval_log "[$id] creating namespace $namespace"
  kubectl create namespace "$namespace" >/dev/null 2>&1 || true
  kubectl label namespace "$namespace" "kstack-eval/scenario=$id" --overwrite >/dev/null

  if [ -f "$dir/fixture.yaml" ]; then
    kubectl apply -f "$dir/fixture.yaml" -n "$namespace" > "$artifact_dir/apply.log" 2>&1 \
      || { _eval_log "[$id] kubectl apply failed — see $artifact_dir/apply.log"
           _eval_cleanup_namespace "$namespace"; return 1; }
  fi

  if [ -x "$dir/wait.sh" ]; then
    _eval_log "[$id] waiting for readiness (up to ${wait_seconds}s)"
    if ! _eval_timeout "$wait_seconds" "$dir/wait.sh" "$namespace" > "$artifact_dir/wait.log" 2>&1; then
      _eval_log "[$id] wait.sh did not succeed within ${wait_seconds}s"
      _eval_run_teardown "$id" "$dir" "$namespace" "$artifact_dir"
      _eval_cleanup_namespace "$namespace"
      return 1
    fi
  fi

  kubectl get all,events -n "$namespace" -o yaml > "$artifact_dir/before.yaml" 2>/dev/null || true

  local prompt=""
  if [ -f "$dir/prompt.txt" ]; then
    prompt=$(cat "$dir/prompt.txt")
  fi

  local passes=0 run_results_file="$artifact_dir/runs.jsonl"
  : > "$run_results_file"

  local i
  for ((i = 1; i <= runs; i++)); do
    if _eval_budget_exceeded; then
      _eval_log "[$id] budget \$$EVAL_BUDGET_USD reached (cumulative \$$EVAL_TOTAL_COST_USD); stopping"
      break
    fi

    local transcript="$artifact_dir/run-$i.jsonl"
    local run_stderr="$artifact_dir/run-$i.stderr"
    _eval_log "[$id] run $i/$runs: invoking claude"
    if ! eval_claude_run "$transcript" "$allowed_tools" "$model" "$prompt" "$run_stderr"; then
      _eval_log "[$id] run $i: claude invocation failed (see $run_stderr)"
      printf '{"run":%d,"pass":false,"reason":"claude invocation failed"}\n' "$i" \
        >> "$run_results_file"
      continue
    fi

    local final_text usage cost
    final_text=$(eval_claude_final_text "$transcript" || echo "")
    usage=$(eval_claude_usage_json "$transcript")
    cost=$(printf '%s' "$usage" | jq -r '.total_cost_usd // 0')
    _eval_add_cost "$cost"
    printf '%s\n' "$final_text" > "$artifact_dir/run-$i.text"

    # 1. Keyword pre-flight. A failure short-circuits this run.
    local keyword_result
    keyword_result=$(eval_score_keywords "$final_text" "$expected_file")
    if [ "$(printf '%s' "$keyword_result" | jq -r .pass)" != "true" ]; then
      _eval_log "[$id] run $i: keyword check failed"
      printf '%s\n' "$keyword_result" \
        | jq -c --argjson run "$i" '. + {run:$run}' \
        >> "$run_results_file"
      continue
    fi

    # 2. Structured JSON scoring when the rubric defines it AND Claude's
    # final message is parseable JSON. Both conditions must hold — skip
    # silently if not.
    local structured_defined structured_result=""
    structured_defined=$(yq -r '.structured // "" | tag' "$expected_file" 2>/dev/null || echo '')
    if [ -n "$structured_defined" ] && [ "$structured_defined" != "!!null" ]; then
      local parsed_json
      parsed_json=$(eval_extract_final_json "$final_text" 2>/dev/null || echo '{}')
      if [ -n "$parsed_json" ] && [ "$parsed_json" != "{}" ]; then
        structured_result=$(eval_score_structured "$parsed_json" "$expected_file")
      fi
    fi

    # 3. Judge: only runs when the rubric defines judge_criteria. Skipped
    # if structured scoring already decided the outcome by failing (no
    # point paying for a second opinion).
    local judge_result=""
    local judge_criteria
    judge_criteria=$(yq -r '.rubric.judge_criteria // ""' "$expected_file")
    if [ -n "$judge_criteria" ] && \
       { [ -z "$structured_result" ] || \
         [ "$(printf '%s' "$structured_result" | jq -r .pass)" = "true" ]; }; then
      judge_result=$(eval_score_judge "$final_text" "$expected_file" "$model" \
        "$artifact_dir/run-$i.judge.stderr")
      printf '%s\n' "$judge_result" > "$artifact_dir/run-$i.judge.json"
    fi

    # Pass iff structured scoring (when run) passed AND judge (when run) passed.
    local run_pass="true" run_reason="run passed"
    if [ -n "$structured_result" ] && \
       [ "$(printf '%s' "$structured_result" | jq -r .pass)" != "true" ]; then
      run_pass="false"
      run_reason=$(printf '%s' "$structured_result" | jq -r .reason)
    fi
    if [ "$run_pass" = "true" ] && [ -n "$judge_result" ] && \
       [ "$(printf '%s' "$judge_result" | jq -r .pass)" != "true" ]; then
      run_pass="false"
      run_reason=$(printf '%s' "$judge_result" | jq -r .reason)
    fi

    jq -cn \
      --argjson run "$i" \
      --argjson pass "$( [ "$run_pass" = "true" ] && echo true || echo false )" \
      --arg reason "$run_reason" \
      --argjson usage "$usage" \
      '{run:$run, pass:$pass, reason:$reason, usage:$usage}' \
      >> "$run_results_file"

    if [ "$run_pass" = "true" ]; then
      passes=$((passes + 1))
    fi
  done

  # Build per-scenario summary.
  local scenario_pass="false"
  if [ "$passes" -ge "$pass_threshold" ]; then
    scenario_pass="true"
  fi

  jq -cn \
    --arg id "$id" \
    --argjson runs "$runs" \
    --argjson passes "$passes" \
    --argjson threshold "$pass_threshold" \
    --argjson pass "$( [ "$scenario_pass" = "true" ] && echo true || echo false )" \
    '{id:$id, runs:$runs, passes:$passes, threshold:$threshold, pass:$pass}' \
    > "$artifact_dir/summary.json"

  _eval_run_teardown "$id" "$dir" "$namespace" "$artifact_dir"

  _eval_cleanup_namespace "$namespace"

  local colour reset="\033[0m"
  if [ "$scenario_pass" = "true" ]; then
    colour="\033[32m"
  else
    colour="\033[31m"
  fi
  printf '%b%s%b  %s  passes=%d/%d threshold=%d\n' \
    "$colour" "$( [ "$scenario_pass" = "true" ] && echo PASS || echo FAIL )" "$reset" \
    "$id" "$passes" "$runs" "$pass_threshold"

  [ "$scenario_pass" = "true" ]
}

_eval_cleanup_namespace() {
  local namespace="$1"
  kubectl delete namespace "$namespace" --wait=false >/dev/null 2>&1 || true
}
