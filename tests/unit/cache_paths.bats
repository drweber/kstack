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

# Source lib/cache.sh so resolve_cache_paths is callable directly.

setup() {
  load '../test_helper.bash'
  common_setup
  . "$SRC_ROOT/lib/cache.sh"
}

@test "resolve_cache_paths: global mode points at ~/.config/kstack/cache" {
  resolve_cache_paths "$HOME/.config/kstack/bin"
  [ "$ROOT_DIR" = "$HOME/.config/kstack" ]
  [ "$CACHE_DIR" = "$HOME/.config/kstack/cache" ]
  [ "$CACHE_FILE" = "$HOME/.config/kstack/cache/update.json" ]
}

@test "resolve_cache_paths: dev/local mode points at <root>/.kstack/cache" {
  resolve_cache_paths "/fake/repo/.kstack/bin"
  [ "$ROOT_DIR" = "/fake/repo/.kstack" ]
  [ "$CACHE_DIR" = "/fake/repo/.kstack/cache" ]
  [ "$CACHE_FILE" = "/fake/repo/.kstack/cache/update.json" ]
}
