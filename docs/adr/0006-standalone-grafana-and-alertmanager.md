---
status: "accepted"
date: 2026-06-14
---

# 0006. Run standalone Grafana and Alertmanager alongside kube-prometheus-stack

## Context and Problem Statement

`kube-prometheus-stack` bundles Grafana and Alertmanager, but we want to manage
Grafana's lifecycle and credentials independently while still using the curated
dashboards the bundle ships. How should the observability stack be composed?

## Decision Drivers

* Independent lifecycle and secret management for Grafana
* Keep the bundle's curated dashboards
* Avoid two competing Grafana instances

## Considered Options

* Use the bundled Grafana and Alertmanager
* Disable the bundled ones and run standalone Grafana + a separate Alertmanager

## Decision Outcome

Chosen option: "standalone", because it decouples Grafana's lifecycle and
credentials from the Prometheus chart. `kube-prometheus-stack` is deployed with
its bundled Grafana and Alertmanager **disabled**; a standalone `grafana` release
runs instead. The bundle's `forceDeployDashboards: true` still pushes dashboard
ConfigMaps, which the standalone Grafana sidecar discovers via the
`grafana_dashboard: "1"` label.

### Consequences

* Good, because Grafana credentials and upgrades are managed on their own
* Bad, because dashboard delivery relies on the sidecar label convention staying
  in sync between the two releases

## More Information

See the "Monitoring stack architecture" note in `CLAUDE.md` and PR #34.
