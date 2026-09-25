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
  . "$REPO_ROOT/scripts/install"

  SKILLS_SRC="$FIXTURES_DIR/skills"
  GF="$SKILLS_SRC/_partials/global-flags.md"
  EP="$SKILLS_SRC/_partials/entrypoint.md"
  PR="$SKILLS_SRC/_partials/preamble.md"
  README="$FIXTURES_DIR/README.md"
  OUT="$TMPDIR_TEST/out/SKILL.md"
  HELP="$TMPDIR_TEST/out/references/help.md"
  mkdir -p "$TMPDIR_TEST/out"
}

render() {
  local skill_dir="${4:-/install/path}"
  render_skill "$1" "kstack-$1" "$2" "$3" "$skill_dir" "$OUT" "$SKILLS_SRC" "$GF" "$EP" "$PR"
}

render_h() {
  render_help "$1" "$README" "$HELP"
}

@test "render_skill substitutes SKILL_NAME and AGENT" {
  render demo claude /root
  grep -F "name: kstack-demo" "$OUT"
  grep -F "agent: claude" "$OUT"
}

@test "render_skill substitutes ROOT_DIR" {
  render demo claude /my/root
  grep -F "install_root: /my/root" "$OUT"
  grep -F "bin_dir: /my/root/bin" "$OUT"
}

@test "render_skill substitutes SKILL_DIR" {
  render demo claude /root /skills/demo
  grep -F "skill_dir: /skills/demo" "$OUT"
}

@test "render_skill inlines both partials" {
  render demo claude /root
  grep -F "does one thing" "$OUT"
  grep -F "entrypoint --skill-dir" "$OUT"
}

@test "render_skill inlines the preamble partial" {
  render demo claude /root
  grep -F "fixture-preamble-marker" "$OUT"
}

@test "render_skill expands ROOT_DIR inside entrypoint partial" {
  render demo claude /opt/kstack
  grep -F "Run /opt/kstack/bin/entrypoint" "$OUT"
}

@test "render_skill leaves no raw template markers" {
  render demo claude /root
  ! grep -F '{{' "$OUT"
}

@test "render_skill creates output parent dir" {
  OUT="$TMPDIR_TEST/out/nested/sub/SKILL.md"
  render demo claude /root
  [ -f "$OUT" ]
}

@test "render_help extracts the skill section body from README" {
  render_h demo
  grep -F "A fixture skill used by tests." "$HELP"
  grep -F "nothing real" "$HELP"
  grep -F "flag-one" "$HELP"
}

@test "render_help prepends a title line for the skill" {
  render_h demo
  head -n 1 "$HELP" | grep -F "/demo"
}

@test "render_help strips <dd> and </dd> HTML tags" {
  render_h demo
  run grep -F "<dd>" "$HELP"
  [ "$status" -ne 0 ]
  run grep -F "</dd>" "$HELP"
  [ "$status" -ne 0 ]
}

@test "render_help stops at the closing </dd> of the target skill" {
  render_h demo
  # Should not leak into the /demo-with-args section below it.
  run grep -F "demo-with-args" "$HELP"
  [ "$status" -ne 0 ]
  run grep -F "Variant whose heading" "$HELP"
  [ "$status" -ne 0 ]
}

@test "render_help matches a skill whose heading carries an argument" {
  render_help demo-with-args "$README" "$HELP"
  grep -F "Variant whose heading" "$HELP"
  ! grep -F "A fixture skill used by tests." "$HELP"
}

@test "render_help appends the global flags table from README" {
  render_h demo
  grep -F "Global flags" "$HELP"
  grep -F -e "--context <ctx>" "$HELP"
  grep -F -e "--dry-run" "$HELP"
}

@test "render_help does not emit the legacy END HELP sentinel" {
  render_h demo
  ! grep -F "=== END HELP ===" "$HELP"
}

@test "render_help exits non-zero when README has no matching section" {
  run render_help nosuch-skill "$README" "$HELP"
  [ "$status" -ne 0 ]
}

@test "render_help creates output parent dir" {
  HELP="$TMPDIR_TEST/out/nested/sub/help.md"
  render_h demo
  [ -f "$HELP" ]
}
