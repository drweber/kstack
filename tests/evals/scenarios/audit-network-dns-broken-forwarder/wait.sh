#!/usr/bin/env bash
# Patches kube-system coredns ConfigMap to add a stub-domain block that
# forwards a made-up zone (BROKEN_ZONE) to BROKEN_UPSTREAM (TEST-NET-1,
# unreachable). The made-up zone keeps cluster DNS unaffected.
# Original Corefile is backed up to ConfigMap $BACKUP_CM so teardown.sh
# can restore it. BROKEN_ZONE / BROKEN_UPSTREAM are contract values —
# the rubric in expected.yaml asserts they appear in the agent's output.

set -eu

NS=kube-system
BACKUP_CM=kstack-eval-coredns-backup
BROKEN_ZONE=kstack-eval-broken.invalid
BROKEN_UPSTREAM=192.0.2.1

if ! kubectl -n "$NS" get cm "$BACKUP_CM" >/dev/null 2>&1; then
  current=$(kubectl -n "$NS" get cm coredns -o jsonpath='{.data.Corefile}')
  kubectl -n "$NS" create cm "$BACKUP_CM" --from-literal=Corefile="$current" >/dev/null

  patched=$(printf '%s\n\n%s:53 {\n    errors\n    forward . %s\n}\n' \
    "$current" "$BROKEN_ZONE" "$BROKEN_UPSTREAM")
  kubectl -n "$NS" create cm coredns --from-literal=Corefile="$patched" \
    --dry-run=client -o yaml | kubectl -n "$NS" apply -f - >/dev/null
fi

kubectl -n "$NS" rollout restart deployment coredns >/dev/null
kubectl -n "$NS" rollout status deployment coredns --timeout=90s >/dev/null
