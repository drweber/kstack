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
  TMPL="$SRC_ROOT/skills/audit-security/SKILL.md.tmpl"
}

@test "LLM-only skill basics (template, no scripts/main, frontmatter, partial markers)" {
  assert_llm_only_skill_basics audit-security
}

@test "frontmatter description matches the README one-liner" {
  run grep -F "description: RBAC, pod security posture, privilege tightening" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Workflows
# ---------------------------------------------------------------------------

@test "documents the RBAC workflow" {
  run grep -E -i "(^|\s)rbac" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "RBAC workflow names wildcard verbs/resources as a check" {
  run grep -E -i "wildcard.*(verb|resource|apigroup)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "RBAC workflow names cluster-admin / high-power bindings as a check" {
  run grep -F "cluster-admin" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "RBAC workflow names dangling/missing-subject bindings as a check" {
  run grep -E -i "(dangling|orphan|no longer exist|missing subject)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents the Pod security workflow" {
  run grep -E -i "pod security" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Pod security workflow names host-level escapes" {
  run grep -E -i "hostNetwork|hostPID|hostIPC|privileged" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Pod security workflow references Pod Security Standards" {
  run grep -F "Pod Security Standards" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents the Secrets & ServiceAccount tokens workflow" {
  run grep -E -i "secret.*serviceaccount|service.?account token" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Secrets workflow names legacy SA-token Secrets" {
  run grep -F "kubernetes.io/service-account-token" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Reporting guidance
# ---------------------------------------------------------------------------

@test "tells the agent to rank findings by blast radius" {
  run grep -E -i "blast radius" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "marks RBAC checks as static (not audit-log based)" {
  run grep -E -i "static" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "forbids reading or surfacing Secret contents" {
  run grep -E -i "never (read|decode|surface).*content" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "references Secrets by name, namespace, and type only" {
  run grep -E -i "name.*namespace.*type" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "tells the agent to explain why a finding matters" {
  run grep -E -i "why it matters|why this matters|why the finding" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents handoff to /investigate and /audit-network" {
  run grep -F "/investigate" "$TMPL"
  [ "$status" -eq 0 ]
  run grep -F "/audit-network" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

@test "documents optional natural-language scope argument" {
  run grep -E -i "(scope|natural.language)" "$TMPL"
  [ "$status" -eq 0 ]
}
