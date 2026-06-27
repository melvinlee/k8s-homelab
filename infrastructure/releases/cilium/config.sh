#!/usr/bin/env bash
# Applies the Cilium LoadBalancer IP pool + L2 announcement policy once the
# Cilium CRDs are registered, then stands up the homelab Gateway once the
# cilium GatewayClass is Accepted. Run as a helmfile postsync hook.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function wait_for_crds() {
    local crds=(
        "ciliumloadbalancerippools" "ciliuml2announcementpolicies"
        "gateways" "gatewayclasses" "httproutes"
    )

    for crd in "${crds[@]}"; do
        local fqcrd
        case "${crd}" in
            gateways|gatewayclasses|httproutes)
                fqcrd="${crd}.gateway.networking.k8s.io" ;;
            *)
                fqcrd="${crd}.cilium.io" ;;
        esac
        until kubectl get crd "${fqcrd}" &>/dev/null; do
            echo "Waiting for CRD ${fqcrd} to be available..."
            sleep 10
        done
    done
}

function apply_config() {
    echo "Waiting for Cilium operator to be ready..."
    kubectl wait --namespace kube-system \
        --for=condition=available deployment/cilium-operator \
        --timeout=120s

    echo "Applying Cilium LoadBalancer config"
    kubectl apply -f "${SCRIPT_DIR}/resources/loadbalancer.yaml"
}

function apply_gateway() {
    echo "Waiting for cilium GatewayClass to be Accepted..."
    until kubectl get gatewayclass cilium &>/dev/null; do
        echo "Waiting for GatewayClass cilium..."
        sleep 5
    done
    kubectl wait gatewayclass cilium \
        --for=condition=Accepted \
        --timeout=120s

    echo "Applying homelab Gateway"
    kubectl apply -f "${SCRIPT_DIR}/resources/gateway.yaml"
}

function main() {
    wait_for_crds
    apply_config
    apply_gateway
}

main "$@"
