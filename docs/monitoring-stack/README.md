# Monitoring Stack for Vendure Production

This folder contains the configuration for deploying **kube-prometheus-stack** separately from the Vendure application.

## Architecture

```
Namespace: vendure-production          Namespace: monitoring
┌─────────────────────────┐           ┌─────────────────────────────────┐
│  Vendure App (3 pods)   │           │  kube-prometheus-stack          │
│  ├── ServiceMonitor ────┼──────────►│  ├── Prometheus (scrapes)       │
│  └── PrometheusRule ────┼──────────►│  ├── Grafana (dashboards)       │
│                         │           │  ├── Alertmanager (alerts)      │
│  Connects to:           │           │  ├── Node Exporter              │
│  ├── RDS MySQL          │           │  └── Kube State Metrics         │
│  └── Redis Cloud        │           │                                 │
└─────────────────────────┘           └─────────────────────────────────┘
```

## Why Separate?

| Benefit | Description |
|---------|-------------|
| **Failure Isolation** | If Vendure crashes, monitoring stays up to observe the failure |
| **Independent Lifecycle** | Update monitoring without touching the app, and vice versa |
| **Resource Isolation** | Dedicated resources for monitoring |
| **Multi-App Monitoring** | One monitoring stack can monitor multiple applications |

## Deployment Steps

### 1. Add Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 2. Create Namespace

```bash
kubectl create namespace monitoring
```

### 3. Install kube-prometheus-stack

```bash
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-production.yaml \
  --set grafana.adminPassword=<YOUR_GRAFANA_PASSWORD>
```

### 4. Verify Installation

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

## Accessing Services

### Grafana (Dashboards)

```bash
# Port forward
kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80

# Open browser
http://localhost:3000
# Login: admin / <YOUR_GRAFANA_PASSWORD>
```

### Prometheus (Metrics)

```bash
# Port forward
kubectl port-forward svc/prometheus-stack-kube-prom-prometheus -n monitoring 9090:9090

# Open browser
http://localhost:9090
```

### Alertmanager

```bash
# Port forward
kubectl port-forward svc/prometheus-stack-kube-prom-alertmanager -n monitoring 9093:9093

# Open browser
http://localhost:9093
```

## Upgrading

```bash
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-production.yaml
```

## Uninstalling

```bash
helm uninstall prometheus-stack -n monitoring
kubectl delete namespace monitoring
```

## Dashboard Folder Structure

Grafana dashboards are organized into folders via ConfigMap annotations:

```
Grafana Dashboards/
├── Kubernetes/
│   ├── Cluster Overview          — Nodes CPU/RAM/Disk, PVC, Network
│   └── Namespace Resources       — Per-namespace CPU/RAM/Disk/Network (dropdown)
│
├── Vendure/
│   ├── Application Full Overview — CPU, RAM, Disk, Requests, Bandwidth, Node.js runtime
│   ├── API Traffic & Performance — Request rates, status codes, latency percentiles
│   ├── Load Test Dashboard       — Incoming requests, throughput, latency breakdown
│   ├── Soak Test Dashboard       — Memory leaks, connection pool, GC pressure
│   └── Spike Test Dashboard      — Autoscaling reaction, error bursts, recovery
│
├── Storefronts/
│   ├── Website Overview          — Per-site (dropdown: kaaikanistore/southmithai/swadkerala)
│   │                               CPU, RAM, Disk, Bandwidth, Visitors, Requests
│   └── Storefront Application    — Detailed USE method metrics for storefronts
│
└── Cloudflare/
    └── Analytics - All Websites  — Total/Cached/Uncached Bandwidth, Unique Visitors,
                                    HTTP status, Threats, Cache hit ratio per zone
```

### Deploying Dashboards

Dashboards are provisioned automatically via Grafana sidecar from ConfigMaps with label `grafana_dashboard: "1"`.

```bash
# Apply dashboard ConfigMaps
kubectl apply -f dashboard-configmaps.yaml -n monitoring

# Apply existing traffic dashboard
kubectl apply -f vendure-traffic-dashboard.yaml -n monitoring
kubectl apply -f storefront-dashboard-configmap.yaml -n monitoring
```

### Cloudflare Exporter (Required for CDN metrics)

The Cloudflare dashboards require the cloudflare-exporter. See `cloudflare-exporter.yaml`.

```bash
# 1. Create Cloudflare API token with "Zone.Analytics:Read" permission
# 2. Create secret
kubectl create secret generic cloudflare-api-token \
  -n monitoring \
  --from-literal=api-token=<YOUR_CF_API_TOKEN>

# 3. Edit cloudflare-exporter.yaml and set your CF_ZONES (comma-separated zone IDs)
# 4. Deploy
kubectl apply -f cloudflare-exporter.yaml -n monitoring
```

## Custom Vendure Alerts

The following alerts are pre-configured for Vendure:

| Alert | Condition | Severity |
|-------|-----------|----------|
| VendureHighErrorRate | Error rate > 10% for 5 min | Critical |
| VendurePodNotReady | Pod not ready for 5 min | Warning |
| VendureHighMemoryUsage | Memory > 90% for 5 min | Warning |
| VendureHighCPUUsage | CPU > 90% for 5 min | Warning |

## Adding Notification Channels

Edit the `alertmanager.config` section in `values-production.yaml` to add:

### Slack

```yaml
receivers:
  - name: 'slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/...'
        channel: '#alerts'
```

### Email

```yaml
receivers:
  - name: 'email'
    email_configs:
      - to: 'alerts@yourdomain.com'
        from: 'prometheus@yourdomain.com'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'your-email@gmail.com'
        auth_password: 'your-app-password'
```
