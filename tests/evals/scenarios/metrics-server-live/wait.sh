#!/usr/bin/env bash
# Install metrics-server (idempotent) and wait until `kubectl top` reports
# the planted pod. Kind needs --kubelet-insecure-tls because kubelet uses
# a self-signed cert.

set -eu
namespace="$1"

# Install if not present. `apply` is idempotent so re-runs are cheap.
if ! kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1; then
  kubectl apply -f \
    https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null
fi

# kind clusters: kubelet's serving cert isn't signed by the cluster CA, so
# metrics-server's TLS verification fails by default. Patch in the flag if
# it isn't already there. The `|| true` guards against the patch failing
# when the flag is already present and JSON-patch indices shift.
if ! kubectl -n kube-system get deploy metrics-server -o yaml \
     | grep -q -- '--kubelet-insecure-tls'; then
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
    >/dev/null || true
fi

# Wait for metrics-server to be Available, then for the metrics API to
# return a row for the planted pod.
kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s >/dev/null

until kubectl top pod -n "$namespace" cpu-burner --no-headers 2>/dev/null \
      | awk 'NF>=3 && $1=="cpu-burner" {found=1} END{exit !found}'; do
  sleep 5
done
