---
status: "accepted"
date: 2026-06-14
---

# 0004. Exempt selected namespaces from PodSecurity admission

## Context and Problem Statement

PodSecurity admission is enforced cluster-wide, but core infrastructure (Cilium,
Longhorn, the ingress controller) needs privileged pods. How do we run privileged
infra without weakening PodSecurity everywhere?

## Decision Drivers

* Keep PodSecurity enforced by default for application workloads
* Allow specific privileged infrastructure to run
* Keep the exemption surface small and explicit

## Considered Options

* Disable PodSecurity admission globally
* Exempt specific namespaces + label privileged namespaces explicitly
* Try to run all infra as restricted (not feasible for CNI/CSI)

## Decision Outcome

Chosen option: "exempt specific namespaces", because it scopes the relaxation to
known infra. The `infra` namespace is exempted in the `cp-01.yaml`
`admissionControl` config; `kube-system` is exempt cluster-wide; privileged
namespaces such as `longhorn-system` carry `pod-security.kubernetes.io/*:
privileged` labels.

### Consequences

* Good, because privileged infra runs while PodSecurity stays enforced elsewhere
* Bad, because each exemption widens the attack surface — the list must be kept
  minimal, and new privileged namespaces must be added deliberately

## More Information

See the "PodSecurity exemptions" note in `CLAUDE.md`.
