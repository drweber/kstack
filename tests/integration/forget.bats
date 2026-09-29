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
  cp "$SRC_ROOT/lib/hash.sh"     "$KSTACK_ROOT/lib/"
  export KSTACK_KUBE_CONTEXT="test-ctx"
  export KSTACK_SKILL_NAME="forget"
  unset KSTACK_NOTICE
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

main() {
  "$SRC_ROOT/skills/forget/scripts/main" "$@"
}

ctx_sha() {
  printf '%s' "$1" | sha256sum 2>/dev/null | awk '{print substr($1,1,12)}' \
    || printf '%s' "$1" | shasum -a 256 | awk '{print substr($1,1,12)}'
}

seed_cache() {
  local ctx="$1"
  local sha; sha="$(ctx_sha "$ctx")"
  mkdir -p "$KSTACK_ROOT/cache/kube/$sha"
  touch    "$KSTACK_ROOT/cache/kube/$sha/cluster.json"
}

seed_state() {
  local ctx="$1"
  local sha; sha="$(ctx_sha "$ctx")"
  mkdir -p "$KSTACK_ROOT/state/$sha"
  touch    "$KSTACK_ROOT/state/$sha/prefs.json"
}

cache_exists() {
  local ctx="$1"
  local sha; sha="$(ctx_sha "$ctx")"
  [ -d "$KSTACK_ROOT/cache/kube/$sha" ]
}

state_exists() {
  local ctx="$1"
  local sha; sha="$(ctx_sha "$ctx")"
  [ -d "$KSTACK_ROOT/state/$sha" ]
}

# ---------------------------------------------------------------------------
# Basics
# ---------------------------------------------------------------------------

@test "main script exists and is executable" {
  [ -x "$SRC_ROOT/skills/forget/scripts/main" ]
}

@test "rejects unknown flags" {
  run main --bogus
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"Unknown flag"* ]]
}

# ---------------------------------------------------------------------------
# Single-context (default)
# ---------------------------------------------------------------------------

@test "nothing to forget when no state exists" {
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"Nothing to forget"* ]]
  [[ "$output" == *"test-ctx"* ]]
}

@test "clears cache for current context" {
  seed_cache "test-ctx"
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"Forgot"* ]]
  ! cache_exists "test-ctx"
}

@test "clears state for current context" {
  seed_state "test-ctx"
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"Forgot"* ]]
  ! state_exists "test-ctx"
}

@test "clears both cache and state for current context" {
  seed_cache "test-ctx"
  seed_state "test-ctx"
  run main
  [ "$status" -eq 0 ]
  run cache_exists "test-ctx"
  [ "$status" -ne 0 ]
  run state_exists "test-ctx"
  [ "$status" -ne 0 ]
}

@test "does not touch other contexts" {
  seed_cache "test-ctx"
  seed_cache "other-ctx"
  seed_state "other-ctx"
  run main
  [ "$status" -eq 0 ]
  run cache_exists "test-ctx"
  [ "$status" -ne 0 ]
  cache_exists "other-ctx"
  state_exists "other-ctx"
}

# ---------------------------------------------------------------------------
# --all flag
# ---------------------------------------------------------------------------

@test "--all: nothing to forget when no state exists" {
  run main --all
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *"Nothing to forget"* ]]
}

@test "--all: clears cache for every context" {
  seed_cache "ctx-a"
  seed_cache "ctx-b"
  run main --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Forgot local state for all contexts"* ]]
  run cache_exists "ctx-a"
  [ "$status" -ne 0 ]
  run cache_exists "ctx-b"
  [ "$status" -ne 0 ]
}

@test "--all: clears state for every context" {
  seed_state "ctx-a"
  seed_state "ctx-b"
  run main --all
  [ "$status" -eq 0 ]
  run state_exists "ctx-a"
  [ "$status" -ne 0 ]
  run state_exists "ctx-b"
  [ "$status" -ne 0 ]
}

@test "--all: clears mixed cache and state across contexts" {
  seed_cache "ctx-a"
  seed_state "ctx-b"
  run main --all
  [ "$status" -eq 0 ]
  run cache_exists "ctx-a"
  [ "$status" -ne 0 ]
  run state_exists "ctx-b"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Notice forwarding
# ---------------------------------------------------------------------------

@test "prepends KSTACK_NOTICE to output when set" {
  export KSTACK_NOTICE="⚠ kstack v2.0 is available"
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *"kstack v2.0 is available"* ]]
}
