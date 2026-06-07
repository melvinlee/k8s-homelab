---
name: helmfile-deploy
description: This skill provides comprehensive guidelines for deploying Helm charts in Kubernetes environments following industry best practices. It emphasizes the mandatory use of override values files for all deployments to ensure proper customization, security hardening, and maintainability. Never deploy Helm charts using default values in production environments.
---

## Use Cases

- Deploying new Helm charts to development, staging, or production Kubernetes clusters
- Upgrading existing Helm releases with configuration changes
- Ensuring consistent and secure deployment practices across multiple environments
- Customizing third-party or internal Helm charts for specific organizational requirements
- Implementing Infrastructure as Code (IaC) for Kubernetes applications

## Workflow

### 1. Prepare Override Values File
- Create a dedicated `values.yaml` file for each environment (dev, staging, prod)
- Override ALL default values that need customization, including:
  - Image tags and registries
  - Resource requests and limits
  - Security contexts and pod security standards
  - Service configurations and ingress settings
  - Environment-specific variables and secrets
- Use YAML anchors and aliases for reusable configurations
- Validate values against the chart's schema if available

### 2. Validate Chart and Configuration
- Run `helm lint <chart-directory>` to check for common issues
- Use `helm template <release-name> <chart> --values values.yaml --dry-run` to validate rendering
- Check for deprecated APIs using `helm template` with `--validate`
- Verify namespace existence and permissions

### 3. Deploy with Override Values
- Use `helm install <release-name> <chart> --values values.yaml --namespace <namespace> --create-namespace --wait --timeout 600s`
- For upgrades: `helm upgrade <release-name> <chart> --values values.yaml --namespace <namespace> --wait --timeout 600s`
- Always specify `--values` flag pointing to your override file
- Use `--atomic` for rollback on failure in production
- Implement proper release naming conventions

### 4. Verify and Test Deployment
- Check pod status: `kubectl get pods -n <namespace>`
- Validate services and endpoints: `kubectl get svc,ep -n <namespace>`
- Review logs: `kubectl logs -n <namespace> <pod-name>`
- Run helm tests if available: `helm test <release-name>`
- Perform smoke tests for application functionality

### 5. Document and Maintain
- Store values files in version control with the application code
- Document deployment procedures and rollback steps
- Use Helm release metadata for tracking: `helm get metadata <release-name>`
- Implement monitoring and alerting for deployed applications
- Plan for regular updates and security patches

## Best Practices

### Security
- Always set security contexts for pods and containers
- Use non-root users where possible
- Implement network policies
- Store secrets separately using external secret management
- Enable Pod Security Standards

### Resource Management
- Set appropriate CPU and memory requests/limits
- Use Horizontal Pod Autoscaling (HPA) for scalable workloads
- Implement resource quotas at namespace level
- Monitor resource usage post-deployment

### Reliability
- Use readiness and liveness probes
- Implement proper rolling update strategies
- Configure anti-affinity rules for high availability
- Set up proper logging and monitoring

### Maintainability
- Use semantic versioning for charts and applications
- Implement CI/CD pipelines for automated deployments
- Document all configuration changes
- Regular backup and disaster recovery testing

## Tools and Commands

### Core Helm Commands
```bash
# Install with overrides
helm install my-release ./mychart --values values.yaml --namespace my-namespace

# Upgrade with overrides
helm upgrade my-release ./mychart --values values.yaml --namespace my-namespace

# Template validation
helm template my-release ./mychart --values values.yaml

# Lint chart
helm lint ./mychart

# Check release status
helm status my-release
```

### Validation and Testing
```bash
# Dry run installation
helm install my-release ./mychart --values values.yaml --dry-run

# Test release
helm test my-release

# Get release values
helm get values my-release
```

## Common Pitfalls

- **Using default values**: Always provide override values for production deployments
- **Missing resource limits**: Can lead to cluster resource exhaustion
- **Inadequate security**: Not setting security contexts or using privileged containers
- **No validation**: Deploying without testing chart rendering
- **Improper rollback planning**: Not having atomic deployments or backup strategies
- **Ignoring dependencies**: Not managing chart dependencies properly

## Prerequisites

- Kubernetes cluster access with appropriate RBAC permissions
- Helm CLI installed (version 3.x recommended)
- kubectl configured for cluster access
- Understanding of Kubernetes concepts (pods, services, deployments)
- Version control system for storing configurations

## Related Skills

- kubernetes-cluster-setup
- helm-chart-development
- secret-management
- monitoring-and-logging
- ci-cd-pipelines

## Examples

### Basic Deployment
```bash
# Create values override file
cat > values.yaml << EOF
image:
  tag: "1.2.3"
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
EOF

# Deploy
helm install my-app ./charts/my-app --values values.yaml --namespace production
```

### Production Deployment with Best Practices
```bash
# values.yaml includes security contexts, resource limits, etc.
helm upgrade --install my-app ./charts/my-app \
  --values values-prod.yaml \
  --namespace production \
  --create-namespace \
  --wait \
  --timeout 600s \
  --atomic
```