#!/usr/bin/env bash
# Wait until the bad-puller pod reaches ErrImagePull or ImagePullBackOff.
namespace="$1"
until kubectl get pod bad-puller -n "$namespace" \
  -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null \
  | grep -qE 'ErrImagePull|ImagePullBackOff'; do
  sleep 5
done
