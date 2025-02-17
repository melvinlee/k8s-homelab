## Network Configuration

### Network Subnet
- Subnet: `192.168.1.0/24`
- Usable Range: `192.168.1.1 - 192.168.1.254`
- Subnet Mask: `255.255.255.0`

### IP Allocation
| Range                | Purpose               | Notes                    |
|---------------------|----------------------|--------------------------|
| 192.168.1.1        | Router/Gateway       | Network gateway         |
| 192.168.1.2-49     | Infrastructure       | Reserved for network    |
| 192.168.1.50-99    | Kubernetes Nodes     | Control plane & workers |
| 192.168.1.100-199  | DHCP Range          | Dynamic clients         |
| 192.168.1.200-250  | MetalLB Pool        | Kubernetes services     |

### Core Infrastructure IPs
- Router/Gateway: `192.168.1.1`
- Pi-hole DNS: `192.168.1.49`

### MetalLB Configuration
- IP Range: `192.168.1.200-192.168.1.250`
- Protocol: Layer 2 mode

### DNS Configuration
- External DNS Provider: Cloudflare `1.1.1.1`
- Domain: `homelab.local`

### Ingress Configuration
- Default Backend: `404-not-found`
- SSL Termination: Enabled
- Default TLS Certificate: LetsEncrypt
- HTTP Port: `80`
- HTTPS Port: `443`