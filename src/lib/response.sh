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

# response.sh — helpers for emitting the kstack response envelope (protocol v1).
#
# Sourced by bin/entrypoint and each skill's scripts/main. Do not execute.
#
# Every kstack script exits 0 on a clean run and writes exactly one JSON
# object (the envelope) to stdout. The envelope schema lives at
# {{ROOT_DIR}}/schemas/response.schema.json. The SKILL.md entrypoint partial
# documents how the agent dispatches on the envelope.
#
# Helpers honor KSTACK_NOTICE: when set, a "notice" field is added to the
# envelope so the agent can surface an update banner above any payload.

# response::_escape
#   Read stdin, emit the body of a JSON string literal (no surrounding quotes).
#   Handles backslashes, double quotes, newlines, tabs, and carriage returns.
#   Non-ASCII bytes pass through (valid JSON allows UTF-8 in strings).
response::_escape() {
  awk '
    BEGIN { ORS = ""; first = 1 }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\t/, "\\t")
      gsub(/\r/, "\\r")
      if (!first) printf "\\n"
      first = 0
      printf "%s", $0
    }
  '
}

# response::_notice_suffix
#   Emit ',"notice":"<escaped>"' when KSTACK_NOTICE is set, else nothing.
response::_notice_suffix() {
  [ -n "${KSTACK_NOTICE:-}" ] || return 0
  local esc
  esc="$(printf '%s' "$KSTACK_NOTICE" | response::_escape)"
  printf ',"notice":"%s"' "$esc"
}

# response::_kube_context_suffix
#   Emit ',"kube_context":"<escaped>"' when KSTACK_KUBE_CONTEXT is set, else
#   nothing.
response::_kube_context_suffix() {
  [ -n "${KSTACK_KUBE_CONTEXT:-}" ] || return 0
  local esc
  esc="$(printf '%s' "$KSTACK_KUBE_CONTEXT" | response::_escape)"
  printf ',"kube_context":"%s"' "$esc"
}

# response::_agent_context_suffix <agent_context>
#   Emit ',"agent_context":"<escaped>"' when the arg is non-empty, else nothing.
response::_agent_context_suffix() {
  [ -n "${1:-}" ] || return 0
  local esc
  esc="$(printf '%s' "$1" | response::_escape)"
  printf ',"agent_context":"%s"' "$esc"
}

# response::ok_verbatim [<content> [<agent_context>]]
#   Emit an ok/verbatim envelope. If no content arg, reads content from stdin.
#   The optional <agent_context> is a side-channel string the agent reads but
#   never shows to the user — use for follow-up metadata (cache paths etc.)
#   that would otherwise clutter the verbatim output.
response::ok_verbatim() {
  local content agent_context=""
  if [ $# -gt 0 ]; then
    content="$1"
    [ $# -ge 2 ] && agent_context="$2"
  else
    content="$(cat)"
  fi
  local esc notice_s agent_s kube_s
  esc="$(printf '%s' "$content" | response::_escape)"
  notice_s="$(response::_notice_suffix)"
  agent_s="$(response::_agent_context_suffix "$agent_context")"
  kube_s="$(response::_kube_context_suffix)"
  printf '{"kstack":"1","status":"ok","render":"verbatim","content":"%s"%s%s%s}\n' \
    "$esc" "$agent_s" "$kube_s" "$notice_s"
}

# response::ok_agent [<content> [<agent_context>]]
#   Emit an ok/agent envelope. Empty content signals "no output; continue
#   with the SKILL.md body." Non-empty content is tool output the agent
#   reads as context before continuing. See ok_verbatim for agent_context.
response::ok_agent() {
  local content agent_context=""
  if [ $# -gt 0 ]; then
    content="$1"
    [ $# -ge 2 ] && agent_context="$2"
  else
    content="$(cat)"
  fi
  local esc notice_s agent_s kube_s
  esc="$(printf '%s' "$content" | response::_escape)"
  notice_s="$(response::_notice_suffix)"
  agent_s="$(response::_agent_context_suffix "$agent_context")"
  kube_s="$(response::_kube_context_suffix)"
  printf '{"kstack":"1","status":"ok","render":"agent","content":"%s"%s%s%s}\n' \
    "$esc" "$agent_s" "$kube_s" "$notice_s"
}

# response::user_error <message>
#   Emit a user-fixable error (bad flag, missing arg, invalid context).
response::user_error() {
  local esc notice_s kube_s
  esc="$(printf '%s' "$1" | response::_escape)"
  notice_s="$(response::_notice_suffix)"
  kube_s="$(response::_kube_context_suffix)"
  printf '{"kstack":"1","status":"error","kind":"user","message":"%s"%s%s}\n' \
    "$esc" "$kube_s" "$notice_s"
}

# response::infra_error <message>
#   Emit an environment/install failure (missing binary, broken cache, etc.).
response::infra_error() {
  local esc notice_s kube_s
  esc="$(printf '%s' "$1" | response::_escape)"
  notice_s="$(response::_notice_suffix)"
  kube_s="$(response::_kube_context_suffix)"
  printf '{"kstack":"1","status":"error","kind":"infra","message":"%s"%s%s}\n' \
    "$esc" "$kube_s" "$notice_s"
}
