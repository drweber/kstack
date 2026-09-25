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

# /karpenter is an LLM-driven skill (no scripts/main). These tests pin the
# template's structure: the frontmatter contract, and the body instructions
# the agent relies on at runtime.

setup() {
  load '../test_helper.bash'
  common_setup
  TMPL="$SRC_ROOT/skills/karpenter/SKILL.md.tmpl"
}

# ---------------------------------------------------------------------------
# Frontmatter contract
# ---------------------------------------------------------------------------

@test "LLM-only skill basics (template, no scripts/main, frontmatter, partial markers)" {
  assert_llm_only_skill_basics karpenter
}

@test "description matches the README one-liner" {
  run grep -F "description: Karpenter provisioning health, node-claim diagnosis, consolidation/cost efficiency" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Read-only contract
# ---------------------------------------------------------------------------

@test "body declares the skill read-only" {
  run grep -E -i "read-only" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body rules out exec and node mutation" {
  run grep -E -i "no .kubectl exec.|never mutate|no node mutation" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Karpenter domain knowledge the body must carry
# ---------------------------------------------------------------------------

@test "body detects the served API version across all three generations" {
  for v in v1 v1beta1 v1alpha5; do
    run grep -F "$v" "$TMPL"
    [ "$status" -eq 0 ] || { echo "missing API version: $v"; return 1; }
  done
}

@test "body names the core Karpenter resources" {
  for kind in NodePool NodeClaim EC2NodeClass; do
    run grep -F "$kind" "$TMPL"
    [ "$status" -eq 0 ] || { echo "missing resource: $kind"; return 1; }
  done
}

@test "body handles a cluster with no Karpenter installed" {
  run grep -E -i "(not installed|isn't installed|no karpenter|karpenter even here)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body treats AWS-only NodeClass fields as best-effort off AWS" {
  run grep -E -i "(best-effort|non-AWS|provider-agnostic)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body names the consolidation policy values that drive cost findings" {
  for v in WhenEmpty WhenEmptyOrUnderutilized consolidateAfter; do
    run grep -F "$v" "$TMPL"
    [ "$status" -eq 0 ] || { echo "missing consolidation knob: $v"; return 1; }
  done
}

# ---------------------------------------------------------------------------
# Reporting rules
# ---------------------------------------------------------------------------

@test "body requires every finding to name its object and evidence" {
  run grep -E -i "(no evidence, no finding|names the concrete object)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body tells the agent to ask rather than invent a scope" {
  run grep -E -i "(ask one short question|never invent)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body hands off to neighbouring skills rather than widening" {
  for skill in /cluster-status /events /investigate /metrics /audit-cost; do
    run grep -F "$skill" "$TMPL"
    [ "$status" -eq 0 ] || { echo "missing handoff: $skill"; return 1; }
  done
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

@test "install renders karpenter into the dev-mode skills dir" {
  use_mocks
  write_stub claude "exit 0"
  FAKE_ROOT="$TMPDIR_TEST/fake"
  stage_dev_source "$FAKE_ROOT"
  mkdir -p "$FAKE_ROOT/src/skills/karpenter"
  cp "$TMPL" "$FAKE_ROOT/src/skills/karpenter/SKILL.md.tmpl"
  # render_help needs a matching README section per staged skill. Keep the
  # fixture README (it carries the demo section) and append the real
  # /karpenter block to it.
  awk '/^#### `\/karpenter`/ {found=1} found {print} found && /^<\/dd>$/ {exit}' \
    "$REPO_ROOT/README.md" >> "$FAKE_ROOT/README.md"

  run "$FAKE_ROOT/scripts/install" --agent claude
  [ "$status" -eq 0 ]

  local out="$FAKE_ROOT/.claude/skills/kstack-karpenter/SKILL.md"
  [ -f "$out" ]
  run grep -F "{{" "$out"
  [ "$status" -ne 0 ]   # every placeholder resolved
  run grep -F "name: kstack-karpenter" "$out"
  [ "$status" -eq 0 ]
  [ -f "$FAKE_ROOT/.claude/skills/kstack-karpenter/references/help.md" ]
}
