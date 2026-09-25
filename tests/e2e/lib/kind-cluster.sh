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

# tests/e2e/lib/kind-cluster.sh — shared kind-cluster lifecycle.
#
# Sourced by tests/e2e/setup_suite.bash (bats e2e tier) and by
# scripts/test-evals.sh (eval harness) so both tiers bring up and tear
# down the same `kstack-test` cluster the same way.
#
# Env:
#   KSTACK_KIND_CLUSTER     name of the kind cluster (default: kstack-test)
#   KSTACK_KIND_NODE_IMAGE  node image to boot (default: the pin below)
#   KSTACK_REUSE_CLUSTER    if =1, adopt an existing cluster and skip teardown
#
# Functions (all use $KUBECONFIG_PATH_VAR to let callers choose where to
# stash the kubeconfig; defaults to a file under the caller's tmpdir):
#
#   kstack_kind_check_prereqs [skip_var_name]
#     Check that `kind`, `kubectl`, and `docker` are on PATH. On missing
#     deps, prints a skip message and (if skip_var_name given) sets the
#     named variable to "1" via eval so the caller can short-circuit.
#     Returns nonzero on missing deps.
#
#   kstack_kind_up <kubeconfig_path>
#     Create (or adopt) the cluster. Writes kubeconfig to the given path
#     and exports KUBECONFIG to point at it.
#
#   kstack_kind_down
#     Delete the cluster unless KSTACK_REUSE_CLUSTER=1.

KSTACK_KIND_CLUSTER="${KSTACK_KIND_CLUSTER:-kstack-test}"

# Pin the Kubernetes version the cluster tiers run against. Without --image,
# kind boots whatever its own release happens to default to, so the tested
# server version changes silently whenever the kind pin moves. The digest is
# kind's own recommendation — a tag can be re-pushed, a digest can't.
#
# To bump: take the node image and digest from the release notes of the kind
# version installed in .github/workflows/ci.yml, and move KUBECTL_VERSION there
# to the same minor.
KSTACK_KIND_NODE_IMAGE="${KSTACK_KIND_NODE_IMAGE:-kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5}"

_kstack_require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

kstack_kind_check_prereqs() {
  local skip_var="${1:-}"
  local missing=()
  local cmd
  for cmd in kind kubectl docker; do
    if ! _kstack_require_cmd "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "# kstack kind prereqs missing: ${missing[*]}" >&2
    if [ -n "$skip_var" ]; then
      eval "$skip_var=1"
    fi
    return 1
  fi
  return 0
}

kstack_kind_up() {
  local kubeconfig="$1"
  if [ -z "$kubeconfig" ]; then
    echo "kstack_kind_up: kubeconfig path required" >&2
    return 2
  fi

  if kind get clusters 2>/dev/null | grep -qx "$KSTACK_KIND_CLUSTER"; then
    echo "# adopting existing kind cluster: $KSTACK_KIND_CLUSTER" >&2
  else
    echo "# creating kind cluster: $KSTACK_KIND_CLUSTER" >&2
    kind create cluster --name "$KSTACK_KIND_CLUSTER" \
      --image "$KSTACK_KIND_NODE_IMAGE" --wait 90s >&2
  fi

  kind get kubeconfig --name "$KSTACK_KIND_CLUSTER" > "$kubeconfig"
  export KUBECONFIG="$kubeconfig"
  export KSTACK_KIND_CLUSTER
}

kstack_kind_down() {
  if [ "${KSTACK_REUSE_CLUSTER:-0}" = "1" ]; then
    echo "# KSTACK_REUSE_CLUSTER=1 — leaving $KSTACK_KIND_CLUSTER running" >&2
    return 0
  fi
  if _kstack_require_cmd kind; then
    echo "# deleting kind cluster: $KSTACK_KIND_CLUSTER" >&2
    kind delete cluster --name "$KSTACK_KIND_CLUSTER" >&2 || true
  fi
}
