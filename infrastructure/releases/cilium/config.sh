#!/usr/bin/env bash
# Applies the Cilium LoadBalancer IP pool + L2 announcement policy once the
# Cilium CRDs are registered. Run as a helmfile postsync hook.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function wait_for_crds() {
    local crds=(
        "ciliumloadbalancerippools" "ciliuml2announcementpolicies"
    )

    for crd in "${crds[@]}"; do
        until kubectl get crd "${crd}.cilium.io" &>/dev/null; do
            echo "Waiting for CRD ${crd} to be available..."
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

function main() {
    wait_for_crds
    apply_config
}

main "$@"
