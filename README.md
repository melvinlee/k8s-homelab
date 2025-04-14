<div align="center">

<img src="https://raw.githubusercontent.com/melvinlee/k8s-homelab/main/docs/assets/logo.png" align="center" width="300" height="100" alt="K8s Homelab Logo"/>

<!-- markdownlint-disable no-trailing-punctuation -->

### My homelab operations repository using k8s, gitops and ci/cd :octocat:

</div>

## Hardware
My HomeLab consists of a bunch of bare-metal machines (Beelink Mini PC).

## Kubernetes
The cluster is based on [Talos](https://www.talos.dev) with 1 control-plane node and 2 worker nodes.


## Proposed Project Repository Structure

```plaintext
k8s-homelab/
├── talos/                 # Talos cluster configuration
│   ├── clusters/
│   │   └── homelab/       # Primary cluster configs
│   │       ├── controlplane/
│   │       │   ├── node1.yaml
│   │       │   └── node2.yaml
│   │       ├── workers/
│   │       │   ├── worker1.yaml
│   │       │   └── worker2.yaml
│   │       ├── patches/    # JSON6902 patches
│   │       │   ├── kernel-params.yaml
│   │       │   └── upgrade-1.5.0.yaml
│   │       └── secrets/    # Encrypted secrets
│   │           ├── encryption-secret.enc.yaml
│   │           └── bootstrap-token.enc.yaml
│   └── templates/         # Reusable configuration snippets
│       ├── network-templates/
│       └── storage-templates/
|
├── helmfile/               # Helmfile configuration root
│   ├── releases/           # Individual service deployments
│   │   ├── longhorn/       # Longhorn storage configuration
│   │   │   ├── values.yaml
│   │   │   └── helmfile.yaml
│   │   ├── metallb/
│   │   │   ├── values.yaml
│   │   │   └── helmfile.yaml
│   │   └── ingress-nginx/
│   ├── environments/       # Cluster environment configs
│   │   └── production/
│   │       ├── values.yaml
│   │       └── secrets.yaml
│   └── helmfile.yaml       # Root helmfile config
│
├── base/                   # Raw Kubernetes manifests
│   ├── namespaces/
│   ├── network-policies/
│   └── storage-classes/
│
├── docs/                   # Existing documentation
│   ├── networking.md
│   ├── infrastructure.md
│   └── assets/
│
├── scripts/                # Maintenance scripts
│   ├── talos-upgrade.sh
│   └── backup-longhorn.sh
│
├── monitoring/             # Prometheus stack configs
│   ├── dashboards/
│   ├── alerts/
│   └── service-monitors/
│
├── .github/                # CI/CD workflows
│   └── workflows/
│       └── helmfile-sync.yaml
│
├── sops/                   # Encrypted secrets
│   └── cluster-secrets.enc.yaml
│
└── policies/               # Kyverno/OPA policies
    ├── network-policies/
    └── security-policies/
```