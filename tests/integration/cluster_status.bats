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
  # KSTACK_ROOT is the cache base — a fresh tmpdir keeps tests off the repo
  # cache dir and sidesteps Windows symlink issues. The two libs main sources
  # via $KSTACK_ROOT/lib/ are copied in rather than symlinked for the same
  # reason.
  export KSTACK_ROOT="$TMPDIR_TEST/kstack"
  mkdir -p "$KSTACK_ROOT/lib"
  cp "$SRC_ROOT/lib/response.sh"   "$KSTACK_ROOT/lib/"
  cp "$SRC_ROOT/lib/kube-cache.sh" "$KSTACK_ROOT/lib/"
  export KSTACK_KUBE_CONTEXT="test-ctx"
}

@test "main script exists and is executable" {
  [ -x "$SRC_ROOT/skills/cluster-status/scripts/main" ]
}

@test "main: rejects --context (entrypoint owns resolution)" {
  run "$SRC_ROOT/skills/cluster-status/scripts/main" --context=foo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"Unknown flag"* ]]
}

@test "main: requires KSTACK_KUBE_CONTEXT env var" {
  unset KSTACK_KUBE_CONTEXT
  run "$SRC_ROOT/skills/cluster-status/scripts/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *"KSTACK_KUBE_CONTEXT"* ]]
}

@test "main: ensure_version, nodes, and pods fetches run in parallel" {
  # 3-process barrier: each kubectl invocation drops a start_<id> marker, then
  # polls (~1s) for three siblings to appear. If they do, it drops an
  # all_started_<id> marker. Sequential execution can produce at most one
  # all_started marker (the third fetch sees the prior two start files);
  # parallel execution produces all three. Asserting on the marker count
  # avoids any wall-clock heuristic.
  use_mocks
  local stub_log="$TMPDIR_TEST/stub"
  mkdir -p "$stub_log"
  write_stub kubectl "
LOG_DIR='$stub_log'
args=\"\$*\"
case \"\$args\" in
  *version*)     id=version ;;
  *'get nodes'*) id=nodes ;;
  *'get pods'*)  id=pods ;;
  *)             id=other ;;
esac
touch \"\$LOG_DIR/start_\$id\"
for _ in \$(seq 1 100); do
  count=\$(ls \"\$LOG_DIR\"/start_* 2>/dev/null | wc -l)
  [ \"\$count\" -ge 3 ] && break
  sleep 0.01
done
if [ \"\$(ls \"\$LOG_DIR\"/start_* 2>/dev/null | wc -l)\" -ge 3 ]; then
  touch \"\$LOG_DIR/all_started_\$id\"
fi
case \"\$id\" in
  version) printf '{\"serverVersion\":{\"gitVersion\":\"v1.30.0\"}}\n' ;;
  *)       printf '{\"kind\":\"List\",\"items\":[]}\n' ;;
esac
"

  # Don't assert on $status — render libs may not love empty-list payloads
  # and that's fine; we only care that all three fetches got launched
  # concurrently.
  run "$SRC_ROOT/skills/cluster-status/scripts/main"

  local n
  n=$(find "$stub_log" -maxdepth 1 -name 'all_started_*' | wc -l | tr -d ' ')
  [ "$n" = "3" ]
}
