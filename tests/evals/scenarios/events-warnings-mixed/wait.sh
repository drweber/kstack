#!/usr/bin/env bash
# Wait until both planted pods have produced Warning events.
namespace="$1"
until kubectl get events -n "$namespace" --field-selector type=Warning \
  -o jsonpath='{range .items[*]}{.involvedObject.name}{"\n"}{end}' 2>/dev/null \
  | grep -q '^bad-puller$' \
  && kubectl get events -n "$namespace" --field-selector type=Warning \
    -o jsonpath='{range .items[*]}{.involvedObject.name}{"\n"}{end}' 2>/dev/null \
    | grep -q '^crasher$'; do
  sleep 5
done
