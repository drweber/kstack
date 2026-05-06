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

# hash.sh — shared hashing utility.
#
# Source this file; do not execute it.

# hash::short_sha <value>
#   12-char sha256 prefix of <value>. Falls back to a sanitized 40-char
#   truncation when neither sha256sum nor shasum is on PATH — keeps the tool
#   usable in minimal environments at the cost of longer directory names.
hash::short_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print substr($1,1,12)}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print substr($1,1,12)}'
  else
    printf '%s' "$1" | tr -c 'A-Za-z0-9' _ | cut -c1-40
  fi
}
