#!/usr/bin/env bash
# Block until the api deployment is Available and the mock kubetail pod is
# Ready so both the workload-existence check (step 2) and the API-presence
# check (step 5) see a settled state.
namespace="$1"
kubectl wait --for=condition=Available deployment/api -n "$namespace" --timeout=60s
kubectl wait --for=condition=Ready pod/kubetail-api-mock -n "$namespace" --timeout=60s
