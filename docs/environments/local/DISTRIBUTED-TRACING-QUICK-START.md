# Distributed Tracing Quick Start - Local

## Overview

This guide helps you set up and test distributed tracing with Tempo in your local environment.

## Prerequisites

- Local Kubernetes cluster (Minikube, Docker Desktop, or Kind)
- kubectl configured to use local cluster
- Helm 3.x installed

## Quick Setup

### 1. Install Dependencies

```bash
# Install OpenTelemetry packages
npm install
```

### 2. Build Application

```bash
# Build with tracing enabled
npm run build
```

### 3. Deploy Monitoring Stack (Including Tempo)

```bash
# Switch to local cluster
kubectl config use-context minikube

# Deploy everything (Prometheus, Grafana, Loki, Tempo)
./helm/environments/local/setup-local-monitoring.sh
```

### 4. Verify Tempo is Running

```bash
# Check Tempo pod
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo

# Check Tempo logs
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo --tail=50
```

### 5. Access Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Login: admin / admin
```

### 6. Verify Tempo Datasource

1. Go to **Configuration** → **Data Sources**
2. Find **Tempo** datasource
3. Verify URL: `http://tempo:3200`
4. Click **Save & Test**

## Testing Tracing

### 1. Deploy Vendure (if not already deployed)

```bash
# Build and load image
docker build -t vendure-local:latest .
minikube image load vendure-local:latest

# Deploy Vendure
helm install vendure-local ./helm/vendure-stack \
  -n vendure-local \
  -f helm/environments/local/vendure-values.yaml
```

### 2. Make API Requests

```bash
# Port-forward Vendure
kubectl port-forward -n vendure-local svc/vendure-local 8001:8001

# Make some API calls
curl http://localhost:8001/shop-api
curl http://localhost:8001/admin-api
```

### 3. View Traces in Grafana

1. Go to **Explore** → Select **Tempo** datasource
2. Search for traces:
   - By service: `service.name=vendure-local`
   - By trace ID: (from logs)
   - By tags: `http.method=GET`
3. Click on a trace to see:
   - Timeline view
   - Span details
   - Related logs (if configured)
   - Related metrics (if configured)

## What Gets Traced

- ✅ HTTP requests (Express routes)
- ✅ Database queries (MySQL)
- ✅ External API calls
- ✅ Express middleware
- ✅ Plugin operations

## Troubleshooting

### No Traces Appearing

1. **Check Tempo is running:**
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
   ```

2. **Check Vendure logs for tracing errors:**
   ```bash
   kubectl logs -n vendure-local -l app.kubernetes.io/name=vendure | grep -i tracing
   ```

3. **Verify environment variables:**
   ```bash
   kubectl exec -n vendure-local -l app.kubernetes.io/name=vendure -- env | grep OTEL
   ```

4. **Check Tempo can receive traces:**
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=tempo | grep -i error
   ```

### Tempo Not Receiving Traces

1. **Verify endpoint URL:**
   - Should be: `http://tempo.monitoring.svc.cluster.local:4318/v1/traces`
   - Check in Vendure pod: `kubectl exec -n vendure-local <pod> -- env | grep OTEL`

2. **Check network connectivity:**
   ```bash
   kubectl exec -n vendure-local -l app.kubernetes.io/name=vendure -- \
     nc -zv tempo.monitoring.svc.cluster.local 4318
   ```

3. **Verify Tempo service:**
   ```bash
   kubectl get svc -n monitoring tempo
   ```

## Next Steps

Once local testing is successful:

1. **Deploy to Production:**
   - Use: `helm/environments/production/tempo-values.yaml`
   - Configure S3 storage for cost efficiency
   - Set up IRSA for S3 access

2. **Optimize Sampling:**
   - Production: 10% sampling (already configured)
   - Local: 100% sampling (for testing)

3. **Enable Trace-to-Logs Correlation:**
   - Already configured in Grafana datasource
   - Click on trace → See related logs

4. **Enable Trace-to-Metrics Correlation:**
   - Already configured in Grafana datasource
   - Click on trace → See related metrics

## Resources

- **Tempo Docs:** https://grafana.com/docs/tempo/latest/
- **OpenTelemetry Docs:** https://opentelemetry.io/docs/
- **Grafana Tracing:** https://grafana.com/docs/grafana/latest/datasources/tempo/

