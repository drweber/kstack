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
# shellcheck disable=SC2034  # this lib populates vars in the caller's scope; "unused" reads are in the sourcing script.
# kstack update cache — shared by check-update and dismiss-update.
#
# Source this file; do not execute it. Requires $HOME.

# resolve_cache_paths $script_dir — sets ROOT_DIR, CACHE_DIR, CACHE_FILE.
# Both modes live under {root}/bin/<helper>, so root is dirname($script_dir).
resolve_cache_paths() {
  ROOT_DIR="$(dirname "$1")"
  CACHE_DIR="$ROOT_DIR/cache"
  CACHE_FILE="$CACHE_DIR/update.json"
}

# read_cache_fields $cache_file
#   Sets cache_ts / cache_latest / cache_dismissed in one awk pass. Sets empty
#   strings when the file is missing or a field isn't present.
read_cache_fields() {
  cache_ts=""
  cache_latest=""
  cache_dismissed=""
  [ -f "$1" ] || return 0
  local _awk_out
  _awk_out="$(awk -F'"' '
    /"last_check"[[:space:]]*:/        { ts = $4 }
    /"latest_known"[[:space:]]*:/      { latest = $4 }
    /"dismissed_version"[[:space:]]*:/ { dismissed = $4 }
    END { print ts; print latest; print dismissed }
  ' "$1")"
  {
    IFS= read -r cache_ts
    IFS= read -r cache_latest
    IFS= read -r cache_dismissed
  } <<< "$_awk_out"
}

# write_cache_json $cache_file $last_check $latest_known [$dismissed_version]
#   Atomic-replaces $cache_file. Omits the dismissed_version line when empty.
write_cache_json() {
  local file="$1" ts="$2" latest="$3" dismissed="${4:-}"
  {
    printf '{\n'
    printf '  "last_check": "%s",\n' "$ts"
    if [ -n "$dismissed" ]; then
      printf '  "latest_known": "%s",\n' "$latest"
      printf '  "dismissed_version": "%s"\n' "$dismissed"
    else
      printf '  "latest_known": "%s"\n' "$latest"
    fi
    printf '}\n'
  } > "$file.tmp" 2>/dev/null \
    && mv "$file.tmp" "$file" 2>/dev/null \
    || rm -f "$file.tmp" 2>/dev/null
}
