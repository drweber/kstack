#!/usr/bin/env bash
# Block until the api deployment is Available so the workload-existence
# check (step 2) sees a settled state.
namespace="$1"
kubectl wait --for=condition=Available deployment/api -n "$namespace" --timeout=60s
