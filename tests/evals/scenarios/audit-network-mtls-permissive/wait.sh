#!/usr/bin/env bash
# Installs a minimal Istio PeerAuthentication CRD (cluster-scoped,
# defined inline so we don't need network access from the sandbox).
# Once the CRD is Established, applies the permissive policy into the
# scenario namespace. Idempotent — re-runs are no-ops.

set -eu
NS="$1"

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: peerauthentications.security.istio.io
spec:
  group: security.istio.io
  names:
    kind: PeerAuthentication
    listKind: PeerAuthenticationList
    plural: peerauthentications
    singular: peerauthentication
    shortNames: [pa]
  scope: Namespaced
  versions:
    - name: v1beta1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              x-kubernetes-preserve-unknown-fields: true
EOF

kubectl wait --for=condition=Established \
  crd/peerauthentications.security.istio.io --timeout=30s >/dev/null

kubectl apply -n "$NS" -f - >/dev/null <<'EOF'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: leaky-default
spec:
  mtls:
    mode: PERMISSIVE
EOF
