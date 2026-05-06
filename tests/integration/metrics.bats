#!/usr/bin/env bats

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

setup() {
  load '../test_helper.bash'
  common_setup
  export KSTACK_ROOT="$TMPDIR_TEST/kstack"
  mkdir -p "$KSTACK_ROOT/lib"
  cp "$SRC_ROOT/lib/response.sh" "$KSTACK_ROOT/lib/"
  export KSTACK_KUBE_CONTEXT="test-ctx"
  export KSTACK_SKILL_NAME="metrics"
}

# ---------------------------------------------------------------------------
# Static checks
# ---------------------------------------------------------------------------

@test "main script exists and is executable" {
  [ -x "$SRC_ROOT/skills/metrics/scripts/main" ]
}

# ---------------------------------------------------------------------------
# Error paths
# ---------------------------------------------------------------------------

@test "main: rejects unknown flag" {
  run "$SRC_ROOT/skills/metrics/scripts/main" --bogus
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"Unknown flag"* ]]
}

@test "main: ignores free-text positional args (agent hint)" {
  use_mocks
  write_kubectl_stub '
  top) exit 0 ;;
  get) printf "{\"items\":[]}\n" ;;
'
  run "$SRC_ROOT/skills/metrics/scripts/main" pods in kube-system
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"render":"agent"'* ]]
}

@test "main: rejects --context (entrypoint owns resolution)" {
  run "$SRC_ROOT/skills/metrics/scripts/main" --context=foo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"kind":"user"'* ]]
}

@test "main: requires KSTACK_KUBE_CONTEXT env var" {
  unset KSTACK_KUBE_CONTEXT
  run "$SRC_ROOT/skills/metrics/scripts/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *"KSTACK_KUBE_CONTEXT"* ]]
}

@test "main: requires KSTACK_ROOT env var" {
  unset KSTACK_ROOT
  run "$SRC_ROOT/skills/metrics/scripts/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *"KSTACK_ROOT"* ]]
}

# ---------------------------------------------------------------------------
# Source detection
# ---------------------------------------------------------------------------

@test "main: emits ok/agent envelope with kube_context" {
  use_mocks
  write_stub kubectl 'exit 0'
  run "$SRC_ROOT/skills/metrics/scripts/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"render":"agent"'* ]]
  [[ "$output" == *'"kube_context":"test-ctx"'* ]]
}

@test "main: reports metrics-server available when 'kubectl top nodes' succeeds" {
  use_mocks
  write_kubectl_stub '
  top) exit 0 ;;
  get) printf "{\"items\":[]}\n" ;;
'
  run "$SRC_ROOT/skills/metrics/scripts/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'metrics-server'* ]]
  [[ "$output" == *'available'* ]]
}

@test "main: reports metrics-server unavailable when 'kubectl top' fails" {
  use_mocks
  write_kubectl_stub '
  top) echo "error: Metrics API not available" >&2; exit 1 ;;
  get) printf "{\"items\":[]}\n" ;;
'
  run "$SRC_ROOT/skills/metrics/scripts/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'metrics-server'* ]]
  [[ "$output" == *'unavailable'* ]]
}

@test "main: reports prometheus when service named 'prometheus' is found" {
  use_mocks
  write_kubectl_stub '
  top) exit 0 ;;
  get)
    cat <<JSON
{"items":[
  {"metadata":{"name":"prometheus-server","namespace":"monitoring"},
   "spec":{"ports":[{"port":9090,"name":"http"}]}}
]}
JSON
    ;;
'
  run "$SRC_ROOT/skills/metrics/scripts/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'prometheus'* ]]
  [[ "$output" == *'monitoring'* ]]
  [[ "$output" == *'9090'* ]]
}

@test "main: reports prometheus not detected when no service matches" {
  use_mocks
  write_kubectl_stub '
  top) exit 0 ;;
  get) printf "{\"items\":[]}\n" ;;
'
  run "$SRC_ROOT/skills/metrics/scripts/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'prometheus'* ]]
  [[ "$output" == *'not detected'* ]]
}

@test "main: missing kubectl returns infra error" {
  use_mocks
  # We need bash + awk reachable but kubectl not. The mechanism varies by OS:
  # - Linux GH-hosted runners ship kubectl in /usr/bin, so we can't keep
  #   /usr/bin on PATH; symlink the deps into MOCK_BIN and curate PATH.
  # - macOS: same story (Homebrew kubectl is on PATH).
  # - Windows-via-Git-Bash: `ln -s` produces a non-executable shim, and bash
  #   has DLL deps in /usr/bin that don't move with a copy. But Git Bash's
  #   /usr/bin doesn't contain kubectl (it's in C:\ProgramData\chocolatey\bin
  #   on GH-hosted runners), so the broad-PATH approach is safe there.
  if [ -n "${MSYSTEM:-}" ] || [[ "${OSTYPE:-}" == msys* ]]; then
    PATH="$MOCK_BIN:/usr/bin:/bin" run "$SRC_ROOT/skills/metrics/scripts/main"
  else
    for tool in bash awk; do
      ln -s "$(command -v "$tool")" "$MOCK_BIN/$tool"
    done
    PATH="$MOCK_BIN" run "$SRC_ROOT/skills/metrics/scripts/main"
  fi
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *'kubectl'* ]]
}
