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

# Unit tests for src/skills/cluster-status/scripts/lib/pod-info.sh.
# The lib is sourced (not executed); each test writes a minimal pods.json
# fixture and calls pod_info::render directly.

setup() {
  load '../test_helper.bash'
  common_setup
  PODS_JSON="$TMPDIR_TEST/pods.json"
  # shellcheck source=../../skills/cluster-status/scripts/lib/pod-info.sh
  . "$SRC_ROOT/skills/cluster-status/scripts/lib/pod-info.sh"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

write_pods() { printf '%s' "$1" > "$PODS_JSON"; }

ready_pod() {
  local ns="${1:-default}" name="${2:-app}"
  printf '{
    "metadata":{"namespace":"%s","name":"%s"},
    "spec":{"containers":[{"name":"c"}]},
    "status":{
      "phase":"Running",
      "containerStatuses":[{"ready":true,"restartCount":0}]
    }
  }' "$ns" "$name"
}

crashing_pod() {
  local ns="${1:-default}" name="${2:-app}" restarts="${3:-5}"
  printf '{
    "metadata":{"namespace":"%s","name":"%s"},
    "spec":{"containers":[{"name":"c"}]},
    "status":{
      "phase":"Running",
      "containerStatuses":[{
        "ready":false,
        "restartCount":%s,
        "state":{"waiting":{"reason":"CrashLoopBackOff"}}
      }]
    }
  }' "$ns" "$name" "$restarts"
}

succeeded_pod() {
  local ns="${1:-default}" name="${2:-job-pod}"
  printf '{
    "metadata":{"namespace":"%s","name":"%s"},
    "spec":{"containers":[{"name":"c"}]},
    "status":{"phase":"Succeeded","containerStatuses":[{"ready":false,"restartCount":0}]}
  }' "$ns" "$name"
}

pods_list() {
  printf '{"kind":"List","items":[%s]}' "$(IFS=,; echo "$*")"
}

# ---------------------------------------------------------------------------
# Summary line
# ---------------------------------------------------------------------------

@test "summary: empty cluster" {
  write_pods '{"kind":"List","items":[]}'
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0/0 Ready"* ]]
}

@test "summary: all pods ready" {
  write_pods "$(pods_list "$(ready_pod ns-a pod-1)" "$(ready_pod ns-b pod-2)")"
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2/2 Ready"* ]]
}

@test "summary: counts non-ready pods" {
  write_pods "$(pods_list "$(ready_pod)" "$(crashing_pod)")"
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1/2 Ready"* ]]
}

@test "summary: counts pods with restarts" {
  write_pods "$(pods_list "$(ready_pod)" "$(crashing_pod default crasher 3)")"
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 pod(s) with restarts"* ]]
}

@test "summary: excludes succeeded pods from counts" {
  write_pods "$(pods_list "$(ready_pod)" "$(succeeded_pod)")"
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1/1 Ready"* ]]
}

@test "summary: output begins with 'Pods'" {
  write_pods '{"kind":"List","items":[]}'
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == Pods* ]]
}

# ---------------------------------------------------------------------------
# No Issues block — agent derives issues from cache_dir/pods.json
# ---------------------------------------------------------------------------

@test "does not emit an Issues block when pods are healthy" {
  write_pods "$(pods_list "$(ready_pod)" "$(ready_pod ns-b pod-2)")"
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Issues"* ]]
}

@test "does not emit an Issues block when pods are crashing" {
  write_pods "$(pods_list "$(crashing_pod)" "$(crashing_pod ns-b pod-2 10)")"
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Issues"* ]]
}

@test "output is a single line" {
  write_pods "$(pods_list "$(ready_pod)" "$(crashing_pod)")"
  run pod_info::render "$PODS_JSON"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}
