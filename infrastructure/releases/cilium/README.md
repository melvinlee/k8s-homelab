# Cilium

CNI + kube-proxy replacement + bare-metal LoadBalancer (L2 announcements).
Replaces Talos' default Flannel/kube-proxy and the former MetalLB release.

## Layout

| File | Purpose |
| ---- | ------- |
| `helmfile.yaml` | Cilium release (chart `1.17.1`, namespace `kube-system`) + `postsync` hook |
| `values.yaml` | `kubeProxyReplacement`, KubePrism `localhost:7445`, `ipam.mode: kubernetes`, Talos cgroup/caps, L2 announcements |
| `config.sh` | postsync hook — waits for the Cilium CRDs/operator, then applies `resources/loadbalancer.yaml` |
| `resources/loadbalancer.yaml` | `CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy` (`cilium.io/v2alpha1`), pool `192.168.1.200-250` |

Cilium depends on Talos having `cni: none` + `proxy.disabled: true` — set in
`talos/patches/cp-01.yaml` (cluster-bootstrap settings, applied from the control
plane only). See the repo `CLAUDE.md` for the migration runbook (issue #22).

## ⚠️ Gotcha: the L2 interface selector must match the node NICs

`CiliumL2AnnouncementPolicy.spec.interfaces` is a list of **regexes matched
against interface names**. If it matches nothing, Cilium still assigns
LoadBalancer IPs but never ARP-announces them — so every LB IP (ingress `.200`,
Pi-hole `.250`) becomes unreachable and DNS breaks cluster-wide. The symptom is
sneaky: `kubectl get svc` shows the `EXTERNAL-IP` assigned and healthy, but the
IP simply doesn't answer.

This hardware's NICs are **`enp1s0`** (cp-01) / **`enp2s0`** (workers), *not*
`eth0`. The committed policy therefore selects:

```yaml
interfaces:
  - ^enp[0-9]+s[0-9]+$
  - ^eth[0-9]+$        # predictable-name fallback
```

If you add a node with a differently-named NIC, update this selector.

### Verify

```bash
# Real NIC names per node
for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
  kubectl -n kube-system exec "$p" -c cilium-agent -- \
    sh -c "ip -o -4 addr show | grep 192.168.1. | awk '{print \$2}'"
done

# Selector currently in effect — must match the names above
kubectl get ciliuml2announcementpolicy pool -o jsonpath='{.spec.interfaces}{"\n"}'

# End-to-end: LB IP must answer its service port (ICMP ping is NOT a valid test —
# Cilium L2 IPs answer ARP + service ports but not ICMP echo)
nslookup grafana.home 192.168.1.250
```

## Apply

```bash
cd infrastructure
helmfile -l name=cilium apply
cilium status --wait          # requires cilium-cli
```

The `postsync` hook applies `resources/loadbalancer.yaml` automatically. To
reconcile just the LB pool/policy without re-running the chart:

```bash
kubectl apply -f releases/cilium/resources/loadbalancer.yaml
```
