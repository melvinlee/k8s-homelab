---
status: "accepted"
date: 2026-06-14
---

# 0008. Add a tiered ssd/hdd Longhorn storage layout

## Context and Problem Statement

Each worker has a spare 500 GB SATA disk in addition to its NVMe OS disk. We want
extra bulk capacity that is **opt-in**, so general PVCs stay on fast NVMe and only
chosen workloads use the slow disk. A deprecated, uncommitted `machine.disks`
config was also drifting on the live nodes. How should the second disk be
provisioned and exposed to Longhorn?

## Decision Drivers

* Future-proof disk provisioning (Talos `machine.disks` is deprecated)
* Robust disk selection (not the unstable `/dev/sda` name, shared with iSCSI)
* Fast-by-default scheduling with an opt-in bulk tier

## Considered Options

* Keep the deprecated `machine.disks` mount
* Provision via a Talos `UserVolumeConfig`
* One untagged Longhorn pool vs. two tagged tiers

## Decision Outcome

Chosen option: "`UserVolumeConfig` + tagged tiers". Talos `worker-data-disk.yaml`
formats `/dev/sda` (xfs) and mounts it at `/var/mnt/hdd`, selected by property.
`disks.sh` tags the NVMe disk `ssd` and the HDD `hdd`; the default `longhorn`
StorageClass pins to `ssd`, and a `longhorn-hdd` class targets `hdd`. Requires the
Longhorn chart ≥ 1.7 for `defaultDiskSelector`.

### Consequences

* Good, because capacity is tiered with fast storage as the default and the layout
  is GitOps-tracked (no drift)
* Bad, because Longhorn tags are one-directional, so **both** tiers must be tagged
* Bad, because StorageClass parameters are immutable (one-time recreate caveat),
  the hook needs `jq`, and the change required a chart bump to 1.7

## More Information

Supersedes the deprecated `machine.disks` mount. Extends
[ADR-0005](0005-longhorn-for-block-storage.md). See
`infrastructure/releases/longhorn/README.md` and issue #9.
