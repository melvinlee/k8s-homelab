#!/usr/bin/env bash
# Install Gateway API CRDs before Cilium's Gateway controller starts.
# https://gateway-api.sigs.k8s.io/guides/#installing-gateway-api
# Idempotent — kubectl apply is safe to re-run on upgrades.
#
# We use experimental-install.yaml (a superset of standard) because Cilium 1.17.x
# registers reconcilers for ALL route types including TLSRoute (experimental), and
# crashes with "no kind is registered for TLSRouteList" when those CRDs are absent.
# Installing the experimental bundle satisfies the scheme registration without
# enabling experimental features — we only create HTTPRoute (standard) resources.

GATEWAY_API_VERSION="v1.2.0"

echo "Installing Gateway API CRDs (${GATEWAY_API_VERSION}, experimental bundle)..."
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
