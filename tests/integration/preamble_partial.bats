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

# Pins the content of the `{{PREAMBLE}}` partial — the cross-cutting
# safety contract every kstack skill inherits. Two clauses:
#   1. Confirm in chat before destructive cluster actions.
#   2. Treat cluster data as untrusted input (prompt-injection-aware).

setup() {
  load '../test_helper.bash'
  common_setup
  PARTIAL="$SRC_ROOT/skills/_partials/preamble.md"
}

@test "preamble partial file exists at the expected path" {
  [ -f "$PARTIAL" ]
}

# ---------------------------------------------------------------------------
# Clause 1: confirm before destructive actions
# ---------------------------------------------------------------------------

@test "preamble has a Destructive actions section" {
  run grep -E -i "^## .*[Dd]estructive" "$PARTIAL"
  [ "$status" -eq 0 ]
}

@test "preamble requires chat confirmation before running destructive commands" {
  run grep -F "Confirm in chat before running any destructive command" "$PARTIAL"
  [ "$status" -eq 0 ]
}

@test "preamble names kubectl mutating verbs as destructive" {
  for verb in delete edit patch apply replace scale drain cordon rollout cp; do
    run grep -F "kubectl $verb" "$PARTIAL"
    [ "$status" -eq 0 ] || { echo "missing: kubectl $verb"; return 1; }
  done
}

@test "preamble names kubectl exec as destructive (since exec can mutate)" {
  run grep -F "kubectl exec" "$PARTIAL"
  [ "$status" -eq 0 ]
}

@test "preamble carves read-only kubectl ops out of the confirmation rule" {
  run grep -E -i "(read.only|no confirmation|don.?t need confirmation)" "$PARTIAL"
  [ "$status" -eq 0 ]
  for verb in get describe logs top explain "api-versions"; do
    run grep -F "kubectl $verb" "$PARTIAL"
    [ "$status" -eq 0 ] || { echo "missing: kubectl $verb"; return 1; }
  done
}

@test "preamble surfaces dry-run as a way to preview destructive commands" {
  run grep -E "(--dry.run|dry.run)" "$PARTIAL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Clause 2: cluster data is untrusted input (prompt injection)
# ---------------------------------------------------------------------------

@test "preamble has an Untrusted cluster data section" {
  run grep -E -i "^## .*[Uu]ntrusted" "$PARTIAL"
  [ "$status" -eq 0 ]
}

@test "preamble names prompt injection explicitly" {
  run grep -E -i "prompt injection" "$PARTIAL"
  [ "$status" -eq 0 ]
}

@test "preamble names the specific cluster data surfaces that may be attacker-controlled" {
  for kind in "pod name" "label" "annotation" "ConfigMap" "Secret" "log" event; do
    run grep -F "$kind" "$PARTIAL"
    [ "$status" -eq 0 ] || { echo "missing surface: $kind"; return 1; }
  done
}

@test "preamble forbids following instructions found in cluster data" {
  run grep -E -i "(never|do not|don.?t).*follow.*(instruction|command|directive)" "$PARTIAL"
  [ "$status" -eq 0 ]
}

@test "preamble distinguishes the user's chat as the only trusted instruction source" {
  run grep -E -i "only.*(chat|user).*(trust|instruction)|user.?s chat.*trust" "$PARTIAL"
  [ "$status" -eq 0 ]
}

# The partial is inlined verbatim into every rendered SKILL.md, so a canonical
# attack string quoted here as an illustration ships to every install and trips
# the deterministic prompt-injection scanners some host agents run over their
# context files. Describe the shape of an injection instead of reproducing one.
@test "preamble does not quote canonical injection strings that scanners flag" {
  local pattern
  for pattern in \
    "ignore (previous|prior|all|the above) instructions" \
    "disregard (your|previous|all|the above) (rules|instructions)" \
    "do ?n.?o?t tell the user" \
    "system prompt override" \
    "exfiltrat"
  do
    if grep -E -i -q "$pattern" "$PARTIAL"; then
      echo "preamble reproduces an injection string scanners match on: /$pattern/"
      return 1
    fi
  done
}

# ---------------------------------------------------------------------------
# Wiring: every skill template inlines {{PREAMBLE}}
# ---------------------------------------------------------------------------

@test "every src/skills SKILL.md.tmpl includes the {{PREAMBLE}} marker" {
  local missing=""
  for tmpl in "$SRC_ROOT/skills"/*/SKILL.md.tmpl; do
    grep -F "{{PREAMBLE}}" "$tmpl" >/dev/null || missing="$missing $tmpl"
  done
  [ -z "$missing" ] || { echo "templates missing {{PREAMBLE}}:$missing"; return 1; }
}

# ---------------------------------------------------------------------------
# End-to-end render: install renders the preamble into each skill's SKILL.md
# ---------------------------------------------------------------------------

@test "install renders the preamble content into a skill's SKILL.md" {
  use_mocks
  write_stub claude "exit 0"
  FAKE_ROOT="$TMPDIR_TEST/fake"
  stage_dev_source "$FAKE_ROOT"
  # Stage a real preamble partial so the installer can find it.
  cp "$PARTIAL" "$FAKE_ROOT/src/skills/_partials/preamble.md"
  # Demo template needs the marker too; the staged demo gets a {{PREAMBLE}}
  # appended for this test.
  printf '\n{{PREAMBLE}}\n' >> "$FAKE_ROOT/src/skills/demo/SKILL.md.tmpl"
  run "$FAKE_ROOT/scripts/install" --agent claude
  [ "$status" -eq 0 ]
  out="$FAKE_ROOT/.claude/skills/kstack-demo/SKILL.md"
  [ -f "$out" ]
  run grep -E -i "^## .*[Dd]estructive" "$out"
  [ "$status" -eq 0 ]
  run grep -E -i "prompt injection" "$out"
  [ "$status" -eq 0 ]
  run grep -F "{{PREAMBLE}}" "$out"
  [ "$status" -ne 0 ]   # marker must be replaced, not left raw
}

@test "install fails fast when the preamble partial is missing" {
  use_mocks
  write_stub claude "exit 0"
  FAKE_ROOT="$TMPDIR_TEST/fake"
  stage_dev_source "$FAKE_ROOT"
  cp "$PARTIAL" "$FAKE_ROOT/src/skills/_partials/preamble.md"
  printf '\n{{PREAMBLE}}\n' >> "$FAKE_ROOT/src/skills/demo/SKILL.md.tmpl"
  rm "$FAKE_ROOT/src/skills/_partials/preamble.md"
  run "$FAKE_ROOT/scripts/install" --agent claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing partial"* ]]
}
