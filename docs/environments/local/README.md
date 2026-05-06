# Local Development Environment

This directory contains configuration for local Kubernetes development (Minikube, Docker Desktop, Kind).

## Quick Start

### 1. Start Local Kubernetes Cluster

**Minikube:**
```bash
minikube start
minikube addons enable ingress
```

**Docker Desktop:**
- Enable Kubernetes in Docker Desktop settings

**Kind:**
```bash
kind create cluster --name vendure-local
```

### 2. Build and Load Image

```bash
# Build image
docker build -t vendure-local:latest .

# For Minikube: Load image
minikube image load vendure-local:latest

# For Docker Desktop/Kind: Image is available locally
```

### 3. Create Namespace and Secrets

```bash
kubectl create namespace vendure-local

# Create secrets
kubectl create secret generic vendure-secrets \
  --namespace vendure-local \
  --from-literal=DB_HOST='host.minikube.internal' \
  --from-literal=DB_PORT='3306' \
  --from-literal=DB_NAME='wow_vendure' \
  --from-literal=DB_USERNAME='root' \
  --from-literal=DB_PASSWORD='your-local-password' \
  --from-literal=REDIS_HOST='host.minikube.internal' \
  --from-literal=REDIS_PORT='6379' \
  --from-literal=REDIS_PASSWORD='' \
  --from-literal=AWS_ACCESS_KEY_ID='your-key' \
  --from-literal=AWS_SECRET_ACCESS_KEY='your-secret' \
  --from-literal=S3_BUCKET='cdn.kaaikani.co.in' \
  --from-literal=COOKIE_SECRET='local-dev-secret' \
  --from-literal=SUPERADMIN_PASSWORD='admin123'
```

### 4. Deploy with Helm

```bash
cd helm/vendure-stack

helm install vendure-local . \
  -n vendure-local \
  -f values.yaml \
  -f values-local.yaml \
  -f ../environments/local/vendure-values.yaml
```

### 5. Access Application

```bash
# Port forward
kubectl port-forward svc/vendure-local 8001:8001 3002:3002 -n vendure-local

# Access:
# - Admin API: http://localhost:8001/admin-api
# - Shop API: http://localhost:8001/shop-api
# - Admin UI: http://localhost:3002/admin
```

## Configuration

### Database Connection

**Minikube:**
- Use `host.minikube.internal` to reach host machine MySQL
- Ensure MySQL is running on host and accessible

**Docker Desktop:**
- Use `host.docker.internal` to reach host machine

**Kind:**
- May need to use port-forward or run MySQL in cluster
- Or use in-cluster MySQL by enabling it in values

### Redis Connection

- Can use host machine Redis
- Or run Redis in cluster (enable redis.enabled in values)
- Or use external Redis service

### Resource Limits

Local environment uses minimal resources:
- Memory: 256Mi request, 512Mi limit
- CPU: 100m request, 500m limit

Adjust in `vendure-values.yaml` if needed.

## Troubleshooting

### Image Pull Errors

```bash
# For Minikube: Load image
minikube image load vendure-local:latest

# Check image exists
minikube image ls | grep vendure-local
```

### Database Connection Issues

```bash
# Test connectivity from pod
kubectl run -it --rm debug --image=busybox --restart=Never -n vendure-local -- \
  nc -zv host.minikube.internal 3306
```

### Port Already in Use

Change NodePort values in `vendure-values.yaml`:
```yaml
service:
  ports:
    server:
      nodePort: 31080  # Change if conflict
    admin:
      nodePort: 31082  # Change if conflict
```

## Cleanup

```bash
# Uninstall Helm release
helm uninstall vendure-local -n vendure-local

# Delete namespace
kubectl delete namespace vendure-local
```

