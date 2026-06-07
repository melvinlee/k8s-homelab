# Infrastructure

Helm releases for core cluster infrastructure, managed with [Helmfile](https://helmfile.readthedocs.io/).

## Structure

```text
infrastructure/
├── helmfile.yaml           # Root helmfile (repos, defaults, active releases)
├── environments/
│   └── production/
│       └── values.yaml     # Shared environment values
└── releases/               # One directory per Helm release
    ├── cilium/             # CNI + kube-proxy replacement + LoadBalancer (L2)
    ├── ingress-nginx/      # Ingress controller
    ├── pihole/             # Home DNS + ad-blocking
    ├── external-dns/       # Auto DNS records from Ingress
    └── longhorn/           # Distributed block storage
```

## Releases

| Release | Namespace | Chart | Version | Purpose |
| --- | --- | --- | --- | --- |
| cilium | `kube-system` | cilium/cilium | 1.17.1 | CNI + kube-proxy replacement + LoadBalancer L2, IP pool `192.168.1.200-250` |
| ingress-nginx-internal | `infra` | ingress-nginx/ingress-nginx | 4.12.0 | Internal ingress controller |
| pihole | `infra` | mojo2600/pihole | 2.18.0 | DNS server at `192.168.1.250` |
| externaldns-pihole | `infra` | bitnami/external-dns | 8.7.5 | Syncs Ingress hostnames to Pi-hole DNS |
| longhorn | `infra` | longhorn/longhorn | 1.6.2 | Distributed block storage |

## Usage

```bash
# Deploy all releases
helmfile apply

# Preview changes
helmfile diff

# Deploy a specific release
helmfile -l name=cilium apply
```

> Run commands from the `infrastructure/` directory so relative paths in helmfile.yaml resolve correctly.

## Pi-hole Web UI

**URL:** <http://pihole.home/admin> (requires Pi-hole DNS) or <http://192.168.1.250/admin> (direct IP)

**Retrieve the admin password:**

```bash
kubectl get secret -n infra pihole-secret -o jsonpath='{.data.password}' | base64 -d
```

**Reset the admin password:**

```bash
kubectl exec -n infra deployment/pihole -- pihole -a -p <new-password>
```
