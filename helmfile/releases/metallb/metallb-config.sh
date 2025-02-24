#!/usr/bin/env bash

function wait_for_crds() {
    local crds=(
        "ipaddresspools" "ipaddresspools"
    )

    for crd in "${crds[@]}"; do
        until kubectl get crd "${crd}.metallb.io" &>/dev/null; do
            echo "Waiting for CRD $crd to be available..."
            sleep 10
        done
    done
}

function main() {
    wait_for_crds
    # apply_config
}
