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

# Unit tests for src/lib/response.sh. Tests invoke response::* directly and
# validate that emitted envelopes round-trip through jq (proving they are
# well-formed JSON) and carry the expected fields.

setup() {
  load '../test_helper.bash'
  common_setup
  # shellcheck source=../../lib/response.sh
  . "$SRC_ROOT/lib/response.sh"
  unset KSTACK_NOTICE
  unset KSTACK_KUBE_CONTEXT
}

# jq is a hard dep for kstack skills (cluster-status uses it heavily).
# Tests that need it skip cleanly when it's missing so the suite still runs
# in minimal environments.
require_jq() { command -v jq >/dev/null 2>&1 || skip "jq not available"; }

@test "_escape passes plain ASCII through unchanged" {
  run bash -c '. "$0" && printf "hello world" | response::_escape' "$SRC_ROOT/lib/response.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
}

@test "_escape escapes double quotes and backslashes" {
  run bash -c '. "$0" && printf "say \"hi\" \\\\ done" | response::_escape' "$SRC_ROOT/lib/response.sh"
  [ "$status" -eq 0 ]
  [ "$output" = 'say \"hi\" \\ done' ]
}

@test "_escape turns newlines into \\n" {
  out="$(printf 'a\nb\nc' | response::_escape)"
  [ "$out" = 'a\nb\nc' ]
}

@test "ok_verbatim emits a well-formed envelope with expected fields" {
  require_jq
  out="$(response::ok_verbatim "hello")"
  [ "$(printf '%s' "$out" | jq -r '.kstack')" = "1" ]
  [ "$(printf '%s' "$out" | jq -r '.status')" = "ok" ]
  [ "$(printf '%s' "$out" | jq -r '.render')" = "verbatim" ]
  [ "$(printf '%s' "$out" | jq -r '.content')" = "hello" ]
  # No notice field when KSTACK_NOTICE is unset.
  [ "$(printf '%s' "$out" | jq -r 'has("notice")')" = "false" ]
}

@test "ok_verbatim preserves multi-line content through the round-trip" {
  require_jq
  in=$'line 1\nline 2\t"quoted"\\slash'
  out="$(response::ok_verbatim "$in")"
  # tr -d '\r': normalize Git Bash / jq text-mode CRLFs (see notice-field
  # test below for the full explanation).
  decoded="$(printf '%s' "$out" | jq -r '.content' | tr -d '\r')"
  [ "$decoded" = "$in" ]
}

@test "ok_agent emits render=agent" {
  require_jq
  out="$(response::ok_agent "context here")"
  [ "$(printf '%s' "$out" | jq -r '.render')" = "agent" ]
  [ "$(printf '%s' "$out" | jq -r '.content')" = "context here" ]
}

@test "ok_verbatim with 2nd arg attaches agent_context" {
  require_jq
  out="$(response::ok_verbatim "visible" '{"cache_dir":"/tmp/x","context":"dev"}')"
  [ "$(printf '%s' "$out" | jq -r '.content')" = "visible" ]
  [ "$(printf '%s' "$out" | jq -r '.agent_context')" = '{"cache_dir":"/tmp/x","context":"dev"}' ]
}

@test "ok_verbatim without 2nd arg omits agent_context" {
  require_jq
  out="$(response::ok_verbatim "visible")"
  [ "$(printf '%s' "$out" | jq -r 'has("agent_context")')" = "false" ]
}

@test "ok_verbatim with empty 2nd arg omits agent_context" {
  require_jq
  out="$(response::ok_verbatim "visible" "")"
  [ "$(printf '%s' "$out" | jq -r 'has("agent_context")')" = "false" ]
}

@test "ok_agent with 2nd arg attaches agent_context" {
  require_jq
  out="$(response::ok_agent "context" "hidden-from-user")"
  [ "$(printf '%s' "$out" | jq -r '.agent_context')" = "hidden-from-user" ]
}

@test "user_error emits status=error kind=user" {
  require_jq
  out="$(response::user_error "bad flag")"
  [ "$(printf '%s' "$out" | jq -r '.status')" = "error" ]
  [ "$(printf '%s' "$out" | jq -r '.kind')" = "user" ]
  [ "$(printf '%s' "$out" | jq -r '.message')" = "bad flag" ]
}

@test "infra_error emits status=error kind=infra" {
  require_jq
  out="$(response::infra_error "kubectl exploded")"
  [ "$(printf '%s' "$out" | jq -r '.kind')" = "infra" ]
  [ "$(printf '%s' "$out" | jq -r '.message')" = "kubectl exploded" ]
}

@test "notice field is attached when KSTACK_NOTICE is set" {
  require_jq
  export KSTACK_NOTICE="kstack v2.0.0 is available"
  out="$(response::ok_verbatim "payload")"
  [ "$(printf '%s' "$out" | jq -r '.notice')" = "kstack v2.0.0 is available" ]
}

@test "notice field is escaped like content" {
  require_jq
  export KSTACK_NOTICE=$'line 1\n"line 2"'
  out="$(response::user_error "nope")"
  # tr -d '\r': jq on Git Bash (Windows) writes stdout in text mode, so
  # internal LFs in the decoded value get translated to CRLF. Bash's $()
  # strips the trailing CRLF pair cleanly but leaves internal CRs, which
  # would otherwise break multi-line round-trip comparisons. The envelope
  # itself is byte-perfect — this only normalizes the jq output layer.
  [ "$(printf '%s' "$out" | jq -r '.notice' | tr -d '\r')" = $'line 1\n"line 2"' ]
}

@test "ok_verbatim reads from stdin when no arg is given" {
  require_jq
  out="$(printf 'from stdin' | response::ok_verbatim)"
  [ "$(printf '%s' "$out" | jq -r '.content')" = "from stdin" ]
}

# ─── kube_context auto-injection ───────────────────────────────

@test "kube_context field is attached when KSTACK_KUBE_CONTEXT is set" {
  require_jq
  export KSTACK_KUBE_CONTEXT="prod-cluster"
  out="$(response::ok_verbatim "payload")"
  [ "$(printf '%s' "$out" | jq -r '.kube_context')" = "prod-cluster" ]
}

@test "kube_context absent when KSTACK_KUBE_CONTEXT is unset" {
  require_jq
  out="$(response::ok_verbatim "payload")"
  [ "$(printf '%s' "$out" | jq -r 'has("kube_context")')" = "false" ]
}

@test "kube_context absent when KSTACK_KUBE_CONTEXT is empty" {
  require_jq
  export KSTACK_KUBE_CONTEXT=""
  out="$(response::ok_verbatim "payload")"
  [ "$(printf '%s' "$out" | jq -r 'has("kube_context")')" = "false" ]
}

@test "kube_context attached to ok_agent envelopes" {
  require_jq
  export KSTACK_KUBE_CONTEXT="staging"
  out="$(response::ok_agent "")"
  [ "$(printf '%s' "$out" | jq -r '.kube_context')" = "staging" ]
}

@test "kube_context attached to user_error envelopes" {
  require_jq
  export KSTACK_KUBE_CONTEXT="dev"
  out="$(response::user_error "bad")"
  [ "$(printf '%s' "$out" | jq -r '.kube_context')" = "dev"  ]
}

@test "kube_context attached to infra_error envelopes" {
  require_jq
  export KSTACK_KUBE_CONTEXT="dev"
  out="$(response::infra_error "kubectl down")"
  [ "$(printf '%s' "$out" | jq -r '.kube_context')" = "dev"  ]
}

@test "kube_context JSON-escaped for special chars" {
  require_jq
  export KSTACK_KUBE_CONTEXT='ctx"with\quotes'
  out="$(response::ok_verbatim "x")"
  [ "$(printf '%s' "$out" | jq -r '.kube_context')" = 'ctx"with\quotes' ]
}

@test "kube_context coexists with notice and agent_context" {
  require_jq
  export KSTACK_KUBE_CONTEXT="prod"
  export KSTACK_NOTICE="update available"
  out="$(response::ok_verbatim "visible" '{"cache_dir":"/tmp/x"}')"
  [ "$(printf '%s' "$out" | jq -r '.kube_context')"  = "prod" ]
  [ "$(printf '%s' "$out" | jq -r '.notice')"        = "update available" ]
  [ "$(printf '%s' "$out" | jq -r '.agent_context')" = '{"cache_dir":"/tmp/x"}' ]
}
