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

  # Stage a global install layout so dismiss-update targets $HOME/.config/kstack/cache.
  mkdir -p "$HOME/.config/kstack/bin" "$HOME/.config/kstack/cache" "$HOME/.config/kstack/lib"
  cp "$SRC_ROOT/bin/dismiss-update" "$HOME/.config/kstack/bin/dismiss-update"
  cp "$SRC_ROOT/lib/cache.sh" "$HOME/.config/kstack/lib/cache.sh"
  chmod +x "$HOME/.config/kstack/bin/dismiss-update"
  CACHE_FILE="$HOME/.config/kstack/cache/update.json"
}

@test "dismiss-update with no cache prints 'no update check has run yet'" {
  run "$HOME/.config/kstack/bin/dismiss-update"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no update check has run yet"* ]]
}

@test "dismiss-update with cache but no latest_known prints 'no known available release'" {
  cat > "$CACHE_FILE" <<EOF
{
  "last_check": "2026-01-01T00:00:00Z"
}
EOF
  run "$HOME/.config/kstack/bin/dismiss-update"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no known available release"* ]]
}

@test "dismiss-update writes dismissed_version = latest_known" {
  cat > "$CACHE_FILE" <<EOF
{
  "last_check": "2026-01-01T00:00:00Z",
  "latest_known": "v1.2.3"
}
EOF
  run "$HOME/.config/kstack/bin/dismiss-update"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dismissed update notice for kstack v1.2.3"* ]]
  run grep -F '"dismissed_version": "v1.2.3"' "$CACHE_FILE"
  [ "$status" -eq 0 ]
}

@test "dismiss-update preserves last_check timestamp" {
  cat > "$CACHE_FILE" <<EOF
{
  "last_check": "2026-01-01T00:00:00Z",
  "latest_known": "v1.2.3"
}
EOF
  run "$HOME/.config/kstack/bin/dismiss-update"
  [ "$status" -eq 0 ]
  run grep -F '"last_check": "2026-01-01T00:00:00Z"' "$CACHE_FILE"
  [ "$status" -eq 0 ]
}
