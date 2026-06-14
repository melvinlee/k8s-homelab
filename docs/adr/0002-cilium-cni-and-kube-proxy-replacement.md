---
status: "accepted"
date: 2026-06-14
---

# 0002. Use Cilium as the CNI and kube-proxy replacement

## Context and Problem Statement

Talos ships with Flannel as the CNI and a standard `kube-proxy`. We want an eBPF
dataplane, native network policy, and a foundation for L2 LoadBalancer support,
none of which the default stack provides well. Which CNI and service-proxy should
the cluster run?

## Decision Drivers

* eBPF dataplane and native NetworkPolicy
* kube-proxy replacement (no iptables service routing)
* Foundation for bare-metal LoadBalancer (L2 announcements)

## Considered Options

* Keep Talos default Flannel + kube-proxy (+ MetalLB for LB)
* Calico
* Cilium as both CNI and kube-proxy replacement

## Decision Outcome

Chosen option: "Cilium", because it provides the CNI, the kube-proxy replacement,
and L2 LoadBalancer in one component. We set `cni.name: none` and disable
`kube-proxy` in `talos/patches/cp-01.yaml`, and run Cilium with
`kubeProxyReplacement: true`, reaching the API server via the Talos KubePrism
endpoint at `localhost:7445`.

### Consequences

* Good, because the cluster gets an eBPF dataplane with no kube-proxy iptables
* Good, because it enables Cilium L2 announcements (see
  [ADR-0003](0003-loadbalancer-via-cilium-l2.md))
* Bad, because networking cannot bootstrap without the cp-01 patch; CNI and
  kube-proxy must never be re-enabled and no second CNI installed
* Bad, because Cilium is now a hard dependency for all pod and service networking

## More Information

Supersedes the default Flannel + kube-proxy. See the "Talos CNI" note in
`CLAUDE.md` and `infrastructure/releases/cilium/README.md`.
