# Architecture Decision Records

Significant architectural decisions for this homelab, recorded as
[MADR (Markdown Any Decision Records)](https://adr.github.io/madr/).

## Why

Decisions used to live scattered across `CLAUDE.md` and long GitHub issue
threads. An ADR captures the **context**, the **options considered**, the
**decision**, and its **consequences** in one short, versioned file — including
decisions we have since superseded (Flannel → Cilium, MetalLB → Cilium L2,
`machine.disks` → `UserVolumeConfig`).

## Conventions

- One file per decision: `NNNN-kebab-title.md`, numbered sequentially.
- Each record follows the MADR template ([`0000-template.md`](0000-template.md)):
  frontmatter (`status`, `date`) + *Context and Problem Statement*, *Decision
  Drivers*, *Considered Options*, *Decision Outcome*, and *Consequences*.
- **Never rewrite or delete an accepted ADR.** To change a decision, add a new
  ADR and set the old one's `status` to `superseded by ADR-NNNN`.

> ADRs 0001–0009 were back-filled on 2026-06-14 from decisions already in
> `CLAUDE.md` and the issue history, so their `date` reflects the back-fill, not
> the original decision.

## Index

| ADR | Title | Status |
| --- | ----- | ------ |
| [0001](0001-adopt-gitops-with-helmfile.md) | Adopt a GitOps workflow with a Helmfile per-release layout | accepted |
| [0002](0002-cilium-cni-and-kube-proxy-replacement.md) | Use Cilium as the CNI and kube-proxy replacement | accepted |
| [0003](0003-loadbalancer-via-cilium-l2.md) | Provide LoadBalancer IPs with Cilium L2 announcements | accepted |
| [0004](0004-podsecurity-namespace-exemptions.md) | Exempt selected namespaces from PodSecurity admission | accepted |
| [0005](0005-longhorn-for-block-storage.md) | Use Longhorn for distributed block storage | accepted |
| [0006](0006-standalone-grafana-and-alertmanager.md) | Run standalone Grafana and Alertmanager alongside kube-prometheus-stack | accepted |
| [0007](0007-secrets-sops-and-external-secrets-operator.md) | Manage secrets with SOPS/age and External Secrets Operator | accepted |
| [0008](0008-tiered-ssd-hdd-longhorn-storage.md) | Add a tiered ssd/hdd Longhorn storage layout | accepted |
| [0009](0009-longhorn-replica-auto-balance-workers-only.md) | Enable Longhorn replica auto-balance, workers only | accepted |
