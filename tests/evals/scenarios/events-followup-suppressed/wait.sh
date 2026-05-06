#!/usr/bin/env bash
# Wait until the planted pod has produced a Scheduled Normal event.
namespace="$1"
until kubectl get events -n "$namespace" --field-selector type=Normal \
  -o jsonpath='{range .items[?(@.reason=="Scheduled")]}{.involvedObject.name}{"\n"}{end}' 2>/dev/null \
  | grep -q '^quiet-sleeper$'; do
  sleep 2
done
