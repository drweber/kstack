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
  export KSTACK_ROOT="$TMPDIR_TEST/kstack"
  mkdir -p "$KSTACK_ROOT/lib"
  cp "$SRC_ROOT/lib/response.sh"   "$KSTACK_ROOT/lib/"
  cp "$SRC_ROOT/lib/kube-cache.sh" "$KSTACK_ROOT/lib/"
  cp "$SRC_ROOT/lib/hash.sh"       "$KSTACK_ROOT/lib/"
  export KSTACK_KUBE_CONTEXT="test-ctx"
  export KSTACK_SKILL_NAME="alerts"

  MAIN="$SRC_ROOT/skills/alerts/scripts/main"
  CALL_LOG="$TMPDIR_TEST/kubectl.log"
  SVCS="$TMPDIR_TEST/services.json"
  ALERTS="$TMPDIR_TEST/alerts.json"
  SILENCES="$TMPDIR_TEST/silences.json"

  # Default cluster: one labeled Alertmanager, the headless peer-discovery
  # Service an Operator creates beside it, and an unrelated Prometheus.
  cat > "$SVCS" << 'JSON'
{"items":[
  {"metadata":{"name":"kube-prom-alertmanager","namespace":"monitoring",
    "labels":{"app.kubernetes.io/name":"alertmanager"}},
   "spec":{"clusterIP":"10.0.0.5","ports":[{"name":"http-web","port":9093}]}},
  {"metadata":{"name":"alertmanager-operated","namespace":"monitoring"},
   "spec":{"clusterIP":"None","ports":[{"name":"http-web","port":9093}]}},
  {"metadata":{"name":"prometheus","namespace":"monitoring"},
   "spec":{"clusterIP":"10.0.0.6","ports":[{"name":"web","port":9090}]}}
]}
JSON

  printf '[]\n' > "$ALERTS"
  printf '[]\n' > "$SILENCES"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Stub kubectl so that `get services` serves $SVCS and the two Alertmanager
# proxy reads (`get --raw …/alerts`, `…/silences`) serve $ALERTS / $SILENCES.
# Every invocation is appended to $CALL_LOG.
write_am_stub() {
  use_mocks
  : > "$CALL_LOG"
  write_stub kubectl "
echo \"\$@\" >> '$CALL_LOG'
raw=''; want=0
for a in \"\$@\"; do
  if [ \"\$want\" = 1 ]; then raw=\"\$a\"; want=0; fi
  [ \"\$a\" = '--raw' ] && want=1
done
if [ -n \"\$raw\" ]; then
  case \"\$raw\" in
    *alerts*)   cat '$ALERTS' ;;
    *silences*) cat '$SILENCES' ;;
    *) echo \"unexpected raw path: \$raw\" >&2; exit 1 ;;
  esac
  exit 0
fi
cat '$SVCS'
"
}

# Write $ALERTS with one critical, one warning, one silenced, one inhibited,
# and the always-firing Watchdog canary. Timestamps are far enough in the
# past that age formatting never lands on a boundary.
seed_mixed_alerts() {
  cat > "$ALERTS" << 'JSON'
[
 {"labels":{"alertname":"KubePodCrashLooping","namespace":"payments","severity":"critical","pod":"checkout-7c9"},
  "annotations":{"summary":"Pod payments/checkout-7c9 is in a crash loop"},
  "startsAt":"2020-01-01T09:40:00.000Z",
  "status":{"state":"active","silencedBy":[],"inhibitedBy":[]}},
 {"labels":{"alertname":"KubePodCrashLooping","namespace":"payments","severity":"critical","pod":"checkout-8d1"},
  "annotations":{"summary":"Pod payments/checkout-8d1 is in a crash loop"},
  "startsAt":"2020-01-01T09:45:00.000Z",
  "status":{"state":"active","silencedBy":[],"inhibitedBy":[]}},
 {"labels":{"alertname":"TargetDown","namespace":"monitoring","severity":"warning"},
  "annotations":{"description":"30% of targets in monitoring are down"},
  "startsAt":"2020-01-01T09:00:00.000Z",
  "status":{"state":"active","silencedBy":[],"inhibitedBy":[]}},
 {"labels":{"alertname":"NodeFilesystemAlmostFull","severity":"warning"},
  "annotations":{"summary":"Filesystem on ip-10-0-3-14 has 3% space left"},
  "startsAt":"2020-01-01T08:00:00.000Z",
  "status":{"state":"suppressed","silencedBy":["sil-abc"],"inhibitedBy":[]}},
 {"labels":{"alertname":"KubeNodeNotReady","severity":"critical"},
  "annotations":{"summary":"Node ip-10-0-3-14 is not ready"},
  "startsAt":"2020-01-01T08:30:00.000Z",
  "status":{"state":"suppressed","silencedBy":[],"inhibitedBy":["fp-xyz"]}},
 {"labels":{"alertname":"Watchdog","severity":"none"},
  "annotations":{"description":"Always firing, routing canary"},
  "startsAt":"2020-01-01T07:00:00.000Z",
  "status":{"state":"active","silencedBy":[],"inhibitedBy":[]}}
]
JSON
  cat > "$SILENCES" << 'JSON'
[
 {"id":"sil-abc","status":{"state":"active"},
  "comment":"Planned disk expansion","createdBy":"alice@example.com",
  "startsAt":"2020-01-01T07:00:00.000Z","endsAt":"2099-01-01T12:00:00.000Z"},
 {"id":"sil-unused","status":{"state":"active"},
  "comment":"Mutes something that is not firing","createdBy":"bob@example.com",
  "startsAt":"2020-01-01T07:00:00.000Z","endsAt":"2099-01-01T12:00:00.000Z"}
]
JSON
}

# Return the per-context cache dir path.
cache_dir_for_ctx() {
  # shellcheck source=/dev/null
  . "$KSTACK_ROOT/lib/hash.sh"
  local sha
  sha="$(hash::short_sha "$KSTACK_KUBE_CONTEXT")"
  printf '%s/cache/kube/%s\n' "$KSTACK_ROOT" "$sha"
}

# ---------------------------------------------------------------------------
# Static checks
# ---------------------------------------------------------------------------

@test "main script exists and is executable" {
  [ -x "$MAIN" ]
}

# ---------------------------------------------------------------------------
# Error paths -- no kubectl needed
# ---------------------------------------------------------------------------

@test "main: rejects --context (entrypoint owns resolution)" {
  run "$MAIN" --context=foo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"error"'* ]]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"Unknown flag"* ]]
}

@test "main: rejects unknown flag" {
  run "$MAIN" --bogus
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"Unknown flag"* ]]
}

@test "main: requires KSTACK_KUBE_CONTEXT env var" {
  unset KSTACK_KUBE_CONTEXT
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *"KSTACK_KUBE_CONTEXT"* ]]
}

@test "main: requires KSTACK_ROOT env var" {
  unset KSTACK_ROOT
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *"KSTACK_ROOT"* ]]
}

@test "main: --ttl requires a value" {
  run "$MAIN" --ttl
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"--ttl requires a value"* ]]
}

@test "main: --service requires a value" {
  run "$MAIN" --service
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"--service requires a value"* ]]
}

@test "main: --service without a namespace is a user error" {
  write_am_stub
  run "$MAIN" --service=alertmanager
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"Invalid --service value"* ]]
}

@test "main: --service with a non-numeric port is a user error" {
  write_am_stub
  run "$MAIN" --service=monitoring/am:web
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"user"'* ]]
  [[ "$output" == *"Invalid --service value"* ]]
}

@test "main: invalid --ttl returns user error" {
  write_am_stub
  run "$MAIN" --ttl=notaduration
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"user"'* ]]
}

@test "main: missing kubectl returns infra error" {
  use_mocks
  # Same PATH curation as tests/integration/metrics.bats: keep bash + awk
  # reachable while removing kubectl, without breaking Git Bash on Windows.
  if [ -n "${MSYSTEM:-}" ] || [[ "${OSTYPE:-}" == msys* ]]; then
    PATH="$MOCK_BIN:/usr/bin:/bin" run "$MAIN"
  else
    for tool in bash awk; do
      ln -s "$(command -v "$tool")" "$MOCK_BIN/$tool"
    done
    PATH="$MOCK_BIN" run "$MAIN"
  fi
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *'kubectl'* ]]
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

@test "main: discovers the Alertmanager Service by well-known label" {
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'monitoring/kube-prom-alertmanager:9093'* ]]
}

@test "main: discovers the Alertmanager Service by name when unlabeled" {
  cat > "$SVCS" << 'JSON'
{"items":[
  {"metadata":{"name":"my-alertmanager-svc","namespace":"obs"},
   "spec":{"clusterIP":"10.0.0.9","ports":[{"name":"http","port":9093}]}}
]}
JSON
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'obs/my-alertmanager-svc:9093'* ]]
}

@test "main: skips the headless -operated Service" {
  cat > "$SVCS" << 'JSON'
{"items":[
  {"metadata":{"name":"alertmanager-operated","namespace":"monitoring"},
   "spec":{"clusterIP":"None","ports":[{"name":"http-web","port":9093}]}},
  {"metadata":{"name":"zz-alertmanager","namespace":"monitoring"},
   "spec":{"clusterIP":"10.0.0.5","ports":[{"name":"http-web","port":9093}]}}
]}
JSON
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'monitoring/zz-alertmanager:9093'* ]]
  [[ "$output" != *'alertmanager-operated'* ]]
}

@test "main: no Alertmanager is a clean ok/verbatim answer, not an error" {
  cat > "$SVCS" << 'JSON'
{"items":[
  {"metadata":{"name":"prometheus","namespace":"monitoring"},
   "spec":{"clusterIP":"10.0.0.6","ports":[{"name":"web","port":9090}]}}
]}
JSON
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"render":"verbatim"'* ]]
  [[ "$output" == *'no Alertmanager detected'* ]]
  [[ "$output" == *'--service'* ]]
}

@test "main: notes when more than one Alertmanager Service matches" {
  cat > "$SVCS" << 'JSON'
{"items":[
  {"metadata":{"name":"alertmanager","namespace":"monitoring","labels":{"app":"alertmanager"}},
   "spec":{"clusterIP":"10.0.0.5","ports":[{"name":"http-web","port":9093}]}},
  {"metadata":{"name":"alertmanager","namespace":"observability","labels":{"app":"alertmanager"}},
   "spec":{"clusterIP":"10.0.0.7","ports":[{"name":"web","port":9093}]}}
]}
JSON
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'2 Alertmanager Services matched'* ]]
  [[ "$output" == *'monitoring/alertmanager:9093'* ]]
}

@test "main: --service bypasses discovery entirely" {
  write_am_stub
  run "$MAIN" --service=obs/custom-am:9999
  [ "$status" -eq 0 ]
  [[ "$output" == *'obs/custom-am:9999'* ]]
  # Discovery never ran, so no service list was fetched.
  run grep -c 'get services' "$CALL_LOG"
  [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

@test "main: quiet Alertmanager renders the all-clear" {
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"render":"verbatim"'* ]]
  [[ "$output" == *'No alerts in Alertmanager right now.'* ]]
}

@test "main: firing alerts render as severity-tagged rows" {
  seed_mixed_alerts
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'CRIT'* ]]
  [[ "$output" == *'payments/KubePodCrashLooping'* ]]
  [[ "$output" == *'WARN'* ]]
  [[ "$output" == *'monitoring/TargetDown'* ]]
  [[ "$output" == *'3 firing (2 critical)'* ]]
}

@test "main: identical alerts collapse into one counted row" {
  seed_mixed_alerts
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  # The two crash-looping pods share (alertname, namespace, severity).
  [[ "$output" == *'2×'* ]]
}

@test "main: suppressed alerts collapse into a tail line split by cause" {
  seed_mixed_alerts
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'2 suppressed (1 silenced, 1 inhibited)'* ]]
  # Collapsed, not rendered as rows.
  [[ "$output" != *'NodeFilesystemAlmostFull '* ]]
}

@test "main: always-on canaries collapse into their own tail line" {
  seed_mixed_alerts
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'always-on canary hidden (Watchdog)'* ]]
  # Watchdog must not inflate the firing count.
  [[ "$output" == *'3 firing (2 critical)'* ]]
}

@test "main: the canary tail line agrees in number" {
  cat > "$ALERTS" << 'JSON'
[{"labels":{"alertname":"Watchdog","severity":"none"},
  "annotations":{"description":"routing canary"},
  "startsAt":"2020-01-01T07:00:00.000Z",
  "status":{"state":"active","silencedBy":[],"inhibitedBy":[]}},
 {"labels":{"alertname":"InfoInhibitor","severity":"none"},
  "annotations":{"description":"inhibits info-level alerts"},
  "startsAt":"2020-01-01T07:00:00.000Z",
  "status":{"state":"active","silencedBy":[],"inhibitedBy":[]}}]
JSON
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'2 always-on canaries hidden'* ]]
  [[ "$output" == *'InfoInhibitor'* ]]
  [[ "$output" == *'Watchdog'* ]]
}

@test "main: only silences that mute something are listed" {
  seed_mixed_alerts
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Active silences:'* ]]
  [[ "$output" == *'Planned disk expansion'* ]]
  [[ "$output" == *'alice@example.com'* ]]
  [[ "$output" != *'bob@example.com'* ]]
}

@test "main: an alert with no recognized severity renders as ALRT" {
  cat > "$ALERTS" << 'JSON'
[{"labels":{"alertname":"CustomThing","namespace":"team-a"},
  "annotations":{"summary":"something happened"},
  "startsAt":"2020-01-01T09:00:00.000Z",
  "status":{"state":"active","silencedBy":[],"inhibitedBy":[]}}]
JSON
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'ALRT'* ]]
  [[ "$output" == *'team-a/CustomThing'* ]]
}

@test "main: nothing firing but something suppressed says so" {
  cat > "$ALERTS" << 'JSON'
[{"labels":{"alertname":"NodeFilesystemAlmostFull","severity":"warning"},
  "annotations":{"summary":"disk nearly full"},
  "startsAt":"2020-01-01T08:00:00.000Z",
  "status":{"state":"suppressed","silencedBy":["sil-abc"],"inhibitedBy":[]}}]
JSON
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Nothing firing.'* ]]
  [[ "$output" == *'1 suppressed'* ]]
}

# ---------------------------------------------------------------------------
# Envelope plumbing
# ---------------------------------------------------------------------------

@test "main: envelope carries kube_context" {
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kube_context":"test-ctx"'* ]]
}

@test "main: envelope carries agent_context with the cache paths and target" {
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"agent_context"'* ]]
  [[ "$output" == *'cache_dir'* ]]
  [[ "$output" == *'alerts_file'* ]]
  [[ "$output" == *'silences_file'* ]]
  [[ "$output" == *'alertmanager'* ]]
}

# ---------------------------------------------------------------------------
# Proxy failures
# ---------------------------------------------------------------------------

@test "main: a denied service proxy read returns an infra error naming the RBAC verb" {
  use_mocks
  : > "$CALL_LOG"
  write_stub kubectl "
for a in \"\$@\"; do
  if [ \"\$a\" = '--raw' ]; then
    echo 'Error from server (Forbidden): services is forbidden' >&2
    exit 1
  fi
done
cat '$SVCS'
"
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *'services/proxy'* ]]
  [[ "$output" == *'Forbidden'* ]]
}

@test "main: an unparseable Alertmanager response returns an infra error" {
  use_mocks
  : > "$CALL_LOG"
  write_stub kubectl "
for a in \"\$@\"; do
  if [ \"\$a\" = '--raw' ]; then printf '<html>502 Bad Gateway</html>\n'; exit 0; fi
done
cat '$SVCS'
"
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *'could not parse'* ]]
}

@test "main: a failing service list returns an infra error" {
  use_mocks
  write_stub kubectl 'exit 1'
  run "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind":"infra"'* ]]
  [[ "$output" == *"Unable to fetch services"* ]]
}

# ---------------------------------------------------------------------------
# Cache behavior
# ---------------------------------------------------------------------------

@test "main: reuses the cached snapshot within TTL (no kubectl call)" {
  write_am_stub
  run "$MAIN" --ttl=1h
  [ "$status" -eq 0 ]

  : > "$CALL_LOG"
  run "$MAIN" --ttl=1h
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [ ! -s "$CALL_LOG" ]
}

@test "main: --refresh bypasses a fresh cache" {
  write_am_stub
  run "$MAIN" --ttl=1h
  [ "$status" -eq 0 ]

  : > "$CALL_LOG"
  run "$MAIN" --refresh
  [ "$status" -eq 0 ]
  [ -s "$CALL_LOG" ]
}

@test "main: pointing --service at another Alertmanager does not read the first one's cache" {
  seed_mixed_alerts
  write_am_stub
  run "$MAIN" --service=monitoring/am-one --ttl=1h
  [ "$status" -eq 0 ]
  [[ "$output" == *'3 firing'* ]]

  # Second target, same TTL window: must fetch rather than reuse am-one's files.
  printf '[]\n' > "$ALERTS"
  : > "$CALL_LOG"
  run "$MAIN" --service=monitoring/am-two --ttl=1h
  [ "$status" -eq 0 ]
  [ -s "$CALL_LOG" ]
  [[ "$output" == *'No alerts in Alertmanager right now.'* ]]
}

@test "main: freshness line says 'Snapshot cached' on a fresh fetch" {
  write_am_stub
  run "$MAIN" --refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *'Snapshot cached'* ]]
}

@test "main: cache files land in the per-context cache dir" {
  write_am_stub
  run "$MAIN"
  [ "$status" -eq 0 ]
  local dir
  dir="$(cache_dir_for_ctx)"
  run bash -c "ls '$dir' | grep -c 'alertmanager-.*-alerts.json'"
  [ "$output" = "1" ]
}
