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
│       ├── controlplane.yaml   # Cluster-wide: CNI=none + kube-proxy disabled (for Cilium)
│       ├── cp-01.yaml          # Hostname, PodSecurity exemptions, AllowSchedulingOnCP, Longhorn mounts
│       └── worker-0{1,2}.yaml  # Per-worker hostname + storage mounts
├── infrastructure/         # Core cluster infrastructure Helm releases managed by Helmfile
│   ├── helmfile.yaml        # Root helmfile (includes only core infra releases)
│   └── releases/            # One sub-helmfile per release
│       ├── cilium/          # CNI + kube-proxy replacement + LoadBalancer (L2), pool 192.168.1.200-250
│       ├── ingress-nginx/   # Internal ingress controller (namespace: infra)
│       ├── pihole/          # DNS + ad-block at 192.168.1.250 (namespace: infra)
│       ├── external-dns/    # Syncs Ingress hostnames → Pi-hole DNS
│       ├── longhorn/        # Distributed block storage (namespace: infra)
│       └── metrics-server/  # Backs metrics.k8s.io API (kubectl top / HPA)
└── apps/                   # Application-layer Helm releases (run on top of the cluster)
    └── observability/       # Observability stack (namespace: monitoring)
        ├── helmfile.yaml    # Aggregating helmfile — includes the four releases below
        └── releases/        # One sub-helmfile per release
            ├── prometheus/  # kube-prometheus-stack
            ├── loki/        # Log aggregation
            ├── grafana/     # Dashboards
            └── alloy/       # Grafana Alloy log/metrics collector
```

> The observability releases under `apps/observability/` are aggregated by `apps/observability/helmfile.yaml` and applied as a unit — they are **not** wired into the root `infrastructure/helmfile.yaml`.

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
```

### Talos Operations

```bash
export TALOSCONFIG="talos/configs/talosconfig"
export CONTROL_PLANE_IP=192.168.1.50

# Apply config changes to a node (cluster-wide patch first, then node patch)
talosctl apply-config --nodes $CONTROL_PLANE_IP \
  --file talos/configs/controlplane.yaml \
  --config-patch @talos/patches/controlplane.yaml \
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

**Talos CNI:** CNI is set to `none` and `kube-proxy` is disabled in the cluster-wide patch `talos/patches/controlplane.yaml` — Cilium handles both as a kube-proxy replacement (`kubeProxyReplacement: true`, reaching the API server via Talos KubePrism at `localhost:7445`). Do not configure a standard CNI or re-enable kube-proxy.

**LoadBalancer:** Cilium provides `LoadBalancer` IPs via L2 announcements (`CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy`, pool `192.168.1.200-250`) — this replaces the former MetalLB release. Cilium's `l2announcements` requires the kube-proxy replacement to be enabled.

**PodSecurity exemptions:** the `infra` namespace is exempted from PodSecurity admission in `talos/patches/cp-01.yaml`. Cilium runs in `kube-system`, which is exempt cluster-wide. Add new privileged namespaces there.

**Longhorn storage mounts:** Worker nodes and the control-plane require the kubelet `extraMounts` for `/var/lib/longhorn` defined in each node patch file. Any new worker node patch must include these mounts.

**Monitoring stack architecture:** `kube-prometheus-stack` is deployed with its bundled Grafana and Alertmanager **disabled** — standalone `grafana` and a separate Alertmanager release are used instead. The bundled stack's `forceDeployDashboards: true` pushes dashboard ConfigMaps that the standalone Grafana sidecar picks up via `grafana_dashboard: "1"` labels.

**Helmfile per-release pattern:** Each release has its own `<name>/helmfile.yaml` + `values.yaml`. An aggregating helmfile combines them via `helmfiles:` paths — `infrastructure/helmfile.yaml` for core infra releases, `apps/observability/helmfile.yaml` for the observability stack.

**Cilium post-sync hook:** The cilium release uses a `postsync` hook that runs `releases/cilium/config.sh` to apply the `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy` CRs after the chart is installed (same pattern MetalLB previously used).

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

`talos/secrets.yaml` is encrypted with SOPS/age. Never commit plaintext secrets. The `apps/observability/loki/resources/secret.yaml` is similarly encrypted.
