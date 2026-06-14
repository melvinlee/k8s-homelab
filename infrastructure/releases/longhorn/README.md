# Longhorn — distributed block storage (tiered)

Longhorn provides the cluster's block storage. Disks are split into two tagged
tiers so fast and bulk storage are addressable independently (issue #9).

## Storage tiers

| Tier | Disk | Path | Tag | StorageClass |
| ---- | ---- | ---- | --- | ------------ |
| Fast (default) | NVMe | `/var/lib/longhorn` | `ssd` | `longhorn` (default) |
| Bulk (opt-in)  | SATA HDD (workers) | `/var/mnt/hdd` | `hdd` | `longhorn-hdd` |

PVCs default to the fast tier. To place a volume on the HDD, set
`storageClassName: longhorn-hdd`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bulk-data
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: longhorn-hdd
  resources:
    requests:
      storage: 100Gi
```

## How the tiers are wired

- **HDD provisioning (Talos):** `talos/patches/worker-data-disk.yaml` is a
  `UserVolumeConfig` that formats the spare SATA disk (`xfs`) and auto-mounts it
  at `/var/mnt/hdd` on both workers. The worker patches bind-mount that path into
  the kubelet so Longhorn can use it.
- **Disk tagging + registration (`resources/disks.sh`, postsync hook):** tags every node's
  `/var/lib/longhorn` disk `ssd` (matched by path), and registers `/var/mnt/hdd`
  as the `hdd` disk on worker nodes. Idempotent `nodes.longhorn.io` merge-patches.
  Requires `kubectl` + `jq` on the machine running `helmfile apply`.
- **Default class → ssd (`values.yaml`):** `persistence.defaultDiskSelector`
  pins the default `longhorn` class to the `ssd` tier. Longhorn disk tags are
  one-directional (a tag only constrains volumes that *request* it), so both
  tiers are tagged — tagging only the HDD would not keep default volumes off it.
- **`longhorn-hdd` class (`resources/storageclass-hdd.yaml`):** applied by a
  postsync hook for opt-in bulk volumes (`diskSelector: hdd`).

## Chart version & the immutable-StorageClass caveat

`persistence.defaultDiskSelector` only exists in the Longhorn chart from **1.7**
onward — 1.6.x silently ignores it. This release is pinned to **1.7.2**.

StorageClass parameters are **immutable**, but the 1.6→1.7 chart bump recreated
the default class, so it picked up `diskSelector: ssd` automatically — no manual
step was needed. If you ever change the selector *without* a chart change, the
existing class must be recreated once:

```bash
kubectl delete storageclass longhorn   # Longhorn recreates it from the updated ConfigMap
```

Safe — PVs reference the provisioner (`driver.longhorn.io`), not the class, and
existing volumes already live on the NVMe disk, so nothing reschedules.
Tags/selectors only affect **newly** provisioned volumes.
