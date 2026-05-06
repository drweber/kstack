#!/usr/bin/env bash
namespace="$1"
kubectl wait --for=condition=Available deployment/api -n "$namespace" --timeout=60s
