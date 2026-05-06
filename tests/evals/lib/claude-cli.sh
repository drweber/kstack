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

# tests/evals/lib/claude-cli.sh — thin wrapper around `claude -p`.
#
# Concentrates all knowledge of the claude CLI flag surface in one place so
# the runner / scoring code stays stable if flags change.
#
# Usage:
#   eval_claude_run <transcript_file> <allowed_tools> <model> <prompt> [stderr_file]
#       Invokes `claude -p` with --output-format stream-json and writes the
#       raw JSONL stream to <transcript_file>. If stderr_file is given,
#       claude's stderr is captured to it (always — useful for debugging
#       failed runs). Returns the claude exit code.
#
#   eval_claude_final_text <transcript_file>
#       Prints the final assistant text from a stream-json transcript.
#
#   eval_claude_usage_json <transcript_file>
#       Prints a single-line JSON object with
#       {input_tokens, output_tokens, total_cost_usd} aggregated from the
#       transcript. Missing fields default to 0.
#
#   eval_claude_judge <model> <rubric_text> <response_text>
#       Runs the LLM-as-judge prompt and prints the judge's JSON verdict
#       line (pass/reason/violations) to stdout. Returns nonzero if the
#       judge call itself fails or emits non-JSON.

_EVAL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

eval_claude_run() {
  local transcript="$1" allowed_tools="$2" model="$3" prompt="$4" stderr_file="${5:-}"
  local -a args=(-p --output-format stream-json --verbose)
  if [ -n "$model" ]; then
    args+=(--model "$model")
  fi
  if [ -n "${KSTACK_EVAL_EFFORT:-}" ]; then
    args+=(--effort "$KSTACK_EVAL_EFFORT")
  fi
  if [ -n "$allowed_tools" ]; then
    args+=(--allowed-tools "$allowed_tools")
  fi
  # --verbose is required for stream-json; captures assistant + tool events.
  if [ -n "$stderr_file" ]; then
    printf '%s' "$prompt" | claude "${args[@]}" > "$transcript" 2> "$stderr_file"
  else
    printf '%s' "$prompt" | claude "${args[@]}" > "$transcript"
  fi
}

eval_claude_final_text() {
  local transcript="$1"
  # Concatenate text blocks from ALL assistant messages in the turn so that
  # rubric keywords can match anything Claude said, not just the final reply.
  # Multi-turn runs interleave tool calls with text; an early message may
  # contain the key output (e.g. a "Command:" line) while the final message
  # is only an error or summary.
  local result
  result=$(jq -rs '
    map(select(type == "object"))
    | map(select(.type == "assistant"))
    | map(.message.content // [])
    | map(map(select(.type == "text") | .text))
    | map(join(""))
    | join("\n\n")
  ' "$transcript" 2>/dev/null) || return 1
  printf '%s\n' "$result"
}

eval_claude_usage_json() {
  local transcript="$1"
  jq -rs '
    map(select(type == "object"))
    | (map(select(.type == "result")) | last // empty) as $r
    | {
        input_tokens:    ($r.usage.input_tokens // 0),
        output_tokens:   ($r.usage.output_tokens // 0),
        total_cost_usd:  ($r.total_cost_usd // 0)
      }
    | tostring
  ' "$transcript" 2>/dev/null || echo '{"input_tokens":0,"output_tokens":0,"total_cost_usd":0}'
}

eval_claude_judge() {
  local model="$1" rubric="$2" response="$3"
  local template="$_EVAL_LIB_DIR/judge-prompt.txt"
  if [ ! -f "$template" ]; then
    echo "missing judge template: $template" >&2
    return 2
  fi

  # Render the template using bash's built-in pattern substitution so
  # multi-line values, backslashes, and `&` pass through untouched.
  # (awk's `-v` rejects newlines; sed mangles `&` in the replacement.)
  local template_body rendered
  template_body=$(cat "$template")
  rendered="${template_body//\{\{RUBRIC\}\}/$rubric}"
  rendered="${rendered//\{\{RESPONSE\}\}/$response}"

  local -a args=(-p --output-format json)
  if [ -n "$model" ]; then
    args+=(--model "$model")
  fi
  args+=(--allowed-tools "")

  local raw
  if ! raw=$(printf '%s' "$rendered" | claude "${args[@]}" 2>/dev/null); then
    echo "judge claude invocation failed" >&2
    return 1
  fi

  # claude -p --output-format json returns a wrapper with the model's text
  # under .result. Parse that out, then validate it is itself JSON with the
  # expected shape.
  local verdict_text
  verdict_text=$(printf '%s' "$raw" | jq -r '.result // empty' 2>/dev/null) || return 1
  if [ -z "$verdict_text" ]; then
    echo "judge returned empty result" >&2
    return 1
  fi

  # Strip any ```json ... ``` fence the model might emit.
  verdict_text=$(printf '%s' "$verdict_text" \
    | sed -E 's/^[[:space:]]*```(json)?[[:space:]]*//; s/```[[:space:]]*$//')

  if ! printf '%s' "$verdict_text" \
      | jq -e 'type == "object" and has("pass")' >/dev/null 2>&1; then
    echo "judge response is not valid JSON with a pass field:" >&2
    printf '%s\n' "$verdict_text" >&2
    return 1
  fi

  printf '%s\n' "$verdict_text"
}
