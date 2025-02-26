#!/usr/bin/env bash

function wait_for_crds() {
    local crds=(
        "ipaddresspools" "l2advertisements"
    )

    for crd in "${crds[@]}"; do
        until kubectl get crd "${crd}.metallb.io" &>/dev/null; do
            echo "Waiting for CRD ${crd} to be available..."
            sleep 10
        done
    done
}

function apply_config() {
    echo "Waiting for MetalLB controller deployment to be ready..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=metallb,app.kubernetes.io/component=controller \
        --timeout=90s
    
    echo "Applying MetalLB config"
    kubectl apply --namespace metallb-system -f resources/pool.yaml 
}

function main() {
    wait_for_crds
    apply_config
}

main "$@"