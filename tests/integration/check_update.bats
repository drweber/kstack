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

  # Global-mode install layout: check-update lives at $HOME/.config/kstack/bin,
  # libs alongside at $HOME/.config/kstack/lib.
  mkdir -p "$HOME/.config/kstack/bin" "$HOME/.config/kstack/cache" \
           "$HOME/.config/kstack/lib" "$HOME/.config/kstack/manifest"
  cp "$SRC_ROOT/bin/check-update" "$HOME/.config/kstack/bin/check-update"
  cp "$SRC_ROOT/lib/cache.sh" "$HOME/.config/kstack/lib/cache.sh"
  cp "$SRC_ROOT/lib/manifest.sh" "$HOME/.config/kstack/lib/manifest.sh"
  cp "$SRC_ROOT/lib/update-check.sh" "$HOME/.config/kstack/lib/update-check.sh"
  chmod +x "$HOME/.config/kstack/bin/check-update"
  CACHE_FILE="$HOME/.config/kstack/cache/update.json"
  CHECK="$HOME/.config/kstack/bin/check-update"

  # Set installed version.
  echo "v1.0.0" > "$HOME/.config/kstack/manifest/version"
}

# stub_git is provided by test_helper.bash.

@test "check-update with stale cache refreshes from remote and prints notice" {
  stub_git
  export MOCK_TAGS="v1.0.0 v1.1.0 v2.0.0"
  cat > "$CACHE_FILE" <<EOF
{
  "last_check": "2000-01-01T00:00:00Z",
  "latest_known": "v1.0.0"
}
EOF
  run "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kstack v2.0.0 is available"* ]]
  [[ "$output" == *"you're on v1.0.0"* ]]
}

@test "check-update with fresh cache does NOT hit remote (same output from cache)" {
  stub_git
  export MOCK_TAGS=""  # if git runs, no notice possible
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cat > "$CACHE_FILE" <<EOF
{
  "last_check": "$now_iso",
  "latest_known": "v2.0.0"
}
EOF
  run "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kstack v2.0.0 is available"* ]]
}

@test "check-update prints up-to-date when latest == installed" {
  stub_git
  export MOCK_TAGS="v1.0.0"
  run "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kstack v1.0.0 is up to date"* ]]
}

@test "check-update with dismissed_version >= latest is silent/up-to-date" {
  stub_git
  export MOCK_TAGS=""
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cat > "$CACHE_FILE" <<EOF
{
  "last_check": "$now_iso",
  "latest_known": "v2.0.0",
  "dismissed_version": "v2.0.0"
}
EOF
  run "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"update to v2.0.0 dismissed"* ]]
}

@test "check-update --quiet suppresses up-to-date message" {
  stub_git
  export MOCK_TAGS="v1.0.0"
  run "$CHECK" --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check-update --quiet still prints notice when one is due" {
  stub_git
  export MOCK_TAGS="v5.0.0"
  run "$CHECK" --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"kstack v5.0.0 is available"* ]]
}

@test "check-update with no manifest/version exits silently (bail)" {
  rm -f "$HOME/.config/kstack/manifest/version"
  stub_git
  export MOCK_TAGS="v9.0.0"
  run "$CHECK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check-update with installed=main exits silently (pre-release)" {
  echo "main" > "$HOME/.config/kstack/manifest/version"
  stub_git
  export MOCK_TAGS="v9.0.0"
  run "$CHECK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check-update writes/updates cache after refresh" {
  stub_git
  export MOCK_TAGS="v1.0.0 v1.1.0 v3.0.0"
  rm -f "$CACHE_FILE"
  run "$CHECK"
  [ "$status" -eq 0 ]
  [ -f "$CACHE_FILE" ]
  run grep -F '"latest_known": "v3.0.0"' "$CACHE_FILE"
  [ "$status" -eq 0 ]
}

@test "check-update preserves dismissed_version through refresh" {
  stub_git
  export MOCK_TAGS="v1.0.0 v2.5.0"
  cat > "$CACHE_FILE" <<EOF
{
  "last_check": "2000-01-01T00:00:00Z",
  "latest_known": "v2.0.0",
  "dismissed_version": "v2.0.0"
}
EOF
  run "$CHECK"
  [ "$status" -eq 0 ]
  # Now v2.5.0 > dismissed v2.0.0, so notice should fire again.
  [[ "$output" == *"kstack v2.5.0 is available"* ]]
  grep -F '"dismissed_version": "v2.0.0"' "$CACHE_FILE"
}
