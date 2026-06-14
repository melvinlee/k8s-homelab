---
status: "accepted"
date: 2026-06-14
---

# 0005. Use Longhorn for distributed block storage

## Context and Problem Statement

Applications need dynamically provisioned `ReadWriteOnce` block storage that can
move with workloads across the worker nodes. What storage layer should the
cluster provide?

## Decision Drivers

* Dynamic provisioning via a CSI driver
* Replication across nodes for data that needs it
* Manageable on a small bare-metal cluster (UI, low operational burden)

## Considered Options

* Longhorn
* Rook / Ceph
* OpenEBS
* `local-path` provisioner (node-local only)

## Decision Outcome

Chosen option: "Longhorn", because it offers dynamic CSI provisioning,
node-replicated volumes, and a UI with far less operational weight than Ceph. It
runs in the `longhorn-system` namespace with `defaultReplicaCount: 1`; every node
patch declares the kubelet `extraMounts` for `/var/lib/longhorn`.

### Consequences

* Good, because PVs are dynamic and replication-capable, with a management UI
* Bad, because `defaultReplicaCount: 1` means no redundancy unless a volume opts
  into more replicas
* Bad, because every node patch must include the `/var/lib/longhorn` host mount

## More Information

Extended by [ADR-0008](0008-tiered-ssd-hdd-longhorn-storage.md) (tiered disks)
and [ADR-0009](0009-longhorn-replica-auto-balance-workers-only.md) (auto-balance).
