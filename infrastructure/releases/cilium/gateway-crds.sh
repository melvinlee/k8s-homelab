#!/usr/bin/env bash
# Install Gateway API standard-channel CRDs before Cilium's Gateway controller starts.
# https://gateway-api.sigs.k8s.io/guides/#installing-gateway-api
# Idempotent — kubectl apply is safe to re-run on upgrades.

GATEWAY_API_VERSION="v1.2.0"

echo "Installing Gateway API CRDs (${GATEWAY_API_VERSION})..."
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
