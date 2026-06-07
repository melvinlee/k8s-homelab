<div align="center">

<img src="https://raw.githubusercontent.com/melvinlee/k8s-homelab/main/docs/assets/logo.png" align="center" width="450" height="100" alt="K8s Homelab Logo"/>

<br/>

[![Talos Linux](https://img.shields.io/badge/Talos_Linux-FF7300?style=flat-square&logo=linux&logoColor=white)](https://www.talos.dev)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Argo CD](https://img.shields.io/badge/Argo_CD-EF7B4D?style=flat-square&logo=argo&logoColor=white)](https://argo-cd.readthedocs.io)
[![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat-square&logo=helm&logoColor=white)](https://helm.sh)
[![License](https://img.shields.io/github/license/melvinlee/k8s-homelab?style=flat-square)](LICENSE)

<!-- markdownlint-disable no-trailing-punctuation -->

### My homelab operations repository using k8s, gitops and ci/cd :octocat:

</div>

## Objective 

This homelab project aims to create a robust, maintainable, and scalable Kubernetes environment based on the following principles:

- **Immutability**: Infrastructure is treated as immutable, with changes requiring new deployments rather than modifications to existing resources
- **Minimalism**: Focused on essential components to reduce complexity and resource overhead
- **API-driven Control**: All system interactions are performed through well-defined APIs, avoiding direct system manipulation

Key operational approaches:

- **Declarative Configuration**: Simplifying and automating Kubernetes deployments using Helm charts through structured, declarative configuration files
- **GitOps Workflow**: Using Git repositories as the single source of truth for infrastructure and application configurations, enabling automated deployments, versioning, and rollbacks
- **Infrastructure as Code**: Managing all infrastructure components through code to ensure consistency and repeatability

## Kubernetes

The cluster is based on [Talos Linux](https://www.talos.dev) with 1 control-plane node and 2 worker nodes.

## Technologies and Tools

- `Talos Linux`: modern Kubernetes operating system designed specifically for running Kubernetes
- `helmfile`: a declarative specification for deploying Helm charts
- `Longhorn`: cloud-native, distributed block storage system designed for Kubernetes
- `Cilium`: eBPF-based CNI providing kube-proxy replacement and bare-metal LoadBalancer via L2 announcements
- `external-dns`: synchronizes exposed Kubernetes Services and Ingresses with DNS providers (pi-hole) 
- `Argo CD`: a declarative, GitOps continuous delivery tool for Kubernetes

## Hardware (Bare Metal)

My HomeLab consists of a bunch of bare-metal machines (Beelink Mini PC).

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
│   │   ├── cilium/
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