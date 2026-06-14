---
status: "accepted"
date: 2026-06-14
---

# 0009. Enable Longhorn replica auto-balance, workers only

## Context and Problem Statement

Longhorn replicas had concentrated on a single worker (`talos-worker-01`). We want
volumes to distribute across the workers and to keep the control plane out of the
storage pool. How should replica placement be steered?

## Decision Drivers

* Even replica distribution across nodes
* Keep the 4-core, tainted control plane free of volume I/O
* Declarative, GitOps-managed configuration

## Considered Options

* `replica-auto-balance: best-effort`
* Raise `defaultReplicaCount` to 2 (a replica per worker)
* Manually move replicas, keeping count 1
* Do nothing

## Decision Outcome

Chosen option: "`best-effort` auto-balance + exclude the control plane". We set
`defaultSettings.replicaAutoBalance: best-effort` and, via `disks.sh`,
`allowScheduling: false` on the `talos-cp-01` Longhorn node. Rebalancing the
existing single-replica volumes is **deferred** (issue #49 stays open).

### Consequences

* Good, because multi-replica volumes self-balance and the control plane stays
  workload-free
* Bad, because auto-balance is a **no-op for single-replica volumes** (it only
  spreads a volume's *own* replicas), so the current imbalance is unresolved
* Bad, because when it does act, moving a replica is a live rebuild (real I/O)

## More Information

Extends [ADR-0005](0005-longhorn-for-block-storage.md). See issue #49 for the
deferred rebalance options.
