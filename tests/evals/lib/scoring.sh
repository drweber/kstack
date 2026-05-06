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

# tests/evals/lib/scoring.sh — scoring primitives for the eval harness.
#
# All scoring functions print one line of JSON to stdout describing the
# outcome: {"pass": bool, "method": "<name>", "reason": "<text>"}.
# Non-fatal scoring failures still produce JSON with "pass": false; only
# programmer errors (missing args, bad jq) return nonzero.

eval_score_keywords() {
  # Cheap pre-flight: must_mention / must_not_mention substring checks.
  # Case-insensitive. Empty lists short-circuit to pass.
  local response="$1" expected_file="$2"

  local missing=()
  local forbidden=()
  local phrase
  local lower_response
  lower_response=$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')

  while IFS= read -r phrase; do
    [ -z "$phrase" ] && continue
    local lower_phrase
    lower_phrase=$(printf '%s' "$phrase" | tr '[:upper:]' '[:lower:]')
    case "$lower_response" in
      *"$lower_phrase"*) ;;
      *) missing+=("$phrase") ;;
    esac
  done < <(yq -r '.rubric.must_mention[]?' "$expected_file")

  while IFS= read -r phrase; do
    [ -z "$phrase" ] && continue
    local lower_phrase
    lower_phrase=$(printf '%s' "$phrase" | tr '[:upper:]' '[:lower:]')
    case "$lower_response" in
      *"$lower_phrase"*) forbidden+=("$phrase") ;;
    esac
  done < <(yq -r '.rubric.must_not_mention[]?' "$expected_file")

  if [ "${#missing[@]}" -eq 0 ] && [ "${#forbidden[@]}" -eq 0 ]; then
    printf '{"pass":true,"method":"keywords","reason":"all keyword checks passed"}\n'
    return 0
  fi

  local reason="keyword checks failed"
  if [ "${#missing[@]}" -gt 0 ]; then
    reason="$reason; missing: ${missing[*]}"
  fi
  if [ "${#forbidden[@]}" -gt 0 ]; then
    reason="$reason; forbidden present: ${forbidden[*]}"
  fi
  jq -cn --arg r "$reason" '{pass:false,method:"keywords",reason:$r}'
}

eval_score_structured() {
  # Compare required_findings / forbidden_findings against a JSON blob
  # Claude emitted as its final answer. The "blob" is a plain JSON object
  # that must contain a top-level "findings" array.
  #
  # A required_finding matches a finding iff every key in the rubric entry
  # is present in the finding with an equal value, OR (for array-valued
  # rubric fields) the finding's value is one of the array's elements.
  # This lets rubrics use e.g. severity: [warning, critical] to tolerate
  # either level.
  local response_json="$1" expected_file="$2"
  local findings_json expected_json

  findings_json=$(printf '%s' "$response_json" | jq -c '.findings // []' 2>/dev/null) \
    || findings_json='[]'
  [ -n "$findings_json" ] || findings_json='[]'

  expected_json=$(yq -o=json '.structured // {}' "$expected_file")

  jq -cn \
    --argjson findings "$findings_json" \
    --argjson expected "$expected_json" '
    def value_matches($actual; $rubric):
      if ($rubric | type) == "array" then ($rubric | index($actual)) != null
      else $actual == $rubric end;
    def finding_matches($f; $rubric):
      ($rubric | to_entries | all(value_matches($f[.key]; .value)));

    ($expected.required_findings // []) as $required
    | ($expected.forbidden_findings // []) as $forbidden
    | ($required | map(. as $r | ($findings | any(finding_matches(.; $r))) | not)) as $missing_mask
    | ($required | [range(0; length)] | map(select($missing_mask[.])) | map($required[.])) as $missing
    | ($forbidden | map(. as $r | $findings | any(finding_matches(.; $r)))) as $present_mask
    | ($forbidden | [range(0; length)] | map(select($present_mask[.])) | map($forbidden[.])) as $present
    | if ($missing | length) == 0 and ($present | length) == 0 then
        {pass:true, method:"structured", reason:"all structured assertions satisfied"}
      else
        {pass:false, method:"structured",
         reason:"structured mismatch",
         missing_required: $missing,
         present_forbidden: $present}
      end
  '
}

eval_score_judge() {
  # Invoke the LLM-judge and translate its verdict into a scoring result.
  # If stderr_file is given, the judge's stderr is captured there (always)
  # so failed invocations can be inspected without re-running.
  local response="$1" expected_file="$2" model="$3" stderr_file="${4:-}"
  local rubric verdict

  rubric=$(yq -o=yaml '.rubric' "$expected_file")

  local _stderr_target="${stderr_file:-$(mktemp)}"
  local rc=0
  verdict=$(eval_claude_judge "$model" "$rubric" "$response" 2>"$_stderr_target") || rc=$?

  if [ "$rc" -ne 0 ]; then
    local err_msg
    err_msg=$(tr '\n' ' ' < "$_stderr_target" | sed 's/  */ /g; s/"/\\"/g' | head -c 500)
    [ -z "$stderr_file" ] && rm -f "$_stderr_target"
    jq -cn --arg err "$err_msg" \
      '{pass:false, method:"judge", reason:("judge invocation failed: " + $err)}'
    return 0
  fi
  [ -z "$stderr_file" ] && rm -f "$_stderr_target"

  # Normalize verdict into the scoring result shape.
  printf '%s' "$verdict" | jq -c '{
    pass:   (.pass // false),
    method: "judge",
    reason: (.reason // ""),
    violations: (.violations // [])
  }'
}

eval_extract_final_json() {
  # Given the final assistant text, extract the first top-level JSON object
  # it contains. Skills invoked with --json should emit a JSON object as
  # their entire final message; tolerate a surrounding ```json fence or
  # leading prose.
  local text="$1"
  local stripped
  stripped=$(printf '%s' "$text" \
    | sed -E 's/^[[:space:]]*```(json)?[[:space:]]*//; s/```[[:space:]]*$//')

  # If the stripped content parses as JSON, return it. Otherwise try to
  # find the first { ... } block via jq's streaming parser fallback.
  if printf '%s' "$stripped" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$stripped" | jq -c .
    return 0
  fi

  # Fallback: look for a JSON object inside the text by bracket-matching.
  local extracted
  extracted=$(printf '%s' "$text" | awk '
    /\{/ { capturing = 1 }
    capturing {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        buf = buf c
        if (c == "{") depth++
        else if (c == "}") {
          depth--
          if (depth == 0) { print buf; exit }
        }
      }
      buf = buf "\n"
    }
  ')
  if [ -z "$extracted" ]; then
    echo '{}'
    return 0
  fi
  printf '%s\n' "$extracted" | jq -c . 2>/dev/null || echo '{}'
}
