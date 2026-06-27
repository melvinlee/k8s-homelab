# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

A bare-metal Kubernetes homelab running [Talos Linux](https://www.talos.dev/) with a GitOps workflow. Infrastructure is managed declaratively — all changes go through Git, never applied ad-hoc.

**Cluster:** 1 control-plane node (`talos-cp-01`, `192.168.1.50`) + 2 worker nodes (`talos-worker-01/02`, `192.168.1.54-55`)

## Repository Structure

```
k8s-homelab/
├── talos/                  # Talos Linux cluster bootstrap & machine configs
│   ├── schematic.yaml      # Talos factory image extensions (iscsi-tools, util-linux-tools)
│   ├── secrets.yaml        # Cluster secrets (SOPS-encrypted)
│   ├── configs/            # Generated machine configs (gitignored)
│   └── patches/            # Node-specific overlays applied at bootstrap
│       ├── cp-01.yaml          # Hostname, CNI=none + kube-proxy disabled (Cilium), PodSecurity exemptions, AllowSchedulingOnCP, Longhorn mounts
│       ├── worker-0{1,2}.yaml  # Per-worker hostname + storage mounts
│       └── worker-data-disk.yaml # UserVolumeConfig: spare SATA disk → /var/mnt/hdd (Longhorn HDD tier; both workers)
├── infrastructure/         # Core cluster infrastructure Helm releases managed by Helmfile
│   ├── helmfile.yaml        # Root helmfile (includes only core infra releases)
│   └── releases/            # One sub-helmfile per release
│       ├── cilium/          # CNI + kube-proxy replacement + LoadBalancer (L2) + Gateway API, pool 192.168.1.200-250
│       ├── pihole/          # DNS + ad-block at 192.168.1.250 (namespace: infra)
│       ├── external-dns/    # Syncs Gateway HTTPRoute hostnames → Pi-hole DNS
│       ├── longhorn/        # Distributed block storage (namespace: longhorn-system); tiered ssd/hdd disks
│       └── metrics-server/  # Backs metrics.k8s.io API (kubectl top / HPA)
└── apps/                   # Application-layer Helm releases (run on top of the cluster)
    ├── observability/       # Observability stack (namespace: monitoring)
    │   ├── helmfile.yaml    # Aggregating helmfile — includes the four releases below
    │   └── releases/        # One sub-helmfile per release
    │       ├── prometheus/  # kube-prometheus-stack
    │       ├── loki/        # Log aggregation
    │       ├── grafana/     # Dashboards
    │       └── alloy/       # Grafana Alloy log/metrics collector
    └── ai/                  # AI/LLM stack (namespace: langfuse)
        ├── helmfile.yaml    # Aggregating helmfile — includes the release(s) below
        └── releases/
            └── langfuse/    # LLM observability / tracing (postgresql + clickhouse + valkey + minio bundled, single-replica)
```

> The releases under `apps/observability/` and `apps/ai/` are each aggregated by their own `helmfile.yaml` and applied as a unit — they are **not** wired into the root `infrastructure/helmfile.yaml`.

## Common Commands

Core infra `helmfile` commands run from the `infrastructure/` directory; observability commands run from `apps/observability/`.

```bash
# Deploy all core infra releases
cd infrastructure && helmfile apply

# Preview changes before applying
cd infrastructure && helmfile diff

# Deploy a single core infra release
cd infrastructure && helmfile -l name=cilium apply

# Deploy the whole observability stack
cd apps/observability && helmfile apply

# Deploy a single observability release
cd apps/observability && helmfile -l name=prometheus apply
cd apps/observability && helmfile -f releases/loki/helmfile.yaml apply

# Deploy the AI stack (Langfuse + bundled backing stores)
cd apps/ai && helmfile -f releases/langfuse/helmfile.yaml apply
```

### Talos Operations

```bash
export TALOSCONFIG="talos/configs/talosconfig"
export CONTROL_PLANE_IP=192.168.1.50

# Apply config changes to the control-plane node
talosctl apply-config --nodes $CONTROL_PLANE_IP \
  --file talos/configs/controlplane.yaml \
  --config-patch @talos/patches/cp-01.yaml

# Bootstrap (first-time only)
talosctl config endpoint $CONTROL_PLANE_IP
talosctl config node $CONTROL_PLANE_IP
talosctl bootstrap

# Get kubeconfig
talosctl kubeconfig --nodes $CONTROL_PLANE_IP -f

# Diagnostics
talosctl dmesg --nodes $CONTROL_PLANE_IP
talosctl logs --nodes $CONTROL_PLANE_IP kubelet
talosctl reboot --nodes $CONTROL_PLANE_IP
```

### Re-generating Machine Configs

```bash
# Regenerate after secrets.yaml changes or cluster endpoint changes
talosctl gen config homelab https://$CONTROL_PLANE_IP:6443 \
  --with-docs=false --with-examples=false \
  --with-secrets talos/secrets.yaml \
  --output-dir talos/configs/
```

## Architecture Decisions

The full register lives in [`docs/adr/`](docs/adr/) (MADR format) — each decision below links to its ADR for the context, options considered, and consequences.

**Talos CNI:** CNI is set to `none` and `kube-proxy` is disabled in the control-plane patch `talos/patches/cp-01.yaml` (these are cluster-bootstrap settings — only the control plane applies the CNI/kube-proxy manifests) — Cilium handles both as a kube-proxy replacement (`kubeProxyReplacement: true`, reaching the API server via Talos KubePrism at `localhost:7445`). Do not configure a standard CNI or re-enable kube-proxy. See [ADR-0002](docs/adr/0002-cilium-cni-and-kube-proxy-replacement.md).

**LoadBalancer:** Cilium provides `LoadBalancer` IPs via L2 announcements (`CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy`, pool `192.168.1.200-250`) — this replaces the former MetalLB release. Cilium's `l2announcements` requires the kube-proxy replacement to be enabled. See [ADR-0003](docs/adr/0003-loadbalancer-via-cilium-l2.md).

**PodSecurity exemptions:** the `infra` namespace is exempted from PodSecurity admission in `talos/patches/cp-01.yaml`. Cilium runs in `kube-system`, which is exempt cluster-wide. Add new privileged namespaces there. See [ADR-0004](docs/adr/0004-podsecurity-namespace-exemptions.md).

**Longhorn storage mounts:** Worker nodes and the control-plane require the kubelet `extraMounts` for `/var/lib/longhorn` defined in each node patch file. Any new worker node patch must include these mounts. Workers additionally bind-mount `/var/mnt/hdd` (the spare SATA disk provisioned by `talos/patches/worker-data-disk.yaml`). See [ADR-0005](docs/adr/0005-longhorn-for-block-storage.md).

**Longhorn storage tiers:** Two tagged disk tiers (see #9). The fast NVMe disk `/var/lib/longhorn` is tagged `ssd`; the default `longhorn` StorageClass pins to it (`persistence.defaultDiskSelector: ssd` in `values.yaml`), so general PVCs stay on fast storage. The HDD `/var/mnt/hdd` (workers only) is tagged `hdd` and exposed via the opt-in `longhorn-hdd` StorageClass (`resources/storageclass-hdd.yaml`) — set `storageClassName: longhorn-hdd` to land a PVC there. Disk tagging + HDD registration are applied declaratively by the `releases/longhorn/resources/disks.sh` **postsync hook** (patches `nodes.longhorn.io`, matching the NVMe disk by path so it's not tied to the generated disk key; requires `jq`). Longhorn tags are one-directional, so both tiers are tagged — tagging only the HDD would not keep default volumes off it. `defaultDiskSelector` requires the Longhorn chart **≥ 1.7** (1.6.x ignores it) — the release is pinned to 1.7.2. StorageClass parameters are immutable, but the 1.6→1.7 bump recreated the default class so it picked up the selector automatically; changing the selector later without a chart change needs a one-time `kubectl delete storageclass longhorn`. See [ADR-0008](docs/adr/0008-tiered-ssd-hdd-longhorn-storage.md).

**Monitoring stack architecture:** `kube-prometheus-stack` is deployed with its bundled Grafana and Alertmanager **disabled** — standalone `grafana` and a separate Alertmanager release are used instead. The bundled stack's `forceDeployDashboards: true` pushes dashboard ConfigMaps that the standalone Grafana sidecar picks up via `grafana_dashboard: "1"` labels. See [ADR-0006](docs/adr/0006-standalone-grafana-and-alertmanager.md).

**Longhorn replica auto-balance:** `replicaAutoBalance: best-effort` is enabled and the control plane is removed from the Longhorn scheduling pool (`allowScheduling: false` on `talos-cp-01`, set in `disks.sh`) so replicas stay on the workers. Auto-balance only spreads a volume's *own* replicas, so it is a no-op for single-replica volumes. See [ADR-0009](docs/adr/0009-longhorn-replica-auto-balance-workers-only.md).

**Helmfile per-release pattern:** Each release has its own `<name>/helmfile.yaml` + `values.yaml`. An aggregating helmfile combines them via `helmfiles:` paths — `infrastructure/helmfile.yaml` for core infra releases, `apps/observability/helmfile.yaml` for the observability stack. See [ADR-0001](docs/adr/0001-adopt-gitops-with-helmfile.md).

**Cilium post-sync hook:** The cilium release uses a `presync` hook (`gateway-crds.sh`) to install Gateway API CRDs, and a `postsync` hook (`config.sh`) to apply the `CiliumLoadBalancerIPPool`, `CiliumL2AnnouncementPolicy`, and the homelab `Gateway` object after the chart is installed.

**Gateway API ingress:** All HTTP ingress is served by Cilium's built-in Gateway controller (GatewayClass `cilium`) — `ingress-nginx` has been removed. A single `Gateway` object (`homelab`, namespace `infra`) receives a LoadBalancer IP from the Cilium L2 pool; each app owns an `HTTPRoute` in its own namespace that attaches to this Gateway. Routes are applied via per-release `postsync` hooks. external-dns watches `gateway-httproute` sources to publish hostnames. See [ADR-0010](docs/adr/0010-gateway-api-migration.md).

## Naming and Conventions

- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <description>`. Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `ci`.
- No name abbreviations in YAML keys or file names.
- Constants (e.g., in scripts) use ALL_CAPS snake case.
- Domain: `homelab.local`. DNS is served by Pi-hole at `192.168.1.250`.

## Claude Code Assets

Prompt and instruction assets live under `.claude/`, **not** `.github/` — the legacy GitHub Copilot files (`.github/copilot-instructions.md`, `.github/prompts/`, `.github/prompt-snippets/`) have been migrated. Use the right asset type for the job:

| Asset | Location | When to use |
| ----- | -------- | ----------- |
| Repo-wide instructions | `CLAUDE.md` (this file) | Always-on guidance for every session |
| Skill | `.claude/skills/<name>/SKILL.md` | Reusable, auto-triggering capability with a `name`/`description` frontmatter (e.g. `commit-message`, `helmfile-deploy`) |
| Slash command | `.claude/commands/<name>.md` | A prompt template invoked manually as `/<name>` |
| Subagent | `.claude/agents/<name>.md` | A specialized agent persona (e.g. `deployment-qa`, `devops-expert`) |

`.claude/settings.local.json` holds personal, machine-local settings and is **not** committed. Commit messages must follow the `commit-message` skill (Conventional Commits, no `Co-authored-by` trailers).

## Secrets

`talos/secrets.yaml` is encrypted with SOPS/age. Never commit plaintext secrets. The `apps/observability/loki/resources/secret.yaml` is similarly encrypted. Application secrets are externalized via External Secrets Operator + Azure Key Vault (`terraform/`). See [ADR-0007](docs/adr/0007-secrets-sops-and-external-secrets-operator.md).
