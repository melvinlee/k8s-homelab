# Manage Talos Linux Configuration with GitOps

Talos Linux is already declarative by design. Every aspect of the operating system is defined in a machine configuration file. By applying GitOps principles to your Talos Linux configuration, you get version control, change tracking, peer review, and automated rollouts. This guide shows you how to manage your entire Talos Linux cluster configuration through Git.

```
talos/
├── patches/
│   ├── cp-01.yaml             # Control plane: hostname, CNI=none + proxy disabled (Cilium), PodSecurity, Longhorn mounts
│   ├── worker-01.yaml         # Worker hostname + Longhorn mounts
│   └── worker-02.yaml
└── secrets.yaml               # encrypted with SOPS/age
```

## Step 1: Generate and Store Base Configuration

Generate secrets separately from the machine configuration so they can be stored securely.
```
# Generate cluster secrets
talosctl gen secrets --output-file secrets.yaml
```

## Step 2: Generate Talos Configuration

Generate the base configuration:
```
# Generate the configuration files directly in the project structure
talosctl gen config homelab https://$CONTROL_PLANE_IP:6443 \
    --with-docs=false \
    --with-examples=false \
    --with-secrets secrets.yaml \
    --output-dir configs/
```

## Step 3: Apply Configuration to Control Plane

1. Apply the configuration:

```bash
# Apply the machineconfig to the control-plane node (cp-01.yaml carries the
# Cilium CNI=none + kube-proxy disabled settings)
talosctl apply-config \
    --nodes $CONTROL_PLANE_IP \
    --file configs/controlplane.yaml \
    --config-patch @patches/cp-01.yaml \
    --insecure
```

## Step 3: Bootstrap the Cluster

```bash
# Configure the endpoints
CONTROL_PLANE_IP=192.168.1.50
talosctl config endpoint $CONTROL_PLANE_IP
talosctl config node $CONTROL_PLANE_IP

# Export talos config, For example 
export TALOSCONFIG="configs/talosconfig"

# Bootstrap the cluster
talosctl bootstrap

# Wait for the node to be ready
talosctl health 
```

## Step 4: Configure kubectl

```bash
# Get the kubeconfig
talosctl kubeconfig --nodes $CONTROL_PLANE_IP -f

# Verify cluster status
kubectl get nodes
```

## Step 5: Join Worker Nodes to Cluster

After setting up your control plane, use the following steps to add worker nodes:

1. Prepare the worker configuration:

2. Apply worker configuration:
```bash
# Set the worker node IP
export WORKER_IP1=192.168.1.54
export WORKER_IP2=192.168.1.55

# Apply the worker configuration
talosctl apply-config \
    --nodes $WORKER_IP1 \
    --file configs/worker.yaml \
    --config-patch @patches/worker-01.yaml \
    --insecure 

talosctl apply-config \
    --nodes $WORKER_IP2 \
    --file configs/worker.yaml \
    --config-patch @patches/worker-02.yaml \
    --insecure 
```

4. Verify the worker node joined successfully:
```bash
# Check if the node appears in the cluster
kubectl get nodes

# Verify the node is in Ready state
kubectl get nodes -o wide
```

5. For multiple worker nodes, repeat steps 1-4 with different node configurations and IPs.

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
talosctl dmesg --nodes $CONTROL_PLANE_IP
```

2. View service logs:
```bash
talosctl logs --nodes $CONTROL_PLANE_IP kubelet
```

3. Reboot server
```bash
talosctl reboot --nodes $CONTROL_PLANE_IP

talosctl reboot --nodes $WORKER_IP1

# To watch the node come back up:
talosctl dmesg --nodes $CONTROL_PLANE_IP --follow
```

4. Common issues:
   - Ensure firewall allows required ports (6443, 50000, etc.)
   - Verify network connectivity
   - Check system requirements are met
   - For worker join issues, verify the API server endpoint is accessible from the worker
   - Ensure worker node has valid machine configuration with proper cluster join information
