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
}

@test "upgrade in global location execs upstream/scripts/install --global" {
  # Stage a fake global install. The upgrade helper checks for an upstream
  # git checkout to distinguish managed installs from dev installs, so the
  # mocked upstream/ needs to be an actual (even if empty) git repo.
  mkdir -p "$HOME/.config/kstack/bin" "$HOME/.config/kstack/upstream/scripts"
  git init --quiet "$HOME/.config/kstack/upstream"
  cp "$SRC_ROOT/bin/upgrade" "$HOME/.config/kstack/bin/upgrade"
  chmod +x "$HOME/.config/kstack/bin/upgrade"
  cat > "$HOME/.config/kstack/upstream/scripts/install" <<'EOF'
#!/usr/bin/env bash
echo "GLOBAL-INSTALL:$*"
EOF
  chmod +x "$HOME/.config/kstack/upstream/scripts/install"

  run "$HOME/.config/kstack/bin/upgrade" --extra
  [ "$status" -eq 0 ]
  [[ "$output" == *"GLOBAL-INSTALL:--global --extra"* ]]
}

@test "upgrade in local layout execs upstream/scripts/install --local from project dir" {
  # Stage a fake local install: <project>/.kstack/{bin,upstream/.git,…}.
  PROJECT="$TMPDIR_TEST/proj"
  mkdir -p "$PROJECT/.kstack/bin" "$PROJECT/.kstack/upstream/scripts"
  git init --quiet "$PROJECT/.kstack/upstream"  # make it look like a checkout
  cp "$SRC_ROOT/bin/upgrade" "$PROJECT/.kstack/bin/upgrade"
  chmod +x "$PROJECT/.kstack/bin/upgrade"
  cat > "$PROJECT/.kstack/upstream/scripts/install" <<EOF
#!/usr/bin/env bash
echo "LOCAL-INSTALL:\$*:pwd=\$PWD"
EOF
  chmod +x "$PROJECT/.kstack/upstream/scripts/install"

  run "$PROJECT/.kstack/bin/upgrade" --extra
  [ "$status" -eq 0 ]
  [[ "$output" == *"LOCAL-INSTALL:--local --extra"* ]]
  # Upgrade must cd into the project dir so the installer's $PWD-based
  # ROOT_DIR resolution points back at <project>/.kstack.
  [[ "$output" == *"pwd=$PROJECT"* ]]
}
