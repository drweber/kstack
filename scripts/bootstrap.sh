#!/usr/bin/env bash

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

# kstack bootstrap — hosted at https://kubestack.xyz/install.sh
#
# Intended for use via:
#
#     curl -sS https://kubestack.xyz/install.sh | bash             # global
#     curl -sS https://kubestack.xyz/install.sh | bash -s -- --local
#
# Resolves the latest tagged release of kstack, clones (or updates) a
# kstack-owned checkout under the chosen root, then hands off to
# `scripts/install` inside that checkout. All substantive logic lives
# in the in-repo installer — this bootstrap is just a getter.
#
# Modes:
#   (default)   Global install. Upstream checkout at
#               ~/.config/kstack/upstream/, skills into ~/.<agent>/skills/.
#   --local     Local install. Upstream checkout at $PWD/.kstack/upstream/,
#               skills into $PWD/.<agent>/skills/. Overwrites any existing
#               .kstack/ in the current directory.
#
# Extra flags (forwarded verbatim to scripts/install):
#   --prefix=<p>   Namespace every slot as <p><skill>/ (default: kstack-).
#   --no-prefix    Install without any prefix.
#   --agent <n>    Limit to one agent (claude, codex, …).
#
# This script is duplicated verbatim in the kubetail-website repo's
# static assets. When editing this file, update both copies.
set -eu

REPO="kubetail-org/kstack"

main() {
  # --local/--global decide where the upstream checkout lands; we leave the
  # flag in "$@" so the in-repo installer sees it too. Any other args pass
  # through unchanged.
  case " $* " in
    *" --local "*)
      ROOT="$PWD/.kstack"
      LABEL="local → $PWD"
      ;;
    *)
      ROOT="$HOME/.config/kstack"
      LABEL="global"
      ;;
  esac
  UPSTREAM_DIR="$ROOT/upstream"

  echo "🔍 Resolving latest kstack release ($LABEL)…"
  TAG=$(curl -sS "https://api.github.com/repos/$REPO/releases/latest" \
          | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
  [ -n "$TAG" ] || { echo "Could not resolve latest kstack release." >&2; exit 1; }

  if [ -d "$UPSTREAM_DIR/.git" ]; then
    echo "📥 Updating kstack @ ${TAG}…"
    git -C "$UPSTREAM_DIR" fetch --tags --quiet
    git -C "$UPSTREAM_DIR" checkout --quiet "$TAG"
  else
    echo "📥 Fetching kstack @ ${TAG}…"
    mkdir -p "$(dirname "$UPSTREAM_DIR")"
    git clone --depth 1 --branch "$TAG" --quiet "https://github.com/$REPO.git" "$UPSTREAM_DIR"
  fi
  echo ""

  # When no mode flag was passed, default to --global (historical behavior).
  case " $* " in
    *" --global "*|*" --local "*) exec "$UPSTREAM_DIR/scripts/install" "$@" ;;
    *) exec "$UPSTREAM_DIR/scripts/install" --global "$@" ;;
  esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main "$@"
fi
