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
# shellcheck disable=SC2034  # STATE_* vars are read by callers that source this file.

# state.sh — durable per-install key/value store for learned preferences.
#
# shellcheck source=hash.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hash.sh"
#
# Two scopes:
#   global   — {{ROOT_DIR}}/state/<key>            (workstation-wide)
#   context  — {{ROOT_DIR}}/state/contexts/<sha>/<key>  (per kube context)
#
# Values are short strings (a single line). Keys may contain slashes and are
# used verbatim as relative paths, so a skill namespacing convention like
# "audit-outdated/deprecated-apis-backend" just maps to a subdirectory.
#
# Usage:
#   . "$KSTACK_ROOT/lib/state.sh"
#   state::init                                       # global only
#   state::init_context                               # global + per-context
#   value="$(state::get global audit-outdated/x)"     # empty string if unset
#   state::set global audit-outdated/x pluto
#   state::unset global audit-outdated/x
#
# Requires $KSTACK_ROOT. state::init_context additionally requires
# $KSTACK_KUBE_CONTEXT. Both set STATE_ERROR + STATE_ERROR_KIND (user|infra)
# on failure; callers dispatch with:
#   response::"${STATE_ERROR_KIND}_error" "$STATE_ERROR"

STATE_DIR=""
STATE_CONTEXT_DIR=""
STATE_ERROR=""
STATE_ERROR_KIND=""

# _state::context_sha <value>
#   Delegates to the shared hash::short_sha utility. Uses the same hash as
#   kube-cache.sh so the same context maps to the same directory stub.
_state::context_sha() {
  hash::short_sha "$1"
}

# _state::resolve <scope> <key>
#   Echo the absolute path for (scope, key) on stdout. Scope must have been
#   initialized (state::init for global, state::init_context for context).
#   Returns non-zero if the scope is unknown or its dir is empty.
_state::resolve() {
  local scope="$1" key="$2" base=""
  case "$scope" in
    global)  base="$STATE_DIR" ;;
    context) base="$STATE_CONTEXT_DIR" ;;
    *)       return 1 ;;
  esac
  [ -n "$base" ] || return 1
  printf '%s/%s\n' "$base" "$key"
}

# state::init
#   Set $STATE_DIR to $KSTACK_ROOT/state and ensure it exists.
state::init() {
  STATE_ERROR=""
  STATE_ERROR_KIND=""

  if [ -z "${KSTACK_ROOT:-}" ]; then
    STATE_ERROR="KSTACK_ROOT not set; source state.sh from a skill that runs via bin/entrypoint."
    STATE_ERROR_KIND=infra
    return 1
  fi

  STATE_DIR="$KSTACK_ROOT/state"
  if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
    STATE_ERROR="Unable to create state dir: $STATE_DIR"
    STATE_ERROR_KIND=infra
    return 1
  fi
}

# state::init_context
#   state::init plus $STATE_CONTEXT_DIR=$KSTACK_ROOT/state/contexts/<sha>.
state::init_context() {
  state::init || return 1

  if [ -z "${KSTACK_KUBE_CONTEXT:-}" ]; then
    STATE_ERROR="KSTACK_KUBE_CONTEXT not set; source state.sh from a skill that runs via bin/entrypoint."
    STATE_ERROR_KIND=infra
    return 1
  fi

  local sha
  sha="$(_state::context_sha "$KSTACK_KUBE_CONTEXT")"
  STATE_CONTEXT_DIR="$STATE_DIR/contexts/$sha"
  if ! mkdir -p "$STATE_CONTEXT_DIR" 2>/dev/null; then
    STATE_ERROR="Unable to create state dir: $STATE_CONTEXT_DIR"
    STATE_ERROR_KIND=infra
    return 1
  fi
}

# state::get <scope> <key>
#   Print the stored value (without a trailing newline) on stdout.
#   Prints nothing and returns 0 if the key is unset — callers distinguish
#   "unset" from "empty string" via state::has when it matters.
state::get() {
  local path
  path="$(_state::resolve "$1" "$2")" || return 1
  [ -r "$path" ] || return 0
  # Trim trailing newline from the stored line. Values are single-line by
  # contract; if the file has multiple lines we only read the first.
  IFS= read -r line < "$path" || line=""
  printf '%s' "$line"
}

# state::has <scope> <key>
#   True iff the key exists (regardless of value).
state::has() {
  local path
  path="$(_state::resolve "$1" "$2")" || return 1
  [ -r "$path" ]
}

# state::set <scope> <key> <value>
#   Atomic write. Creates parent dirs under the scope root as needed.
state::set() {
  local scope="$1" key="$2" value="$3" path parent
  path="$(_state::resolve "$scope" "$key")" || return 1
  parent="$(dirname "$path")"
  mkdir -p "$parent" 2>/dev/null || return 1
  printf '%s\n' "$value" > "$path.tmp" 2>/dev/null || { rm -f "$path.tmp"; return 1; }
  mv "$path.tmp" "$path" 2>/dev/null || { rm -f "$path.tmp"; return 1; }
}

# state::unset <scope> <key>
#   Remove the key if present. Returns 0 whether or not it existed.
state::unset() {
  local path
  path="$(_state::resolve "$1" "$2")" || return 1
  rm -f "$path" 2>/dev/null || return 1
}
