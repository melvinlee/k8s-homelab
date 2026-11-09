---
status: accepted
date: 2026-11-09
---

# Adopt Homepage as the homelab dashboard with Gateway API service discovery

## Context and Problem Statement

Services behind the `homelab` Gateway (Grafana, Langfuse, Longhorn UI, Pi-hole, Prometheus) are
reachable only if their hostnames are remembered. A single landing page that lists them and shows
live health is needed, without a hand-maintained list of links.

See [issue #72](https://github.com/melvinlee/k8s-homelab/issues/72).

## Decision Drivers

* Must fit GitOps with Helmfile (ADR-0001): configuration as plain YAML, no UI-driven state.
* Should discover services from the Gateway API `HTTPRoute` objects every app already owns (ADR-0010).
* Stateless: no PVC, no database.
* Widget credentials must never be committed in plaintext (ADR-0007).

## Considered Options

* **Homepage (gethomepage.dev)** — YAML config in ConfigMaps, native Kubernetes integration with
  `HTTPRoute` discovery via `gethomepage.dev/*` annotations, many service widgets.
* **Glance** — lightweight, YAML-configured, but no Kubernetes service discovery.
* **Homarr** — configured through a UI and stores state in a database.
* **Dashy** — UI-edited config persisted to a file/volume; no route discovery.
* **Homer** — static YAML links only; no discovery or live status.

## Decision Outcome

Chosen option: **Homepage**, because it is the only option that is declarative, stateless and
discovers services from `HTTPRoute` annotations.

* Release in `apps/dashboard/releases/homepage/` (namespace `dashboard`), chart `jameswynn/homepage`
  pinned to 2.1.0 (app v1.2.0), aggregated by `apps/dashboard/helmfile.yaml`.
* `kubernetes.yaml`: `mode: cluster`, `gateway: true`. The chart ClusterRole is read-only
  (get/list on nodes, namespaces, pods, `httproutes`, `metrics.k8s.io`).
* Each app's HTTPRoute carries `gethomepage.dev/*` annotations (enabled, name, group, icon,
  description, pod-selector). Prometheus' route also carries the Prometheus widget annotations.
* Info widgets for cluster resources and Longhorn are defined in `values.yaml`.
* Ingress: a postsync hook applies an HTTPRoute for `homepage.home`; external-dns
  publishes it to Pi-hole. `HOMEPAGE_ALLOWED_HOSTS` is set to the same host.
* Hardened pod: non-root, read-only root filesystem, all capabilities dropped, RuntimeDefault
  seccomp, emptyDir mounts for the writable paths, pinned to worker nodes.
* The Pi-hole and Grafana widgets are deferred: they need credentials, and External Secrets
  Operator (#47) is not yet deployed.

### Deploying

```bash
cd apps/dashboard && helmfile apply
```

### Consequences

* Good — adding a service to the dashboard is an annotation on its HTTPRoute.
* Good — stateless; nothing to back up.
* Bad — the dashboard has no authentication; it is LAN-only for now.
* Neutral — Pi-hole and Grafana widgets are added once #47 provides `HOMEPAGE_VAR_*` secrets.

## More Information

* Relates to: [ADR-0001](0001-adopt-gitops-with-helmfile.md), [ADR-0007](0007-secrets-sops-and-external-secrets-operator.md),
  [ADR-0010](0010-gateway-api-migration.md).
* Docs: <https://gethomepage.dev/configs/kubernetes/>
