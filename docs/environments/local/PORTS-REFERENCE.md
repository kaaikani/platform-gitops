# Port Reference Guide - Local Environment

## 🌐 Quick Access Ports

### **Option 1: Using NodePort (Direct Access via Minikube IP)**

Get your Minikube IP:
```bash
minikube ip
# Example output: 192.168.49.2
```

Then access services at: `http://<MINIKUBE_IP>:<PORT>`

---

## 📋 Service Ports

### **1. Grafana (Visualization & Dashboards)**
- **NodePort**: `30000`
- **Access**: `http://<MINIKUBE_IP>:30000`
- **Example**: `http://192.168.49.2:30000`
- **Default Login**: `admin` / `admin`
- **Alternative (Port-Forward)**: 
  ```bash
  kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
  # Then access: http://localhost:3000
  ```

### **2. Prometheus (Metrics)**
- **NodePort**: `31090`
- **Access**: `http://<MINIKUBE_IP>:31090`
- **Example**: `http://192.168.49.2:31090`
- **Alternative (Port-Forward)**:
  ```bash
  kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
  # Then access: http://localhost:9090
  ```

### **3. Loki (Log Collection)**
- **NodePort**: `31000` (Loki Grafana instance)
- **Loki API**: ClusterIP `3100` (use port-forward)
- **Access Grafana with Loki**: `http://<MINIKUBE_IP>:31000`
- **Alternative (Port-Forward)**:
  ```bash
  kubectl port-forward -n monitoring svc/loki 3100:3100
  # Then access API: http://localhost:3100
  ```

### **4. Tempo (Distributed Tracing)**
- **No NodePort** (ClusterIP only)
- **Use Port-Forward**:
  ```bash
  kubectl port-forward -n monitoring svc/tempo-query-frontend 3200:3200
  # Then access: http://localhost:3200
  ```
- **Or access via Grafana**: Add Tempo as datasource in Grafana (http://tempo-query-frontend:3200)

### **5. Vendure Application**
- **Server API**: NodePort `31080`
- **Admin UI**: NodePort `31082`
- **Access Server**: `http://<MINIKUBE_IP>:31080`
- **Access Admin**: `http://<MINIKUBE_IP>:31082`
- **Example**: 
  - Server: `http://192.168.49.2:31080`
  - Admin: `http://192.168.49.2:31082`
- **Alternative (Port-Forward)**:
  ```bash
  kubectl port-forward -n vendure-local svc/vendure-local-vendure-stack-vendure 8001:8001
  # Then access: http://localhost:8001
  ```

### **6. Kubecost (Cost Monitoring)**
- **NodePort**: `30090`
- **Access**: `http://<MINIKUBE_IP>:30090`
- **Example**: `http://192.168.49.2:30090`
- **Alternative (Port-Forward)**:
  ```bash
  kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090
  # Then access: http://localhost:9090
  ```

---

## 🎯 Recommended Access Methods

### **For Development (Easiest)**
Use **port-forward** - no need to remember Minikube IP:

```bash
# Grafana (most important)
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090

# Vendure
kubectl port-forward -n vendure-local svc/vendure-local-vendure-stack-vendure 8001:8001
```

Then access:
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
- Vendure: `http://localhost:8001`

### **For Testing (Direct Access)**
Use **NodePort** with Minikube IP:

```bash
# Get Minikube IP
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"

# Access services
echo "Grafana: http://$MINIKUBE_IP:30000"
echo "Prometheus: http://$MINIKUBE_IP:31090"
echo "Vendure: http://$MINIKUBE_IP:31080"
```

---

## 📊 Port Summary Table

| Service | NodePort | Port-Forward | Access URL (NodePort) | Access URL (Port-Forward) |
|---------|----------|--------------|------------------------|---------------------------|
| **Grafana** | 30000 | 3000:80 | `http://<IP>:30000` | `http://localhost:3000` |
| **Prometheus** | 31090 | 9090:9090 | `http://<IP>:31090` | `http://localhost:9090` |
| **Loki** | 31000 | 3100:3100 | `http://<IP>:31000` | `http://localhost:3100` |
| **Tempo** | N/A | 3200:3200 | N/A | `http://localhost:3200` |
| **Vendure Server** | 31080 | 8001:8001 | `http://<IP>:31080` | `http://localhost:8001` |
| **Vendure Admin** | 31082 | 3002:3002 | `http://<IP>:31082` | `http://localhost:3002` |
| **Kubecost** | 30090 | 9090:9090 | `http://<IP>:30090` | `http://localhost:9090` |

---

## 🚀 Quick Start Commands

### **Start All Port-Forwards (Background)**

```bash
# Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 &

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &

# Vendure
kubectl port-forward -n vendure-local svc/vendure-local-vendure-stack-vendure 8001:8001 &

# Tempo
kubectl port-forward -n monitoring svc/tempo-query-frontend 3200:3200 &
```

### **Access URLs (Port-Forward)**
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Vendure: http://localhost:8001
- Tempo: http://localhost:3200

---

## 🔍 Verify Services Are Running

```bash
# Check all services
kubectl get svc -A | grep -E "NodePort|grafana|prometheus|loki|tempo|vendure"

# Check Minikube IP
minikube ip

# Test access
curl http://$(minikube ip):30000  # Grafana
curl http://$(minikube ip):31090  # Prometheus
curl http://$(minikube ip):31080  # Vendure
```

---

## ⚠️ Important Notes

1. **NodePort Access**: Requires Minikube IP. Use `minikube ip` to get it.
2. **Port-Forward**: Only works from your local machine (not accessible from other machines).
3. **Port Conflicts**: If ports are already in use, change NodePort values in values files.
4. **Grafana**: Most important service - access it first to configure datasources.
5. **Tempo**: No NodePort configured - use port-forward or access via Grafana.

---

## 🎯 Most Common Use Case

**For daily development, use Grafana port-forward:**

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
```

Then open: **http://localhost:3000**

Grafana has all datasources pre-configured:
- Prometheus (metrics)
- Loki (logs)
- Tempo (traces)

---

**Port Reference Complete** ✅

