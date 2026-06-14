---
status: "accepted"
date: 2026-06-14
---

# 0001. Adopt a GitOps workflow with a Helmfile per-release layout

## Context and Problem Statement

This is a bare-metal Kubernetes homelab that must be reproducible and reviewable.
Ad-hoc `kubectl apply` / `helm install` commands drift from any record of how the
cluster was built and cannot be reviewed or rolled back. How should cluster state
be declared and applied?

## Decision Drivers

* Reproducibility and reviewability of every change through Git
* Avoiding configuration drift
* Ability to deploy releases individually
* Low operational overhead for a single-maintainer homelab

## Considered Options

* Helmfile with a per-release `helmfile.yaml` + `values.yaml`
* Raw Helm + shell scripts
* A pull-based GitOps controller (Argo CD / Flux)
* Kustomize-only

## Decision Outcome

Chosen option: "Helmfile per-release", because it keeps all state declarative in
Git without running an in-cluster GitOps controller to operate and upgrade.
Releases live under `infrastructure/releases/` and `apps/observability/releases/`,
aggregated by `infrastructure/helmfile.yaml` and `apps/observability/helmfile.yaml`.

### Consequences

* Good, because every change is reproducible, reviewable, and revertable
* Good, because releases deploy individually (`helmfile -l name=<release> apply`)
* Bad, because there is more boilerplate per release and one-off resources need
  Helmfile hooks instead of direct `kubectl`
* Bad, because there is no auto-reconcile — changes must be applied manually, and
  out-of-band edits are drift

## More Information

See the "Helmfile per-release pattern" note in `CLAUDE.md`.
