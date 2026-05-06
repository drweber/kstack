#!/usr/bin/env bash
# Restores the kube-system coredns Corefile from $BACKUP_CM created by
# wait.sh, then deletes the backup. Idempotent — re-runs are a no-op
# once the backup is gone.

set -eu

NS=kube-system
BACKUP_CM=kstack-eval-coredns-backup

original=$(kubectl -n "$NS" get cm "$BACKUP_CM" -o jsonpath='{.data.Corefile}' 2>/dev/null || true)
[ -n "$original" ] || exit 0

kubectl -n "$NS" create cm coredns --from-literal=Corefile="$original" \
  --dry-run=client -o yaml | kubectl -n "$NS" apply -f - >/dev/null
kubectl -n "$NS" delete cm "$BACKUP_CM" --ignore-not-found >/dev/null
kubectl -n "$NS" rollout restart deployment coredns >/dev/null
kubectl -n "$NS" rollout status deployment coredns --timeout=60s >/dev/null
