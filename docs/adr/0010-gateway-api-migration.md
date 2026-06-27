---
status: accepted
date: 2026-06-27
---

# Migrate cluster ingress from ingress-nginx to Kubernetes Gateway API (Cilium GatewayClass)

## Context and Problem Statement

The cluster previously used `ingress-nginx` (chart 4.12.0, IngressClass `nginx-internal`) as
the HTTP ingress controller for four apps: Grafana, Langfuse, Longhorn UI, and Pi-hole. Cilium
1.17.x is already deployed as the CNI, kube-proxy replacement, and L2 LoadBalancer (see
ADR-0002 and ADR-0003). Running a separate nginx controller alongside Cilium duplicates the data
path without adding capability. The upstream Ingress API is feature-frozen; the Gateway API is
its typed, role-oriented successor with richer routing semantics.

See [issue #54](https://github.com/melvinlee/k8s-homelab/issues/54).

## Decision Drivers

* Reduce moving parts — Cilium already owns the L2/LoadBalancer stack; folding ingress into it
  removes the separate nginx Deployment, Service, IngressClass, and ServiceMonitor.
* Gateway API is the upstream successor to the Ingress API, offering typed routing
  (HTTPRoute, GRPCRoute) without nginx-specific annotation soup.
* None of the existing Ingress objects used `nginx.ingress.kubernetes.io/*` annotations, so
  there is nothing to translate — a clean cutover.

## Considered Options

* **Keep ingress-nginx** — no migration cost, but continues to run a redundant data-path
  component alongside Cilium.
* **Migrate to Cilium Gateway API** (chosen) — enables Cilium's built-in Gateway controller,
  installs upstream Gateway API CRDs, and replaces all Ingress objects with HTTPRoutes.
* **Migrate to another Gateway controller (e.g., Envoy Gateway)** — adds yet another component;
  no benefit over using what Cilium already ships.

## Decision Outcome

Chosen option: **Migrate to Cilium Gateway API**, because it consolidates ingress into the CNI
we already run, eliminates a standalone controller, and positions the cluster on the
upstream-standard routing API.

### Implementation

* Gateway API standard-channel CRDs (v1.2.0) are installed via a `presync` hook on the Cilium
  helmfile release (`releases/cilium/gateway-crds.sh`).
* `gatewayAPI.enabled: true` is added to `releases/cilium/values.yaml`; Cilium registers the
  `cilium` GatewayClass automatically on startup.
* A single `Gateway` object (`homelab`, namespace `infra`, port 80, `allowedRoutes.from: All`)
  is applied by the Cilium `postsync` hook (`config.sh`) after the GatewayClass is `Accepted`.
  It receives a LoadBalancer IP from the existing Cilium L2 pool (ADR-0003).
* One `HTTPRoute` per app is stored in the app release's `resources/` directory and applied via
  a `postsync` hook on that release (mirroring the Cilium `config.sh` pattern from ADR-0001):
  | App | Namespace | Backend service | Port |
  |-----|-----------|-----------------|------|
  | Grafana | `monitoring` | `grafana` | 80 |
  | Langfuse | `langfuse` | `langfuse-web` | 3000 |
  | Longhorn UI | `longhorn-system` | `longhorn-frontend` | 80 |
  | Pi-hole | `infra` | `pihole-web` | 80 |
* `external-dns` sources updated from the implicit `ingress` default to
  `[service, gateway-httproute]`; `ingressClassFilters` removed.
* `ingress-nginx` release and its `releases/ingress-nginx/` directory removed from the repo;
  all `ingressClassName: nginx-internal` references removed from app values.
* The nginx-ingress Grafana dashboard (gnetId 9614) removed from `grafana/values.yaml`.

### Consequences

* Good — one fewer Deployment and LoadBalancer Service in the cluster; the data path is fully
  owned by Cilium.
* Good — HTTPRoutes are typed Kubernetes objects with status conditions (`Accepted`,
  `Programmed`), making route health directly observable via `kubectl get httproute -A`.
* Good — `allowedRoutes.from: All` on the Gateway lets each app namespace own its HTTPRoute
  without requiring a ReferenceGrant for the parent reference.
* Bad — Gateway API CRDs are not bundled in Cilium's Helm chart and must be installed
  separately (handled by the `presync` hook); an internet connection is required at deploy time
  to fetch `standard-install.yaml` from the upstream GitHub release.
* Neutral — Pi-hole's `serviceWeb` remains type `LoadBalancer` (direct access at
  `192.168.1.250:80`) in addition to the hostname route via `pihole.home`; both coexist.

## More Information

* Supersedes / relates to: [ADR-0003](0003-loadbalancer-via-cilium-l2.md) (LoadBalancer via
  Cilium L2 — the Gateway uses the same IP pool).
* Relates to: [ADR-0001](0001-adopt-gitops-with-helmfile.md) (per-release resources/ +
  postsync-hook pattern used for Gateway and HTTPRoutes).
* Cilium Gateway API docs: <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>
* Kubernetes Gateway API: <https://gateway-api.sigs.k8s.io/>
