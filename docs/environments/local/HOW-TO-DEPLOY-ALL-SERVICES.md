# How to Deploy All Services Locally

## 📋 Overview

When you run Helm commands locally, **NOT all services deploy automatically**. You need to deploy them separately. Here's what's configured and how to deploy everything.

---

## 🎯 Services Configured for Local

### 1. **Monitoring Stack** (Prometheus, Grafana, Loki, Tempo)
- **Chart**: `prometheus-community/kube-prometheus-stack`
- **Chart**: `grafana/loki-stack`
- **Chart**: `grafana/tempo-distributed`
- **Config**: `helm/environments/local/prometheus-stack-values.yaml`
- **Config**: `helm/environments/local/loki-values.yaml`
- **Config**: `helm/environments/local/tempo-values.yaml`

### 2. **Cost Monitoring** (Kubecost)
- **Chart**: `kubecost/cost-analyzer`
- **Config**: `helm/environments/local/kubecost-values.yaml`

### 3. **Image Scanning** (Trivy Operator)
- **Chart**: `aquasecurity/trivy-operator`
- **Config**: `helm/environments/production/trivy-operator-values.yaml`

### 4. **Vendure Application**
- **Chart**: `helm/vendure-stack` (your custom chart)
- **Config**: `helm/environments/local/vendure-values.yaml`

### 5. **Backup** (Velero - optional for local)
- **Chart**: `vmware-tanzu/velero`
- **Config**: `helm/environments/local/velero-values.yaml`

---

## 🚀 How to Deploy Everything

### **Option 1: Deploy All at Once (Recommended)**

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui

# This deploys everything and runs tests
./helm/environments/local/deploy-and-test-all.sh
```

**What this script does:**
1. ✅ Deploys Monitoring Stack (Prometheus, Grafana, Loki, Tempo)
2. ✅ Deploys Trivy Operator (Image Scanning)
3. ✅ Deploys Network Policies (if Vendure is deployed)
4. ✅ Applies Pod Security Standards (PSS) labels
5. ✅ Runs comprehensive tests

---

### **Option 2: Deploy Step by Step**

#### **Step 1: Deploy Monitoring Stack**

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui

# This deploys: Prometheus, Grafana, Loki, Tempo, Kubecost
./helm/environments/local/setup-local-monitoring.sh
```

**What gets deployed:**
- ✅ Prometheus (metrics collection)
- ✅ Grafana (visualization)
- ✅ Loki (log aggregation)
- ✅ Promtail (log collector)
- ✅ Tempo (distributed tracing)
- ✅ Kubecost (cost monitoring)

#### **Step 2: Deploy Trivy Operator (Image Scanning)**

```bash
# Add Trivy Helm repo
helm repo add aquasecurity https://aquasecurity.github.io/helm-charts/
helm repo update

# Deploy Trivy Operator
helm install trivy-operator aquasecurity/trivy-operator \
  -n trivy-system \
  --create-namespace \
  -f helm/environments/production/trivy-operator-values.yaml
```

#### **Step 3: Deploy Vendure Application**

```bash
# Deploy Vendure with all configurations
helm install vendure-local helm/vendure-stack \
  -n vendure-local \
  --create-namespace \
  -f helm/environments/local/vendure-values.yaml
```

**Note**: You need to build and load the Vendure image first:
```bash
# Build image
docker build -t vendure-local:latest .

# Load into Minikube
minikube image load vendure-local:latest
```

#### **Step 4: Apply Pod Security Standards**

```bash
# Apply PSS labels to namespaces
kubectl label namespace vendure-local \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite

kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

---

## 📊 What Each Service Does

| Service | Purpose | Namespace | Access |
|---------|---------|-----------|--------|
| **Prometheus** | Metrics collection | `monitoring` | Port-forward: 9090 |
| **Grafana** | Visualization & dashboards | `monitoring` | Port-forward: 3000 |
| **Loki** | Log aggregation | `monitoring` | Via Grafana or port-forward: 3100 |
| **Tempo** | Distributed tracing | `monitoring` | Via Grafana or port-forward: 3200 |
| **Kubecost** | Cost monitoring | `kubecost` | Port-forward: 9090 |
| **Trivy Operator** | Image vulnerability scanning | `trivy-system` | Check reports: `kubectl get vulnerabilityreports -A` |
| **Vendure** | Your application | `vendure-local` | Depends on your service config |

---

## ✅ Quick Deploy Commands

### **Deploy Everything (One Command)**

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui
./helm/environments/local/deploy-and-test-all.sh
```

### **Deploy Only Monitoring**

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui
./helm/environments/local/setup-local-monitoring.sh
```

### **Deploy Only Vendure**

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui
helm install vendure-local helm/vendure-stack \
  -n vendure-local \
  --create-namespace \
  -f helm/environments/local/vendure-values.yaml
```

---

## 🔍 Verify Everything is Deployed

```bash
# Check all pods
kubectl get pods -A | grep -E "monitoring|trivy|vendure-local|kubecost"

# Check Helm releases
helm list -A

# Run comprehensive test
./helm/environments/local/test-local-comprehensive.sh
```

---

## 🎯 Answer to Your Question

**Q: "If I run helm local, does it run all the services I configured?"**

**A: No, not automatically.** You need to:

1. **Either** run the automated script:
   ```bash
   ./helm/environments/local/deploy-and-test-all.sh
   ```

2. **Or** deploy each service separately:
   - Monitoring: `./helm/environments/local/setup-local-monitoring.sh`
   - Trivy: `helm install trivy-operator ...`
   - Vendure: `helm install vendure-local helm/vendure-stack ...`

**The Helm values files (`vendure-values.yaml`, `loki-values.yaml`, etc.) are just configurations** - they don't deploy anything by themselves. You need to run `helm install` or `helm upgrade` commands to actually deploy.

---

## 📝 Summary

| What | How to Deploy |
|------|---------------|
| **All Services** | `./helm/environments/local/deploy-and-test-all.sh` |
| **Monitoring Only** | `./helm/environments/local/setup-local-monitoring.sh` |
| **Vendure Only** | `helm install vendure-local helm/vendure-stack -n vendure-local --create-namespace -f helm/environments/local/vendure-values.yaml` |
| **Trivy Only** | `helm install trivy-operator aquasecurity/trivy-operator -n trivy-system --create-namespace` |

---

## 🚨 Important Notes

1. **Minikube must be running**: `minikube start`
2. **Helm repos must be added**: The scripts do this automatically
3. **Vendure image must be built**: `docker build -t vendure-local:latest . && minikube image load vendure-local:latest`
4. **Namespaces are created automatically**: Using `--create-namespace` flag

---

## 📚 Related Documentation

- **Full Test Results**: `helm/environments/local/LOCAL-TEST-RESULTS.md`
- **Testing Guide**: `helm/environments/local/HOW-TO-TEST-ALL-FIXES.md`
- **Deployment Summary**: `helm/environments/local/DEPLOYMENT-AND-TESTING-SUMMARY.md`

