#!/usr/bin/env bash
# Wait until the planted pod has restarted at least once, so the
# investigate skill's `--previous` log fetch has something to surface.
namespace="$1"
until kubectl get pod checkout-api -n "$namespace" \
  -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null \
  | grep -qE '^[1-9]'; do
  sleep 5
done
