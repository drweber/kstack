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
# kstack install manifest — paired read/write helpers for the per-install
# manifest dir at $root/manifest/. Files are plain text, one "fact" each:
#
#   version  — single line: installed version (tag or branch name), empty
#              when unknown / detached HEAD.
#   skills   — one rendered slot name per line, sorted. Lets re-installs
#              diff against the new set to prune orphans, and lets
#              src/bin/uninstall know which slots belong to kstack.
#
# Source this file; do not execute it.

manifest::read_version() {
  cat -- "$1/manifest/version" 2>/dev/null || true
}

manifest::write_version() {
  mkdir -p "$1/manifest"
  printf '%s\n' "$2" > "$1/manifest/version"
}

manifest::read_skills() {
  cat -- "$1/manifest/skills" 2>/dev/null || true
}

# manifest::write_skills $root $slot_names... — one slot per line, sorted.
# Each argument is a single slot name (already-prefixed).
manifest::write_skills() {
  local root="$1"; shift
  mkdir -p "$root/manifest"
  local slot
  for slot in "$@"; do
    [ -n "$slot" ] && printf '%s\n' "$slot"
  done | LC_ALL=C sort > "$root/manifest/skills"
}
