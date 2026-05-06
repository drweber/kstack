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

# Unit tests for src/lib/kube-context.sh. The lib is sourced (not executed).
# kube_context::resolve is the single resolver for the kube context across
# entrypoint and scripts/main: precedence is --context flag > $KSTACK_KUBE_CONTEXT
# env > `kubectl config current-context`.

setup() {
  load '../test_helper.bash'
  common_setup
  unset KSTACK_KUBE_CONTEXT
  # shellcheck source=../../lib/kube-context.sh
  . "$SRC_ROOT/lib/kube-context.sh"
}

# _stub_kubectl emits a stub that returns $MOCK_CONTEXT (default "kc-default")
# for `config current-context`, and fails for anything else. Exit status can
# be forced to 1 via MOCK_CONTEXT_EXIT=1.
_stub_kubectl() {
  use_mocks
  write_stub kubectl "
case \"\$*\" in
  'config current-context')
    [ \"\${MOCK_CONTEXT_EXIT:-0}\" = 1 ] && exit 1
    printf '%s\n' \"\${MOCK_CONTEXT:-kc-default}\"
    ;;
  *) exit 2 ;;
esac
"
}

# ─── flag parsing ──────────────────────────────────────────────

@test "resolve: --context=value sets KSTACK_KUBE_CONTEXT and strips the flag" {
  _stub_kubectl
  kube_context::resolve --context=prod pos1 pos2
  [ "$KSTACK_KUBE_CONTEXT" = "prod" ]
  [ "${#KUBE_CONTEXT_RESIDUAL_ARGS[@]}" = "2" ]
  [ "${KUBE_CONTEXT_RESIDUAL_ARGS[0]}" = "pos1" ]
  [ "${KUBE_CONTEXT_RESIDUAL_ARGS[1]}" = "pos2" ]
}

@test "resolve: --context value (space form) strips both tokens" {
  _stub_kubectl
  kube_context::resolve --context prod --refresh
  [ "$KSTACK_KUBE_CONTEXT" = "prod" ]
  [ "${#KUBE_CONTEXT_RESIDUAL_ARGS[@]}" = "1" ]
  [ "${KUBE_CONTEXT_RESIDUAL_ARGS[0]}" = "--refresh" ]
}

@test "resolve: --context in the middle of args" {
  _stub_kubectl
  kube_context::resolve --refresh --context=staging --ttl=5m
  [ "$KSTACK_KUBE_CONTEXT" = "staging" ]
  [ "${#KUBE_CONTEXT_RESIDUAL_ARGS[@]}" = "2" ]
  [ "${KUBE_CONTEXT_RESIDUAL_ARGS[0]}" = "--refresh" ]
  [ "${KUBE_CONTEXT_RESIDUAL_ARGS[1]}" = "--ttl=5m" ]
}

@test "resolve: no args leaves residual empty" {
  _stub_kubectl
  kube_context::resolve
  [ "$KSTACK_KUBE_CONTEXT" = "kc-default" ]
  [ "${#KUBE_CONTEXT_RESIDUAL_ARGS[@]}" = "0" ]
}

# ─── precedence ────────────────────────────────────────────────

@test "resolve: flag beats env var" {
  _stub_kubectl
  export KSTACK_KUBE_CONTEXT=env-ctx
  kube_context::resolve --context=flag-ctx
  [ "$KSTACK_KUBE_CONTEXT" = "flag-ctx" ]
}

@test "resolve: env var used when no flag" {
  _stub_kubectl
  export KSTACK_KUBE_CONTEXT=env-ctx
  kube_context::resolve --refresh
  [ "$KSTACK_KUBE_CONTEXT" = "env-ctx" ]
  [ "${KUBE_CONTEXT_RESIDUAL_ARGS[0]}" = "--refresh" ]
}

@test "resolve: kubectl current-context used when no flag and no env" {
  _stub_kubectl
  export MOCK_CONTEXT=kc-live
  kube_context::resolve
  [ "$KSTACK_KUBE_CONTEXT" = "kc-live" ]
}

@test "resolve: flag beats kubectl fallback" {
  _stub_kubectl
  export MOCK_CONTEXT=kc-live
  kube_context::resolve --context=override
  [ "$KSTACK_KUBE_CONTEXT" = "override" ]
}

# ─── errors ────────────────────────────────────────────────────

@test "resolve: --context with empty value is user error" {
  _stub_kubectl
  kube_context::resolve --context= || true
  [ "$KUBE_CONTEXT_ERROR_KIND" = "user" ]
  [[ "$KUBE_CONTEXT_ERROR" == *"empty"* ]] || [[ "$KUBE_CONTEXT_ERROR" == *"value"* ]]
}

@test "resolve: --context with no following arg is user error" {
  _stub_kubectl
  kube_context::resolve --context || true
  [ "$KUBE_CONTEXT_ERROR_KIND" = "user" ]
}

@test "resolve: kubectl exit 1 with no flag and no env is user error" {
  _stub_kubectl
  export MOCK_CONTEXT_EXIT=1
  kube_context::resolve || true
  [ "$KUBE_CONTEXT_ERROR_KIND" = "user" ]
  [[ "$KUBE_CONTEXT_ERROR" == *"kube context"* ]] || [[ "$KUBE_CONTEXT_ERROR" == *"context"* ]]
}

@test "resolve: kubectl empty output with no flag and no env is user error" {
  use_mocks
  write_stub kubectl '
case "$*" in
  "config current-context") printf "" ;;
  *) exit 2 ;;
esac
'
  kube_context::resolve || true
  [ "$KUBE_CONTEXT_ERROR_KIND" = "user" ]
}

@test "resolve: kubectl absent (or failing) with no flag and no env is user error" {
  # Stub kubectl to `exit 127` — simulates the binary being unavailable or
  # otherwise unable to answer. Stubbing is more robust than PATH-wiping:
  # on many systems (e.g. Homebrew) bash and kubectl share a bin dir, so
  # trimming PATH to bash's dir still leaks the host's real kubectl.
  use_mocks
  write_stub kubectl 'exit 127'
  kube_context::resolve || true
  [ "$KUBE_CONTEXT_ERROR_KIND" = "user" ]
}

@test "resolve: returns non-zero on failure" {
  _stub_kubectl
  export MOCK_CONTEXT_EXIT=1
  run kube_context::resolve
  [ "$status" -ne 0 ]
}
