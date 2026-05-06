# Vendure Helm Environments

This directory contains environment-specific configurations for deploying Vendure on EKS.

## Directory Structure

```
environments/
├── README.md                          # This file
├── test/                              # Test/Staging environment
│   ├── vendure-values.yaml            # Vendure Helm values
│   ├── monitoring-values.yaml         # Prometheus/Grafana values
│   ├── eks-nodegroups.yaml            # EKS node group config
│   └── deploy.sh                      # Deployment script
│
└── production/                        # Production environment
    ├── vendure-values.yaml            # Vendure Helm values
    ├── monitoring-values.yaml         # Prometheus/Grafana values
    └── eks-nodegroups.yaml            # EKS node group config
```

## Environment Comparison

| Aspect | Test | Production |
|--------|------|------------|
| **Node Strategy** | All SPOT (single node) | Hybrid (ON-DEMAND monitoring + SPOT app) |
| **Vendure Replicas** | 1 | 2+ (with HPA) |
| **Prometheus Retention** | 7 days | 30 days |
| **Alert Severity** | Warning | Critical |
| **Network Policies** | Disabled | Enabled |
| **Estimated Cost** | ~$105/month | ~$130/month |

## Architecture Overview

### Test Environment
```
┌─────────────────────────────────────────────┐
│           SINGLE SPOT NODE                  │
│           (t3a.medium)                      │
│                                             │
│  ┌─────────────────┐  ┌─────────────────┐  │
│  │ Vendure Server  │  │   Prometheus    │  │
│  │ (1 replica)     │  │   Grafana       │  │
│  │                 │  │   AlertManager  │  │
│  └─────────────────┘  └─────────────────┘  │
│                                             │
│  Cost: ~$8-12/month (spot)                  │
└─────────────────────────────────────────────┘
```

### Production Environment
```
┌──────────────────────┐  ┌──────────────────────┐
│  ON-DEMAND NODE      │  │    SPOT NODE(S)      │
│  (t3.small)          │  │    (t3a.medium)      │
│                      │  │                      │
│  ┌────────────────┐  │  │  ┌────────────────┐  │
│  │ Prometheus     │  │  │  │ Vendure Server │  │
│  │ Grafana        │  │  │  │ (2+ replicas)  │  │
│  │ AlertManager   │  │  │  │                │  │
│  └────────────────┘  │  │  └────────────────┘  │
│                      │  │                      │
│  Cost: ~$15/month    │  │  Cost: ~$8-16/month  │
└──────────────────────┘  └──────────────────────┘
```

## Quick Start - Test Environment

### 1. Deploy EKS Node Groups (if not exists)
```bash
# Create the spot node group for test
eksctl create nodegroup -f helm/environments/test/eks-nodegroups.yaml
```

### 2. Run Deployment Script
```bash
# Full deployment
./helm/environments/test/deploy.sh

# Dry-run first (recommended)
./helm/environments/test/deploy.sh --dry-run

# Deploy only monitoring
./helm/environments/test/deploy.sh --monitoring-only

# Deploy only Vendure
./helm/environments/test/deploy.sh --vendure-only
```

### 3. Access Services
```bash
# Grafana
kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80

# Prometheus
kubectl port-forward svc/prometheus-stack-kube-prom-prometheus -n monitoring 9090:9090

# Vendure Admin
kubectl port-forward svc/vendure -n vendure-test 3002:3002
```

## Manual Deployment Steps

### Step 1: Create Namespaces
```bash
kubectl create namespace vendure-test
kubectl create namespace monitoring
```

### Step 2: Create Secrets
```bash
kubectl create secret generic vendure-secrets \
  --namespace vendure-test \
  --from-literal=DB_USERNAME=admin \
  --from-literal=DB_PASSWORD=<YOUR_RDS_PASSWORD> \
  --from-literal=REDIS_USERNAME=default \
  --from-literal=REDIS_PASSWORD=<YOUR_REDIS_PASSWORD> \
  --from-literal=COOKIE_SECRET=$(openssl rand -base64 32) \
  --from-literal=SUPERADMIN_PASSWORD=<YOUR_ADMIN_PASSWORD> \
  --from-literal=AWS_ACCESS_KEY_ID=<YOUR_AWS_KEY> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<YOUR_AWS_SECRET> \
  --from-literal=AWS_REGION=ap-south-1 \
  --from-literal=S3_BUCKET=cdn.kaaikani.co.in
```

### Step 3: Deploy Monitoring Stack
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f helm/environments/test/monitoring-values.yaml \
  --set grafana.adminPassword=<YOUR_GRAFANA_PASSWORD>
```

### Step 4: Deploy Vendure
```bash
helm install vendure ./helm/vendure-stack \
  -n vendure-test \
  -f helm/environments/test/vendure-values.yaml
```

## Upgrading Deployments

### Upgrade Vendure
```bash
helm upgrade vendure ./helm/vendure-stack \
  -n vendure-test \
  -f helm/environments/test/vendure-values.yaml
```

### Upgrade Monitoring
```bash
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f helm/environments/test/monitoring-values.yaml
```

## Troubleshooting

### View Logs
```bash
# Vendure logs
kubectl logs -f deployment/vendure -n vendure-test

# Prometheus logs
kubectl logs -f prometheus-prometheus-stack-kube-prom-prometheus-0 -n monitoring

# Grafana logs
kubectl logs -f deployment/prometheus-stack-grafana -n monitoring
```

### Check Pod Status
```bash
kubectl get pods -n vendure-test
kubectl get pods -n monitoring
kubectl describe pod <pod-name> -n <namespace>
```

### Check Events
```bash
kubectl get events -n vendure-test --sort-by='.lastTimestamp'
```

### Restart Deployments
```bash
kubectl rollout restart deployment/vendure -n vendure-test
```

## Cost Optimization Tips

1. **Use Spot Instances** - 70-90% cheaper than on-demand
2. **Right-size Resources** - Monitor actual usage and adjust
3. **Reduce Prometheus Retention** - 7 days is usually enough for test
4. **Disable Unused Components** - kubeApiServer, kubeEtcd, etc.
5. **Use gp3 Storage** - Cheaper than gp2 for same performance

## Security Notes

- Test environment has network policies **disabled** for easier debugging
- Production environment should have network policies **enabled**
- Always use separate databases for test and production
- Rotate secrets regularly
- Use IRSA (IAM Roles for Service Accounts) for AWS access in production
