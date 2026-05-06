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
  TMPL="$SRC_ROOT/skills/audit-cost/SKILL.md.tmpl"
}

@test "LLM-only skill basics (template, no scripts/main, frontmatter, partial markers)" {
  assert_llm_only_skill_basics audit-cost
}

@test "frontmatter description matches the README one-liner" {
  run grep -F "description: Requests vs. usage, over-provisioning, idle capacity" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Workflows
# ---------------------------------------------------------------------------

@test "documents the requests-vs-usage workflow" {
  run grep -E "^## Workflow.*requests.*usage" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "requests-vs-usage workflow names p95 as the comparison signal" {
  run grep -E -i "p95" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "requests-vs-usage workflow flags missing requests" {
  run grep -E -i "no .resources\.requests|requests.*not set|missing.*requests" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "requests-vs-usage workflow flags OOMKills against memory limit" {
  run grep -F "OOMKill" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents the idle-workloads workflow" {
  run grep -E -i "^## Workflow.*idle" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "idle workflow names Deployments/StatefulSets with zero traffic / near-zero CPU" {
  run grep -E -i "(deployment|statefulset).*(zero|idle|near.zero)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "idle workflow names Jobs/CronJobs failing or suspended" {
  run grep -E -i "(job|cronjob).*(fail|suspend)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents the unused-storage / load-balancer workflow" {
  run grep -E -i "(persistentvolume|pv|pvc|loadbalancer)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "storage workflow names PVs in Released state" {
  run grep -F "Released" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "storage workflow names PVCs bound but not mounted" {
  run grep -E -i "bound.*not mounted|not mounted by any pod" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "load-balancer workflow names LB Services with no endpoints" {
  run grep -E -i "loadbalancer.*no endpoint|type.*loadbalancer.*endpoint" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Window + sources
# ---------------------------------------------------------------------------

@test "documents the 7-day Prometheus default and metrics-server fallback" {
  run grep -E "7.day|7 day" "$TMPL"
  [ "$status" -eq 0 ]
  run grep -F "metrics-server" "$TMPL"
  [ "$status" -eq 0 ]
  run grep -F "Prometheus" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Reporting guidance
# ---------------------------------------------------------------------------

@test "tells the agent to state source + lookback in the header" {
  run grep -E -i "(header|state.*source).*lookback|source.*lookback|lookback.*header" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "tells the agent to mark Prometheus-only findings as not available" {
  run grep -E -i 'not available|"not available"|n/a' "$TMPL"
  [ "$status" -eq 0 ]
}

@test "tells the agent to skip small/noisy gaps" {
  run grep -E -i "(small|noise|noisy).*(delta|gap)|gap.*(noise|matter)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents handoff to /metrics" {
  run grep -F "/metrics" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

@test "documents optional natural-language scope argument" {
  run grep -E -i "natural.language scope" "$TMPL"
  [ "$status" -eq 0 ]
}
