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
    sleep 20
    echo "Applying Metallb config"
    kubectl apply -f resources/pool.yaml
}

function main() {
    wait_for_crds
    apply_config
}

main "$@"