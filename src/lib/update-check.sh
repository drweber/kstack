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
# shellcheck disable=SC2034  # functions set vars in the caller's scope (uc_*, NOTICE).
# kstack update-check library — shared by bin/check-update and bin/entrypoint.
#
# Source this file; do not execute it. Requires cache.sh and manifest.sh to
# be sourced first (uses resolve_cache_paths / read_cache_fields /
# write_cache_json, and manifest::read_version).

UC_DEFAULT_REMOTE_URL="https://github.com/kubetail-org/kstack.git"
UC_DEFAULT_TTL_SECS=$((24 * 60 * 60))

# Effective config — binaries may override via KSTACK_REMOTE_URL before sourcing.
UC_REMOTE_URL="${KSTACK_REMOTE_URL:-$UC_DEFAULT_REMOTE_URL}"
UC_TTL_SECS="$UC_DEFAULT_TTL_SECS"

# uc_is_newer $a $b — exit 0 if $a > $b via `sort -V`; 1 on equal or $a < $b.
uc_is_newer() {
  [ "$1" = "$2" ] && return 1
  local top
  top=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)
  [ "$top" = "$1" ] && return 0 || return 1
}

# uc_iso_to_epoch $iso_utc — echoes epoch seconds; 0 on parse failure.
uc_iso_to_epoch() {
  case "$OSTYPE" in
    darwin*|bsd*) date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || echo 0 ;;
    *)            date -d "$1" +%s 2>/dev/null || echo 0 ;;
  esac
}

# uc_resolve_installed_version $root_dir — sets INSTALLED from the install
# manifest. Emits empty when: version file is missing, empty, or pinned to
# "main" (pre-release dev checkout — no update check applies).
uc_resolve_installed_version() {
  INSTALLED="$(manifest::read_version "$1")"
  case "$INSTALLED" in
    ""|main) INSTALLED="" ;;
  esac
}

# uc_refresh_if_stale $cache_file $remote_url $ttl_secs
#   Reads $cache_file (via read_cache_fields from cache.sh), refreshes from
#   upstream tags when stale or latest is unknown, and atomically rewrites the
#   cache. Sets cache_latest / cache_dismissed in the caller. Never fails —
#   network/parse errors leave the existing cache in place.
uc_refresh_if_stale() {
  local cache_file="$1" remote_url="$2" ttl="$3"

  read_cache_fields "$cache_file"

  local now_epoch cache_epoch=0 age
  now_epoch=$(date +%s)
  [ -n "$cache_ts" ] && cache_epoch=$(uc_iso_to_epoch "$cache_ts")
  age=$((now_epoch - cache_epoch))

  if [ -z "$cache_latest" ] || [ "$age" -ge "$ttl" ] || [ "$age" -lt 0 ]; then
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null || true
    local fresh
    fresh=$(git ls-remote --tags "$remote_url" 'v*' 2>/dev/null \
      | awk -F'refs/tags/' '/refs\/tags\/v[0-9]/ && !/\^\{\}$/ { print $2 }' \
      | sort -V | tail -1)
    if [ -n "$fresh" ]; then
      cache_latest="$fresh"
      # shellcheck disable=SC2154  # cache_dismissed is populated by the read_cache_fields call above.
      write_cache_json "$cache_file" \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        "$cache_latest" \
        "$cache_dismissed"
    fi
  fi
}

# uc_notice $script_dir
#   End-to-end preamble: resolve install paths, decide if an update notice is
#   due, and set NOTICE to the single-line string (or empty). Also sets
#   INSTALLED, ROOT_DIR, CACHE_FILE, and cache_latest/cache_dismissed as a
#   side-effect so callers that want the verbose "up to date" branch still
#   have the data. Returns 0 unconditionally — the caller distinguishes the
#   "notice due" vs "nothing to say" cases by inspecting NOTICE.
uc_notice() {
  NOTICE=""
  resolve_cache_paths "$1"
  uc_resolve_installed_version "$ROOT_DIR"
  [ -z "$INSTALLED" ] && return 0
  uc_refresh_if_stale "$CACHE_FILE" "$UC_REMOTE_URL" "$UC_TTL_SECS"
  [ -z "$cache_latest" ] && return 0
  # shellcheck disable=SC2154  # cache_* vars are populated by uc_refresh_if_stale.
  uc_compute_notice "$INSTALLED" "$cache_latest" "$cache_dismissed"
}

# uc_compute_notice $installed $latest $dismissed
#   Sets NOTICE to the single-line "update available" string, or empty when
#   no notice is due (up to date, or dismissed version covers current latest).
#   Pure function — no side effects.
uc_compute_notice() {
  local installed="$1" latest="$2" dismissed="$3"
  NOTICE=""
  [ -z "$installed" ] || [ -z "$latest" ] && return 0
  uc_is_newer "$latest" "$installed" || return 0
  if [ -n "$dismissed" ] && ! uc_is_newer "$latest" "$dismissed"; then
    return 0
  fi
  NOTICE="kstack $latest is available (you're on $installed). Say \"upgrade kstack\" to install, or \"dismiss\" to hide until the next release."
}
