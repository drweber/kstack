#!/usr/bin/env bash
# Wait until the stand-in Alertmanager answers through the API server's
# service proxy — the exact path /alerts reads, so a green wait means the
# skill has something to talk to.
set -eu
NS="$1"

kubectl wait --for=condition=Ready pod/fake-alertmanager -n "$NS" --timeout=90s >/dev/null

until kubectl get --raw \
  "/api/v1/namespaces/$NS/services/alertmanager:9093/proxy/api/v2/alerts" >/dev/null 2>&1; do
  sleep 2
done
