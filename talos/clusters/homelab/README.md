# Bootstrapping Talos Control Plane

This guide outlines the steps to bootstrap a Talos control plane node with IP `192.168.1.51`.

## Step 1: Generate Talos Configuration

1. Generate the base configuration:
```bash
# Generate the configuration files directly in the project structure
talosctl gen config k8s-homelab https://$CONTROL_PLANE_IP:6443 \
    --output-dir . \
    --endpoints=$CONTROL_PLANE_IP \
    --with-docs=false \
    --with-examples=false \
    --install-disk=/dev/nvme0n1
```

2. Apply configuration patches:
```bash
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
    --nodes $CONTROL_PLANE_IP \
    --file talos/clusters/homelab/controlplane/node1.yaml
```

## Step 3: Bootstrap the Cluster

```bash
# Configure the endpoints
talosctl config endpoint $CONTROL_PLANE_IP
talosctl config node $CONTROL_PLANE_IP

# Export talos config, For example 
# TALOSCONFIG="_out/talosconfig"

# Bootstrap the cluster
talosctl bootstrap

# Wait for the node to be ready
talosctl health
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
talosctl services

# Check running containers
talosctl containers

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
