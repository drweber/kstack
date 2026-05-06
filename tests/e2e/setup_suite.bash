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

# tests/e2e/setup_suite.bash — bats suite-level hook for the e2e tier.
#
# Brings up a kind cluster once before any test in tests/e2e/ runs and
# deletes it once all tests have finished. Individual tests inherit
# KUBECONFIG and talk to the cluster directly.
#
# Env:
#   KSTACK_KIND_CLUSTER   name of the kind cluster (default: kstack-test)
#   KSTACK_REUSE_CLUSTER  if =1, adopt an existing cluster and skip teardown

_E2E_SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/kind-cluster.sh
. "$_E2E_SUITE_DIR/lib/kind-cluster.sh"

setup_suite() {
  if ! kstack_kind_check_prereqs 2>&3; then
    if declare -F skip_suite >/dev/null 2>&1; then
      skip_suite "missing required commands for e2e tier"
    else
      export KSTACK_E2E_SKIP=1
      return 0
    fi
  fi

  kstack_kind_up "$BATS_SUITE_TMPDIR/kubeconfig" 2>&3
}

teardown_suite() {
  if [ "${KSTACK_E2E_SKIP:-0}" = "1" ]; then
    return 0
  fi
  kstack_kind_down 2>&3
}
