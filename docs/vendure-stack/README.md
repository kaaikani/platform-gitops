# Vendure Stack Helm Chart

A comprehensive Helm chart for deploying the Vendure e-commerce platform with MySQL, Redis, and Prometheus monitoring.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner support (for persistence)

## Installation

### Quick Start (Local/Minikube)

```bash
# Add Bitnami repo for dependencies
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Build dependencies
cd helm/vendure-stack
helm dependency build

# Install with local values
helm install vendure . -f values-local.yaml -n vendure-local --create-namespace
```

### Production Installation

```bash
# Install with production values
helm install vendure . \
  -f values-production.yaml \
  -n production \
  --create-namespace \
  --set secrets.database.rootPassword=<ROOT_PASSWORD> \
  --set secrets.database.password=<DB_PASSWORD> \
  --set secrets.vendure.cookieSecret=<COOKIE_SECRET> \
  --set secrets.vendure.superadminPassword=<ADMIN_PASSWORD>
```

## Configuration

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vendure.replicaCount` | Number of Vendure replicas | `1` |
| `vendure.image.repository` | Vendure image repository | `vendure-local` |
| `vendure.image.tag` | Vendure image tag | `latest` |
| `vendure.resources.requests.memory` | Memory request | `512Mi` |
| `vendure.resources.limits.memory` | Memory limit | `1Gi` |
| `vendure.service.type` | Service type | `NodePort` |
| `mysql.enabled` | Enable MySQL | `true` |
| `redis.enabled` | Enable Redis | `true` |
| `prometheus.enabled` | Enable Prometheus | `true` |
| `grafana.enabled` | Enable Grafana | `false` |
| `ingress.enabled` | Enable Ingress | `false` |

### Environment-Specific Values

- `values-local.yaml` - Local development (Minikube)
- `values-production.yaml` - Production deployment

## Upgrading

```bash
helm upgrade vendure . -f values-local.yaml -n vendure-local
```

## Uninstalling

```bash
helm uninstall vendure -n vendure-local
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Ingress                              │
└─────────────────────────────┬───────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                      Vendure Service                         │
│                    (Port 8001, 3002)                         │
└─────────────────────────────┬───────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                    Vendure Deployment                        │
│                  (HPA, PDB enabled)                          │
└──────────┬──────────────────────────────────┬───────────────┘
           │                                  │
┌──────────▼──────────┐          ┌───────────▼────────────────┐
│       MySQL         │          │          Redis              │
│   (Primary/Replica) │          │      (Master/Replica)       │
└─────────────────────┘          └────────────────────────────┘
           │                                  │
┌──────────▼──────────────────────────────────▼───────────────┐
│                       Prometheus                             │
│            (ServiceMonitor, PrometheusRules)                 │
└─────────────────────────────┬───────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                        Grafana                               │
│                    (Dashboards)                              │
└─────────────────────────────────────────────────────────────┘
```

## Monitoring

The chart includes:
- ServiceMonitor for Vendure metrics scraping
- PrometheusRules for alerting
- Pre-configured Grafana datasources

### Access Prometheus (Local)

```bash
# Get Minikube IP
minikube ip

# Access at http://<MINIKUBE_IP>:30090
```

### Access Grafana (if enabled)

```bash
# Access at http://<MINIKUBE_IP>:30091
# Default credentials: admin/admin123
```

## Security

For production:
1. Use external secrets management (Vault, AWS Secrets Manager)
2. Enable network policies
3. Enable TLS for ingress
4. Change all default passwords
5. Use non-root containers

## Troubleshooting

### Check pod status
```bash
kubectl get pods -n vendure-local
```

### View logs
```bash
kubectl logs -f deployment/vendure-vendure-stack-vendure -n vendure-local
```

### Restart deployment
```bash
kubectl rollout restart deployment/vendure-vendure-stack-vendure -n vendure-local
```
