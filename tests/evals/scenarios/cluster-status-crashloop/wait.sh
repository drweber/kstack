#!/usr/bin/env bash
# Wait until the crasher pod enters CrashLoopBackOff.
namespace="$1"
until kubectl get pod crasher -n "$namespace" \
  -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null \
  | grep -q 'CrashLoopBackOff'; do
  sleep 5
done
