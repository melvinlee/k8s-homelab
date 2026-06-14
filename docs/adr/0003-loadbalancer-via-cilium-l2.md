---
status: "accepted"
date: 2026-06-14
---

# 0003. Provide LoadBalancer IPs with Cilium L2 announcements

## Context and Problem Statement

A bare-metal cluster has no cloud LoadBalancer. We previously used MetalLB to
assign `LoadBalancer` IPs. Now that Cilium handles networking
([ADR-0002](0002-cilium-cni-and-kube-proxy-replacement.md)), running MetalLB as
well is redundant. How should `LoadBalancer` services get an IP?

## Decision Drivers

* Fewer moving parts to run and upgrade
* Integration with the existing Cilium dataplane
* Single L2 subnet (no BGP infrastructure at home)

## Considered Options

* MetalLB (L2 or BGP mode)
* Cilium L2 announcements
* Cilium BGP control plane

## Decision Outcome

Chosen option: "Cilium L2 announcements", because it removes a component while
reusing Cilium. A `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy`
(pool `192.168.1.200-250`) are applied by the cilium release's `postsync` hook
(`releases/cilium/config.sh`). The MetalLB release is removed.

### Consequences

* Good, because there is one fewer component and LB is integrated with Cilium
* Bad, because it requires the kube-proxy replacement to be enabled
* Bad, because it is L2-only (ARP, single subnet) with no BGP

## More Information

Supersedes MetalLB. See the "LoadBalancer" note in `CLAUDE.md`.
