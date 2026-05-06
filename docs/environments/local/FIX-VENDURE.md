# Fix Vendure - Build and Deploy Image

## ❌ Current Issue

**Status**: `ErrImageNeverPull`  
**Problem**: The image `vendure-local:latest` doesn't exist in Minikube  
**Solution**: Build the image and load it into Minikube

---

## ✅ Quick Fix (3 Steps)

### **Step 1: Build Docker Image**

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui

# Build the Vendure image
docker build -t vendure-local:latest .
```

**Note**: Make sure you have a `Dockerfile` in the project root. If not, you may need to create one or use an existing one.

---

### **Step 2: Load Image into Minikube**

```bash
# Load the image into Minikube
minikube image load vendure-local:latest
```

**Alternative**: If you're using Docker Desktop with Kubernetes, the image should already be available.

---

### **Step 3: Restart Vendure Deployment**

```bash
# Restart the deployment to pick up the new image
kubectl rollout restart deployment/vendure-local-vendure-stack-vendure -n vendure-local

# Wait for it to be ready
kubectl rollout status deployment/vendure-local-vendure-stack-vendure -n vendure-local

# Check status
kubectl get pods -n vendure-local
```

---

## 🔍 Verify It's Working

```bash
# Check pod status
kubectl get pods -n vendure-local

# Should show: READY 1/1, STATUS Running

# Check logs
kubectl logs -n vendure-local -l app.kubernetes.io/name=vendure-stack --tail=50

# Access Vendure
kubectl port-forward -n vendure-local svc/vendure-local-vendure-stack-vendure 8001:8001
# Then open: http://localhost:8001
```

---

## 📋 Complete Commands (Copy & Paste)

```bash
# Navigate to project
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui

# Build image
docker build -t vendure-local:latest .

# Load into Minikube
minikube image load vendure-local:latest

# Restart deployment
kubectl rollout restart deployment/vendure-local-vendure-stack-vendure -n vendure-local

# Wait and check
kubectl rollout status deployment/vendure-local-vendure-stack-vendure -n vendure-local
kubectl get pods -n vendure-local
```

---

## 🐳 Dockerfile Check

If you don't have a Dockerfile, you may need to create one. Check if it exists:

```bash
ls -la Dockerfile*
```

**Common Dockerfile locations:**
- `./Dockerfile`
- `./docker/Dockerfile`
- `./src/Dockerfile`

---

## 🔧 Alternative: Use Existing Image

If you have the image in a registry, you can change the pull policy:

```bash
# Edit the values file
# Change pullPolicy from "Never" to "IfNotPresent" or "Always"

# Then upgrade
helm upgrade vendure-local helm/vendure-stack \
  -n vendure-local \
  -f helm/environments/local/vendure-values.yaml \
  --set vendure.image.pullPolicy=IfNotPresent \
  --set vendure.image.repository=your-registry/vendure \
  --set vendure.image.tag=latest
```

---

## ⚠️ Troubleshooting

### **Issue: "docker: command not found"**
```bash
# Install Docker or use Podman
# For Podman:
podman build -t vendure-local:latest .
minikube image load vendure-local:latest
```

### **Issue: "Cannot connect to Docker daemon"**
```bash
# Start Docker service
sudo systemctl start docker

# Or use Minikube's Docker
eval $(minikube docker-env)
docker build -t vendure-local:latest .
```

### **Issue: Image builds but pod still fails**
```bash
# Check if image is loaded in Minikube
minikube image ls | grep vendure-local

# Verify image name matches
kubectl get deployment -n vendure-local vendure-local-vendure-stack-vendure -o jsonpath='{.spec.template.spec.containers[*].image}'

# Should output: vendure-local:latest
```

### **Issue: Pod starts but crashes**
```bash
# Check logs
kubectl logs -n vendure-local -l app.kubernetes.io/name=vendure-stack

# Check events
kubectl describe pod -n vendure-local -l app.kubernetes.io/name=vendure-stack
```

---

## 📊 Current Configuration

**Image**: `vendure-local:latest`  
**Pull Policy**: `Never` (expects local image)  
**Namespace**: `vendure-local`  
**Service Type**: `NodePort`  
**Ports**: 
- Server: `8001` (NodePort: `31080`)
- Admin: `3002` (NodePort: `31082`)

---

## ✅ Success Criteria

After fixing, you should see:

```bash
$ kubectl get pods -n vendure-local
NAME                                                   READY   STATUS    RESTARTS   AGE
vendure-local-vendure-stack-vendure-xxxxx              1/1     Running   0          1m
```

**Then access:**
- Server: `http://localhost:8001` (via port-forward)
- Or: `http://$(minikube ip):31080` (via NodePort)

---

**Fix Guide Complete** ✅

