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
# shellcheck disable=SC2034  # vars like SRC_ROOT/REPO_ROOT/FIXTURES_DIR are consumed by tests that source this file.
# Shared helpers for the kstack bats suite.
#
# Each test's setup() should call common_setup to isolate HOME in a tmpdir.

TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT is the repo top, where install/, scripts/, and src/ live.
# SRC_ROOT points at src/ — the installer payload (lib/, bin/, skills/).
REPO_ROOT="$(cd "$TEST_HELPER_DIR/.." && pwd)"
SRC_ROOT="$REPO_ROOT/src"
FIXTURES_DIR="$TEST_HELPER_DIR/fixtures"

common_setup() {
  TMPDIR_TEST="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  export HOME="$TMPDIR_TEST/home"
  mkdir -p "$HOME"
}

# File-level companion to common_setup. Call from setup_file so tests in the
# same file share state (HOME, baseline installs) while still being isolated
# from other test files. Exports TMPDIR_FILE and HOME.
common_setup_file() {
  TMPDIR_FILE="${BATS_FILE_TMPDIR:-$(mktemp -d)}"
  export HOME="$TMPDIR_FILE/home"
  mkdir -p "$HOME"
}

# Stage the files that every fake kstack checkout needs (installer, src/lib,
# demo skill + partials, README, bin/hello). Callers add their own extras
# (schemas, skill scripts, etc.) after invoking this.
stage_src_payload() {
  local root="$1"
  mkdir -p "$root/scripts" \
           "$root/src/bin" "$root/src/lib" \
           "$root/src/skills/demo" "$root/src/skills/_partials"
  cp "$REPO_ROOT/scripts/install" "$root/scripts/install"
  cp "$SRC_ROOT/lib/agents.sh" "$root/src/lib/agents.sh"
  cp "$SRC_ROOT/lib/manifest.sh" "$root/src/lib/manifest.sh"
  cp "$SRC_ROOT/lib/cache.sh" "$root/src/lib/cache.sh"
  cp "$FIXTURES_DIR/skills/demo/SKILL.md.tmpl" "$root/src/skills/demo/SKILL.md.tmpl"
  cp "$FIXTURES_DIR/skills/_partials/global-flags.md" "$root/src/skills/_partials/global-flags.md"
  cp "$FIXTURES_DIR/skills/_partials/entrypoint.md" "$root/src/skills/_partials/entrypoint.md"
  cp "$FIXTURES_DIR/skills/_partials/preamble.md" "$root/src/skills/_partials/preamble.md"
  cp "$FIXTURES_DIR/README.md" "$root/README.md"
  cat > "$root/src/bin/hello" <<'EOF'
#!/usr/bin/env bash
echo hello
EOF
  chmod +x "$root/src/bin/hello" "$root/scripts/install"
}

# Stage a dev-mode fake kstack checkout at $1. Adds src/schemas/ on top of
# the shared payload so install dev-mode tests can verify schema copying.
stage_dev_source() {
  local root="$1"
  stage_src_payload "$root"
  mkdir -p "$root/src/schemas"
  cp "$SRC_ROOT/schemas/response.schema.json" "$root/src/schemas/response.schema.json"
}

# Build a fake kstack upstream under $1: a bare repo at $1/kstack.git plus a
# working tree at $1/kstack-work committed and pushed at tag v1.2.3. Exports
# KSTACK_REMOTE_URL so install --local / --global can clone from it.
stage_fake_upstream() {
  local tmp="$1"
  local bare="$tmp/kstack.git"
  local work="$tmp/kstack-work"
  mkdir -p "$bare" "$work"
  git init --quiet --bare "$bare"
  git -c init.defaultBranch=main init --quiet "$work"

  stage_src_payload "$work"
  mkdir -p "$work/src/skills/demo/scripts"
  cat > "$work/src/skills/demo/scripts/snapshot" <<'EOF'
#!/usr/bin/env bash
echo snap
EOF
  chmod +x "$work/src/skills/demo/scripts/snapshot"

  git -C "$work" config user.email "test@example.com"
  git -C "$work" config user.name "Test"
  git -C "$work" add -A
  git -C "$work" commit --quiet -m "init"
  git -C "$work" branch -M main
  git -C "$work" tag v1.2.3
  git -C "$work" remote add origin "$bare"
  git -C "$work" push --quiet origin main
  git -C "$work" push --quiet origin v1.2.3

  export KSTACK_REMOTE_URL="$bare"
}

# Prepend a dedicated mock dir to PATH. Stubs placed here shadow system commands.
use_mocks() {
  MOCK_BIN="$TMPDIR_TEST/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
}

# Write a one-off stub to MOCK_BIN. The body is shell source executed as the stub.
write_stub() {
  local name="$1" body="$2"
  cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$MOCK_BIN/$name"
}

# Write a kubectl stub that dispatches on the first non-flag arg (the verb,
# e.g. `top`, `get`). Skips leading global flags (`--context=…`, etc.) so
# tests don't have to care about how the caller invokes kubectl. The supplied
# body should be a `case "$verb" in …` body without the surrounding case/esac.
write_kubectl_stub() {
  write_stub kubectl '
verb=""
for a in "$@"; do
  case "$a" in --*) ;; *) verb="$a"; break ;; esac
done
case "$verb" in
'"$1"'
esac
'
}

assert_file_exists() {
  if [ ! -e "$1" ]; then
    echo "expected file to exist: $1" >&2
    return 1
  fi
}

# Pin the static scaffolding shared by every LLM-only skill (no scripts/main):
# template exists at the standard path, no scripts/main, frontmatter has the
# {{SKILL_NAME}} placeholder, and the three partial markers are all present
# ({{ENTRYPOINT}}, {{GLOBAL_FLAGS}}, {{PREAMBLE}}). Per-skill description
# strings stay in their own per-file test.
assert_llm_only_skill_basics() {
  local skill="$1"
  local tmpl="$SRC_ROOT/skills/$skill/SKILL.md.tmpl"
  [ -f "$tmpl" ]                                || { echo "missing: $tmpl"; return 1; }
  [ ! -e "$SRC_ROOT/skills/$skill/scripts/main" ] || { echo "$skill is not LLM-only: scripts/main exists"; return 1; }
  grep -qF "name: {{SKILL_NAME}}" "$tmpl"       || { echo "missing {{SKILL_NAME}} placeholder in $tmpl"; return 1; }
  grep -qF "{{ENTRYPOINT}}"   "$tmpl"           || { echo "missing {{ENTRYPOINT}} marker in $tmpl"; return 1; }
  grep -qF "{{GLOBAL_FLAGS}}" "$tmpl"           || { echo "missing {{GLOBAL_FLAGS}} marker in $tmpl"; return 1; }
  grep -qF "{{PREAMBLE}}"     "$tmpl"           || { echo "missing {{PREAMBLE}} marker in $tmpl"; return 1; }
}

# stub_git [--fail] — install a git stub in MOCK_BIN that intercepts
# `git ls-remote --tags …` and falls through to real git for everything else.
# Without --fail: emits tags from the space-separated $MOCK_TAGS env var.
# With --fail: `ls-remote` exits 1 (used to simulate network failures).
stub_git() {
  use_mocks
  local mode=ok
  [ "${1:-}" = "--fail" ] && mode=fail
  local real_git
  real_git="$(command -v git)"
  if [ "$mode" = fail ]; then
    write_stub git "
REAL_GIT=$real_git
if [ \"\$1\" = 'ls-remote' ]; then exit 1; fi
exec \"\$REAL_GIT\" \"\$@\"
"
  else
    write_stub git "
REAL_GIT=$real_git
if [ \"\$1\" = 'ls-remote' ]; then
  for t in \$MOCK_TAGS; do
    printf 'abcdef\trefs/tags/%s\n' \"\$t\"
  done
  exit 0
fi
exec \"\$REAL_GIT\" \"\$@\"
"
  fi
}
