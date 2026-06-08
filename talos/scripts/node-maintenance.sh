#!/usr/bin/env bash
#
# node-maintenance.sh — safely take a cluster node into maintenance.
#
# Cordons and drains a Kubernetes node, then (optionally) shuts it down or
# reboots it via Talos. When Longhorn is present, the node's replicas are first
# evicted onto another node so its instance-manager PodDisruptionBudget releases
# and the drain can complete without risking volume availability. Wraps the
# manual sequence:
#
#     kubectl cordon <node>
#     kubectl patch nodes.longhorn.io <node> ... evictionRequested=true  # if Longhorn
#     kubectl drain  <node> --ignore-daemonsets --delete-emptydir-data
#     talosctl shutdown|reboot --nodes <ip>
#
# Usage:
#   node-maintenance.sh --node <name|ip> [--action drain|shutdown|reboot]
#                       [--timeout <seconds>] [--longhorn-timeout <seconds>]
#                       [--skip-longhorn] [--dry-run] [--yes]
#
# Examples:
#   # Drain only, then leave the node cordoned for inspection
#   node-maintenance.sh --node talos-worker-01 --action drain
#
#   # Drain and power off
#   node-maintenance.sh --node talos-worker-02 --action shutdown
#
#   # Preview the steps without touching the cluster
#   node-maintenance.sh --node talos-worker-01 --dry-run
#
# Requires: kubectl, talosctl (for shutdown/reboot), a valid TALOSCONFIG.

set -euo pipefail

# --- Configuration ----------------------------------------------------------

# Known node name -> Talos endpoint IP. talosctl addresses nodes by IP, so we
# resolve friendly Kubernetes node names through this table. An IP passed
# directly on the command line is used as-is.
declare -A NODE_IP_MAP=(
    ["talos-cp-01"]="192.168.1.50"
    ["talos-worker-01"]="192.168.1.54"
    ["talos-worker-02"]="192.168.1.55"
)

# The single control-plane node — draining/powering it off takes the API
# server offline, so we guard it behind an explicit confirmation.
readonly CONTROL_PLANE_NODE="talos-cp-01"

readonly DEFAULT_ACTION="shutdown"
readonly DEFAULT_DRAIN_TIMEOUT="300"

# Fallback namespace if Longhorn's namespace cannot be auto-detected.
readonly DEFAULT_LONGHORN_NAMESPACE="longhorn-system"
# How long to wait for Longhorn to migrate replicas off the node before drain.
readonly DEFAULT_LONGHORN_TIMEOUT="900"

# --- Defaults / parsed options ----------------------------------------------

NODE=""
ACTION="${DEFAULT_ACTION}"
DRAIN_TIMEOUT="${DEFAULT_DRAIN_TIMEOUT}"
LONGHORN_TIMEOUT="${DEFAULT_LONGHORN_TIMEOUT}"
SKIP_LONGHORN="false"
DRY_RUN="false"
ASSUME_YES="false"

# Set during eviction so the recovery hint knows whether to undo it, and where.
EVICTION_REQUESTED="false"
RESOLVED_LONGHORN_NAMESPACE=""

# --- Helpers ----------------------------------------------------------------

function log() {
    echo "[node-maintenance] $*"
}

function error() {
    echo "[node-maintenance] ERROR: $*" >&2
}

function usage() {
    # Print the leading comment block (everything after the shebang up to the
    # first code line) as help text, so this stays correct as the header grows.
    sed -n '3,/^[^#]/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'
}

# Run a command, or just print it when --dry-run is set.
function run() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY-RUN: $*"
        return 0
    fi
    log "+ $*"
    "$@"
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --node)
                NODE="${2:-}"
                shift 2
                ;;
            --action)
                ACTION="${2:-}"
                shift 2
                ;;
            --timeout)
                DRAIN_TIMEOUT="${2:-}"
                shift 2
                ;;
            --longhorn-timeout)
                LONGHORN_TIMEOUT="${2:-}"
                shift 2
                ;;
            --skip-longhorn)
                SKIP_LONGHORN="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --yes | -y)
                ASSUME_YES="true"
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done
}

function validate_args() {
    if [[ -z "${NODE}" ]]; then
        error "--node is required"
        usage
        exit 1
    fi

    case "${ACTION}" in
        drain | shutdown | reboot) ;;
        *)
            error "--action must be one of: drain, shutdown, reboot (got '${ACTION}')"
            exit 1
            ;;
    esac

    if ! [[ "${DRAIN_TIMEOUT}" =~ ^[0-9]+$ ]]; then
        error "--timeout must be a positive integer number of seconds (got '${DRAIN_TIMEOUT}')"
        exit 1
    fi

    if ! [[ "${LONGHORN_TIMEOUT}" =~ ^[0-9]+$ ]]; then
        error "--longhorn-timeout must be a positive integer number of seconds (got '${LONGHORN_TIMEOUT}')"
        exit 1
    fi

    if ! command -v kubectl &>/dev/null; then
        error "kubectl not found on PATH"
        exit 1
    fi

    if [[ "${ACTION}" != "drain" ]] && ! command -v talosctl &>/dev/null; then
        error "talosctl not found on PATH (required for --action ${ACTION})"
        exit 1
    fi
}

# Resolve the Talos endpoint IP for the requested node. Accepts either a
# known node name or a literal IPv4 address.
function resolve_node_ip() {
    local node="$1"

    if [[ "${node}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "${node}"
        return 0
    fi

    if [[ -n "${NODE_IP_MAP[${node}]:-}" ]]; then
        echo "${NODE_IP_MAP[${node}]}"
        return 0
    fi

    return 1
}

function confirm() {
    local prompt="$1"

    if [[ "${ASSUME_YES}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    read -r -p "${prompt} [y/N] " reply
    [[ "${reply}" =~ ^[Yy]$ ]]
}

# --- Steps ------------------------------------------------------------------

function verify_node_exists() {
    log "Verifying node '${NODE}' exists in the cluster..."
    if ! kubectl get node "${NODE}" &>/dev/null; then
        error "Node '${NODE}' not found (kubectl get node ${NODE})"
        exit 1
    fi
}

function guard_control_plane() {
    if [[ "${NODE}" != "${CONTROL_PLANE_NODE}" ]]; then
        return 0
    fi

    error "'${NODE}' is the single control-plane node."
    error "Draining or powering it off will take the Kubernetes API server offline."
    if ! confirm "Continue anyway?"; then
        log "Aborted by user."
        exit 1
    fi
}

# Count Longhorn replicas currently placed on the target node.
function count_node_replicas() {
    local namespace="$1"
    kubectl get replicas.longhorn.io -n "${namespace}" \
        -o jsonpath='{range .items[*]}{.spec.nodeID}{"\n"}{end}' 2>/dev/null \
        | grep -Fxc "${NODE}" || true
}

# Longhorn protects its instance-manager pods with a PodDisruptionBudget while a
# node still holds the last healthy replica of a volume, which makes a plain
# `kubectl drain` retry forever (especially with single-replica volumes, where
# every replica is the last one). Ask Longhorn to migrate this node's replicas
# onto another node first, then wait until none remain so the drain can proceed
# safely. Non-fatal when Longhorn is absent or the node holds no replicas.
function evict_longhorn_replicas() {
    if [[ "${SKIP_LONGHORN}" == "true" ]]; then
        log "Skipping Longhorn replica eviction (--skip-longhorn)."
        return 0
    fi

    if ! kubectl get crd nodes.longhorn.io &>/dev/null; then
        log "Longhorn not detected; skipping replica eviction."
        return 0
    fi

    local namespace
    namespace="$(kubectl get nodes.longhorn.io -A \
        -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
    namespace="${namespace:-${DEFAULT_LONGHORN_NAMESPACE}}"
    RESOLVED_LONGHORN_NAMESPACE="${namespace}"

    if ! kubectl get nodes.longhorn.io "${NODE}" -n "${namespace}" &>/dev/null; then
        log "'${NODE}' is not a Longhorn storage node; skipping replica eviction."
        return 0
    fi

    local replica_count
    replica_count="$(count_node_replicas "${namespace}")"
    if [[ "${replica_count}" -eq 0 ]]; then
        log "No Longhorn replicas on '${NODE}'; nothing to evict."
        return 0
    fi

    log "'${NODE}' holds ${replica_count} Longhorn replica(s). Requesting eviction to other node(s)..."
    run kubectl patch nodes.longhorn.io "${NODE}" -n "${namespace}" --type=merge \
        -p '{"spec":{"allowScheduling":false,"evictionRequested":true}}'
    EVICTION_REQUESTED="true"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY-RUN: would wait up to ${LONGHORN_TIMEOUT}s for replicas to leave '${NODE}'."
        return 0
    fi

    log "Waiting up to ${LONGHORN_TIMEOUT}s for replicas to migrate off '${NODE}'..."
    local waited=0
    local interval=15
    while [[ "${waited}" -lt "${LONGHORN_TIMEOUT}" ]]; do
        replica_count="$(count_node_replicas "${namespace}")"
        if [[ "${replica_count}" -eq 0 ]]; then
            log "All replicas have migrated off '${NODE}'."
            return 0
        fi
        log "  ${replica_count} replica(s) remaining... (${waited}s/${LONGHORN_TIMEOUT}s)"
        sleep "${interval}"
        waited=$((waited + interval))
    done

    error "Longhorn replicas did not finish migrating off '${NODE}' within ${LONGHORN_TIMEOUT}s."
    error "Rebuilds may just need more time (raise --longhorn-timeout) or the target"
    error "node may lack space. Check progress with:"
    error "  kubectl get replicas.longhorn.io -n ${namespace} -o wide | grep ${NODE}"
    error "Eviction is still requested on the node; reset it if you abort with:"
    error "  kubectl patch nodes.longhorn.io ${NODE} -n ${namespace} --type=merge -p '{\"spec\":{\"evictionRequested\":false}}'"
    exit 1
}

function cordon_node() {
    log "Cordoning '${NODE}' (marking unschedulable)..."
    run kubectl cordon "${NODE}"
}

function drain_node() {
    log "Draining '${NODE}' (timeout ${DRAIN_TIMEOUT}s)..."
    if ! run kubectl drain "${NODE}" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --timeout="${DRAIN_TIMEOUT}s"; then
        error "Drain did not complete — pods may be blocked by a PodDisruptionBudget"
        error "or stuck terminating. Node remains cordoned. Investigate with:"
        error "  kubectl get pods --all-namespaces --field-selector spec.nodeName=${NODE}"
        exit 1
    fi
}

function power_node() {
    local node_ip
    if ! node_ip="$(resolve_node_ip "${NODE}")"; then
        error "Cannot resolve a Talos IP for '${NODE}'. Pass the node IP directly,"
        error "or add it to NODE_IP_MAP in this script."
        exit 1
    fi

    case "${ACTION}" in
        shutdown)
            log "Shutting down '${NODE}' (${node_ip}) via talosctl..."
            run talosctl shutdown --nodes "${node_ip}"
            ;;
        reboot)
            log "Rebooting '${NODE}' (${node_ip}) via talosctl..."
            run talosctl reboot --nodes "${node_ip}"
            ;;
    esac
}

# Print the commands needed to return the node to service once maintenance is
# done. If we asked Longhorn to evict replicas, include the reset so the node
# can host replicas again.
function print_recovery_hint() {
    log "When '${NODE}' is back online, return it to service with:"
    log "  kubectl uncordon ${NODE}"
    if [[ "${EVICTION_REQUESTED}" == "true" ]]; then
        log "  kubectl patch nodes.longhorn.io ${NODE} -n ${RESOLVED_LONGHORN_NAMESPACE} --type=merge -p '{\"spec\":{\"allowScheduling\":true,\"evictionRequested\":false}}'"
    fi
}

# --- Main -------------------------------------------------------------------

function main() {
    parse_args "$@"
    validate_args

    log "Plan: action='${ACTION}' node='${NODE}' timeout=${DRAIN_TIMEOUT}s longhorn-timeout=${LONGHORN_TIMEOUT}s dry-run=${DRY_RUN}"

    verify_node_exists
    guard_control_plane

    cordon_node
    evict_longhorn_replicas
    drain_node

    if [[ "${ACTION}" == "drain" ]]; then
        log "Drain complete. '${NODE}' remains cordoned."
        print_recovery_hint
        return 0
    fi

    power_node

    log "Done."
    print_recovery_hint
}

main "$@"
