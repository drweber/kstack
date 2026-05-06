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

# Source entrypoint so has_help_flag is callable without running main.

setup() {
  load '../test_helper.bash'
  common_setup
  # shellcheck source=../../lib/cache.sh
  . "$SRC_ROOT/lib/cache.sh"
  # shellcheck source=../../lib/update-check.sh
  . "$SRC_ROOT/lib/update-check.sh"
  . "$SRC_ROOT/bin/entrypoint"
}

@test "has_help_flag: --help present returns 0" {
  run has_help_flag --context=foo --help
  [ "$status" -eq 0 ]
}

@test "has_help_flag: -h present returns 0" {
  run has_help_flag --context=foo -h --other
  [ "$status" -eq 0 ]
}

@test "has_help_flag: absent returns 1" {
  run has_help_flag --context=foo --namespace=bar
  [ "$status" -eq 1 ]
}

@test "has_help_flag: no args returns 1" {
  run has_help_flag
  [ "$status" -eq 1 ]
}

@test "has_help_flag: substring match does not trigger" {
  # --helper or --help-ish should not be treated as --help.
  run has_help_flag --helper --help-ish
  [ "$status" -eq 1 ]
}
