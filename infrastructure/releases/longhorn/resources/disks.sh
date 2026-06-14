#!/usr/bin/env bash
# Registers Longhorn's two storage tiers (issue #9). Run as a helmfile postsync
# hook, mirroring releases/cilium/config.sh.
#
#   - Fast tier (ssd): the NVMe disk at /var/lib/longhorn on every Longhorn node
#     is tagged "ssd". The default StorageClass (diskSelector: ssd, set in
#     values.yaml) pins to it, keeping general workloads on fast storage.
#   - Bulk tier (hdd): the SATA disk mounted at /var/mnt/hdd (provisioned by
#     talos/patches/worker-data-disk.yaml) is registered as a second disk on
#     each worker node and tagged "hdd" for the opt-in longhorn-hdd StorageClass.
#
# Tagging is one-directional in Longhorn (a tag only constrains volumes that
# request it), so both tiers must be tagged to keep default volumes off the HDD.
#
# All changes are idempotent JSON merge-patches against nodes.longhorn.io. The
# NVMe disk is matched by path, not its generated disk key, so it is not fragile.
# Requires: kubectl, jq.

set -euo pipefail

NAMESPACE="longhorn-system"
SSD_PATH="/var/lib/longhorn"
HDD_PATH="/var/mnt/hdd"

function require_tools() {
    for tool in kubectl jq; do
        command -v "$tool" >/dev/null 2>&1 || {
            echo "ERROR: '$tool' is required but not installed." >&2
            exit 1
        }
    done
}

function wait_for_crd() {
    until kubectl get crd nodes.longhorn.io &>/dev/null; do
        echo "Waiting for CRD nodes.longhorn.io to be available..."
        sleep 10
    done
}

# Block until the node's default disk (SSD_PATH) is registered so it can be
# looked up by path. Longhorn registers it shortly after the node CR appears.
# Longhorn stores the default path with a trailing slash (/var/lib/longhorn/),
# so paths are compared with the trailing slash stripped.
function wait_for_default_disk() {
    local node="$1"
    until kubectl -n "$NAMESPACE" get nodes.longhorn.io "$node" -o json 2>/dev/null \
        | jq -e --arg p "$SSD_PATH" \
            '(.spec.disks // {}) | to_entries[] | select((.value.path | rtrimstr("/")) == $p)' \
            >/dev/null; do
        echo "Waiting for node '$node' to register its default disk ($SSD_PATH)..."
        sleep 10
    done
}

# Tag the disk whose path == SSD_PATH with ["ssd"] (looked up by path).
function tag_ssd_disk() {
    local node="$1"
    local key
    key=$(kubectl -n "$NAMESPACE" get nodes.longhorn.io "$node" -o json \
        | jq -r --arg p "$SSD_PATH" \
            '.spec.disks | to_entries[] | select((.value.path | rtrimstr("/")) == $p) | .key')

    echo "Tagging $SSD_PATH on '$node' (disk key: $key) -> ssd"
    kubectl -n "$NAMESPACE" patch nodes.longhorn.io "$node" --type=merge \
        -p "$(jq -n --arg k "$key" '{spec:{disks:{($k):{tags:["ssd"]}}}}')"
}

# Register the HDD disk at HDD_PATH (idempotent merge — adds/updates the "hdd"
# disk without disturbing the existing default disk).
function add_hdd_disk() {
    local node="$1"
    echo "Registering $HDD_PATH on '$node' -> hdd"
    kubectl -n "$NAMESPACE" patch nodes.longhorn.io "$node" --type=merge -p '{
      "spec": {
        "disks": {
          "hdd": {
            "path": "/var/mnt/hdd",
            "diskType": "filesystem",
            "allowScheduling": true,
            "evictionRequested": false,
            "storageReserved": 0,
            "tags": ["hdd"]
          }
        }
      }
    }'
}

function main() {
    require_tools
    wait_for_crd

    # Fast tier: tag /var/lib/longhorn "ssd" on every Longhorn node.
    for node in $(kubectl -n "$NAMESPACE" get nodes.longhorn.io \
        -o jsonpath='{.items[*].metadata.name}'); do
        wait_for_default_disk "$node"
        tag_ssd_disk "$node"
    done

    # Bulk tier: register /var/mnt/hdd on worker nodes only — they carry the
    # spare SATA disk; the control plane does not.
    for node in $(kubectl get nodes -l node-role/worker=true \
        -o jsonpath='{.items[*].metadata.name}'); do
        add_hdd_disk "$node"
    done
}

main "$@"
