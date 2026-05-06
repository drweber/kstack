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
  TMPL="$SRC_ROOT/skills/audit-network/SKILL.md.tmpl"
}

@test "LLM-only skill basics (template, no scripts/main, frontmatter, partial markers)" {
  assert_llm_only_skill_basics audit-network
}

@test "frontmatter description matches the README one-liner" {
  run grep -F "description: NetworkPolicy, Service, Ingress, Gateway API, DNS and encryption checks" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Workflows
# ---------------------------------------------------------------------------

@test "documents the NetworkPolicy workflow" {
  run grep -E "^## Workflow.*NetworkPolicy" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "NetworkPolicy workflow names default-deny gap" {
  run grep -E -i "default.deny" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "NetworkPolicy workflow names selectors that match no pods" {
  run grep -E -i "(podSelector|peer selector|selector).*(match|matches) no" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents the Service workflow" {
  run grep -E "^## Workflow.*Service" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Service workflow names zero-endpoint Services" {
  run grep -E -i "zero.*endpoint|no .*ready endpoint" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Service workflow names selector / port-vs-targetPort mismatches" {
  run grep -E -i "targetPort" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Service workflow names headless services not backing a StatefulSet" {
  run grep -E -i "headless.*statefulset|clusterip.*none.*statefulset" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents the Ingress & GatewayAPI workflow" {
  run grep -E "^## Workflow.*(Ingress|Gateway)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Ingress workflow names hostname collisions" {
  run grep -E -i "hostname collision|host.*collision" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Ingress workflow names TLS Secrets missing or expired" {
  run grep -E -i "tls.*(missing|expired)|expired.*secret" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "Ingress workflow names backends pointing at nonexistent Services" {
  run grep -E -i "backend.*service.*(no.*endpoint|does.?n.t exist|missing)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents the DNS workflow" {
  run grep -E "^## Workflow.*DNS" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "DNS workflow names CoreDNS pod health / restarts" {
  run grep -E -i "coredns.*(restart|health)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "DNS workflow names NXDOMAIN / SERVFAIL rates" {
  run grep -E "NXDOMAIN|SERVFAIL" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "DNS workflow names CoreDNS ConfigMap stub domains / forwarders" {
  run grep -E -i "(stub domain|forwarder).*coredns|coredns.*configmap" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents the Encryption / mTLS workflow" {
  run grep -E "^## Workflow.*(mTLS|Encryption)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "mTLS workflow names workloads outside mesh coverage" {
  run grep -E -i "(outside|no).*(sidecar|ambient|mesh coverage)" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "mTLS workflow names permissive (plaintext-allowed) mode" {
  run grep -E -i "permissive" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "mTLS workflow names the supported mesh CRDs (Istio/Linkerd/Cilium)" {
  run grep -E "Istio|Linkerd|Cilium" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Reporting & scoping guidance
# ---------------------------------------------------------------------------

@test "tells the agent to skip mesh / Gateway API workflows when CRDs are absent" {
  run grep -E -i "absence is not a finding|skip.*(mesh|gateway).*crd|crd.*not installed" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "TLS checks distinguish RBAC-unreadable from expired" {
  run grep -E -i "rbac.*(unread|cannot read|can.?t read)|not readable.*rbac" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "DNS active probes state the probe source" {
  run grep -E -i "probe source|state.*probe|probe.*from" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "tells the agent to include evidence, not just the verdict" {
  run grep -E -i "(include|with).*evidence|evidence.*not.*verdict" "$TMPL"
  [ "$status" -eq 0 ]
}

@test "documents handoff to /logs and /investigate" {
  run grep -F "/logs" "$TMPL"
  [ "$status" -eq 0 ]
  run grep -F "/investigate" "$TMPL"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

@test "documents optional natural-language scope argument" {
  run grep -E -i "natural.language scope" "$TMPL"
  [ "$status" -eq 0 ]
}
