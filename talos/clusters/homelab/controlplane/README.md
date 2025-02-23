# Bootstrapping Talos Control Plane

This guide outlines the steps to bootstrap a Talos control plane node with IP `192.168.1.51`.

## Step 1: Generate Talos Configuration

1. Generate the base configuration:
```bash
# Generate the configuration files directly in the project structure
talosctl gen config k8s-homelab https://192.168.1.51:6443 \
    --output-dir talos/clusters/homelab \
    --endpoints-192.168.1.51 \
    --with-docs=false \
    --with-examples=false \
    --install-disk=nvme0n1
```

2. Apply configuration patches:
```bash
# Run CLI to get disk information on where to install talos
talosctl get disk --nodes 192.168.1.51 --insecure

# Move the generated controlplane config to the correct location
mv talos/clusters/homelab/controlplane.yaml talos/clusters/homelab/controlplane/node1.yaml
```


## Step 2: Apply Configuration to Node

1. Boot your machine with the Talos ISO
2. Apply the configuration:

```bash
# Apply the machineconfig to the node
talosctl apply-config \
    --insecure \
    --nodes 192.168.1.51 \
    --file talos/clusters/homelab/controlplane/node1.yaml
```

## Step 3: Bootstrap the Cluster

```bash
# Configure the endpoints
talosctl config endpoint 192.168.1.51

# Bootstrap the cluster
talosctl bootstrap --nodes 192.168.1.51

# Wait for the node to be ready
talosctl health --nodes 192.168.1.51
```

## Step 4: Configure kubectl

```bash
# Get the kubeconfig
talosctl kubeconfig --nodes 192.168.1.51 -f

# Verify cluster status
kubectl get nodes
```

## Verification

Your control plane node should now be running. Verify with:

```bash
# Check Talos services
talosctl services --nodes 192.168.1.51

# Check running containers
talosctl containers --nodes 192.168.1.51

# View cluster info
kubectl cluster-info

# Verify node is untainted and ready for workloads
kubectl describe node | grep Taints
```

## Troubleshooting

If you encounter issues:

1. Check node status:
```bash
talosctl dmesg --nodes 192.168.1.51
```

2. View service logs:
```bash
talosctl logs --nodes 192.168.1.51 kubelet
```

3. Common issues:
   - Ensure firewall allows required ports (6443, 50000, etc.)
   - Verify network connectivity
   - Check system requirements are met
