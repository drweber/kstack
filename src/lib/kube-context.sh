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

# shellcheck shell=bash
# shellcheck disable=SC2034  # KSTACK_KUBE_CONTEXT and KUBE_CONTEXT_* vars are read by callers.

# kube-context.sh — single resolver for the kube context.
#
# Sourced by bin/entrypoint (and, indirectly, by any skill's scripts/main via
# the env var exported from entrypoint). Applies precedence:
#
#   1. --context=<value> / --context <value> passed in args
#   2. $KSTACK_KUBE_CONTEXT environment variable
#   3. `kubectl config current-context`
#
# Entrypoint strips --context from forwarded user args before exec'ing
# scripts/main, so scripts/main consumes the resolved value from the env var
# only — no per-skill duplicate parser.

# kube_context::resolve [args…]
#   Walks args looking for --context=VAL or --context VAL, resolves via the
#   precedence above, and populates caller scope:
#     KSTACK_KUBE_CONTEXT       - resolved context (exported for children)
#     KUBE_CONTEXT_RESIDUAL_ARGS - array of args with --context removed
#   On failure (empty/missing value, no resolvable fallback):
#     KUBE_CONTEXT_ERROR        - human-readable message
#     KUBE_CONTEXT_ERROR_KIND   - "user" (caller emits via response::user_error)
#   Returns 0 on success, 1 on failure. Never calls `kubectl` when the flag
#   or env var already supplied a value (cheap and avoids surprises in CI).
kube_context::resolve() {
  KUBE_CONTEXT_RESIDUAL_ARGS=()
  KUBE_CONTEXT_ERROR=""
  KUBE_CONTEXT_ERROR_KIND=""

  local flag_val="" flag_set=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --context=*)
        flag_val="${1#--context=}"
        flag_set=1
        shift
        ;;
      --context)
        if [ $# -lt 2 ]; then
          KUBE_CONTEXT_ERROR="Flag --context requires a value."
          KUBE_CONTEXT_ERROR_KIND=user
          return 1
        fi
        flag_val="$2"
        flag_set=1
        shift 2
        ;;
      *)
        KUBE_CONTEXT_RESIDUAL_ARGS+=("$1")
        shift
        ;;
    esac
  done

  if [ "$flag_set" = 1 ]; then
    if [ -z "$flag_val" ]; then
      KUBE_CONTEXT_ERROR="Flag --context has an empty value."
      KUBE_CONTEXT_ERROR_KIND=user
      return 1
    fi
    KSTACK_KUBE_CONTEXT="$flag_val"
    return 0
  fi

  if [ -n "${KSTACK_KUBE_CONTEXT:-}" ]; then
    return 0
  fi

  local kc
  if ! kc="$(kubectl config current-context 2>/dev/null)" || [ -z "$kc" ]; then
    KUBE_CONTEXT_ERROR="Unable to determine kube context. Set one with kubectl or pass --context=<name>."
    KUBE_CONTEXT_ERROR_KIND=user
    return 1
  fi
  KSTACK_KUBE_CONTEXT="$kc"
  return 0
}
