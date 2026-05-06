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

load ../test_helper

setup() {
  common_setup
  if [ "${KSTACK_E2E_SKIP:-0}" = "1" ]; then
    skip "e2e prerequisites missing"
  fi
}

@test "kind cluster is reachable via kubectl" {
  run kubectl get nodes --no-headers
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ready"* ]]
}

@test "KUBECONFIG points to the suite tmpdir" {
  [ -n "$KUBECONFIG" ]
  [ -f "$KUBECONFIG" ]
  [[ "$KUBECONFIG" == "$BATS_SUITE_TMPDIR/"* ]]
}

@test "cluster name matches KSTACK_KIND_CLUSTER" {
  run kubectl config current-context
  [ "$status" -eq 0 ]
  [[ "$output" == "kind-$KSTACK_KIND_CLUSTER" ]]
}
