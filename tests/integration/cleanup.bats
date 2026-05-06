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

# /cleanup is an LLM-driven skill (no scripts/main). These tests pin the
# template's structure: frontmatter contract + body instructions the agent
# relies on at runtime.

setup() {
  load '../test_helper.bash'
  common_setup
  TMPL="$SRC_ROOT/skills/cleanup/SKILL.md.tmpl"
}

@test "LLM-only skill basics (template, no scripts/main, frontmatter, partial markers)" {
  assert_llm_only_skill_basics cleanup
}

@test "frontmatter sets disable-model-invocation: true" {
  run grep -E "^disable-model-invocation:[[:space:]]*true" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "description matches the README one-liner" {
  run grep -F "description: Remove all kstack-owned resources from the cluster" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body names the owned-by annotation key" {
  run grep -F "kstack.kubetail.com/owned-by=kstack" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body instructs the agent to list before deleting" {
  run grep -E -i "(list|group).*(namespace|kind)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body requires explicit user confirmation" {
  run grep -E -i "confirm" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body instructs the agent to never touch un-annotated resources" {
  run grep -E -i "without the annotation|not annotated|un-annotated|never.*touch" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "body instructs the agent to report failures rather than retry blindly" {
  run grep -E -i "(report|surface).*(fail|error|remain)" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Rendering (end-to-end through the installer)
# ---------------------------------------------------------------------------

@test "install renders cleanup into the dev-mode skills dir" {
  use_mocks
  write_stub claude "exit 0"
  FAKE_ROOT="$TMPDIR_TEST/fake"
  stage_dev_source "$FAKE_ROOT"
  # Copy the real cleanup skill on top of the staged demo.
  mkdir -p "$FAKE_ROOT/src/skills/cleanup"
  cp "$TMPL" "$FAKE_ROOT/src/skills/cleanup/SKILL.md.tmpl"
  # Add a README section so render_help succeeds for /cleanup.
  cat >> "$FAKE_ROOT/README.md" <<'EOF'

#### `/cleanup`

<dd>
Remove every kstack-owned resource from the cluster.
</dd>
EOF
  run "$FAKE_ROOT/scripts/install" --agent claude
  [ "$status" -eq 0 ]
  out="$FAKE_ROOT/.claude/skills/kstack-cleanup/SKILL.md"
  [ -f "$out" ]
  run grep -F "name: kstack-cleanup" "$out"
  [ "$status" -eq 0 ]
  run grep -E "^disable-model-invocation:[[:space:]]*true" "$out"
  [ "$status" -eq 0 ]
  run grep -F "kstack.kubetail.com/owned-by=kstack" "$out"
  [ "$status" -eq 0 ]
}
