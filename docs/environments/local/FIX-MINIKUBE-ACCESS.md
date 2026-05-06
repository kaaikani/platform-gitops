# Fix: Unable to Connect to Minikube Services

## ❌ Problem

You're getting "Unable to connect" errors when trying to access services via NodePort URLs like:
- `http://192.168.49.2:30000` (Grafana)
- `http://192.168.49.2:31090` (Prometheus)

**This is normal!** Minikube NodePort services aren't directly accessible from your host machine in some configurations.

---

## ✅ Solutions (Choose One)

### **Solution 1: Use `minikube service` (Easiest!)**

This command automatically opens the service in your browser:

```bash
# Grafana
minikube service prometheus-stack-grafana -n monitoring

# Prometheus
minikube service prometheus-stack-kube-prom-prometheus -n monitoring

# Vendure
minikube service vendure-local-vendure-stack-vendure -n vendure-local
```

**What it does:**
- Gets the correct URL
- Opens it in your default browser
- Handles all the networking automatically

**To get just the URL (without opening browser):**
```bash
minikube service prometheus-stack-grafana -n monitoring --url
# Output: http://192.168.49.2:30000
```

---

### **Solution 2: Use Port-Forward (Most Reliable!)**

This is the most reliable method and works 100% of the time:

```bash
# Grafana (run in terminal, keep it open)
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Then open in browser: http://localhost:3000
```

**For all services:**

```bash
# Terminal 1: Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Terminal 2: Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090

# Terminal 3: Vendure
kubectl port-forward -n vendure-local svc/vendure-local-vendure-stack-vendure 8001:8001
```

**Access URLs:**
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Vendure: http://localhost:8001

**Note:** Keep the terminal windows open while using the services.

---

### **Solution 3: Use `minikube tunnel` (Advanced)**

This makes NodePort services accessible directly:

```bash
# Run in a separate terminal (keeps running)
minikube tunnel

# Leave it running, then access services normally:
# http://192.168.49.2:30000 (Grafana)
# http://192.168.49.2:31090 (Prometheus)
```

**Note:** 
- Requires sudo/root privileges
- Must keep the terminal open
- Creates a network route

---

## 🎯 Recommended Approach

### **For Quick Access:**
Use `minikube service` - it's the easiest:

```bash
minikube service prometheus-stack-grafana -n monitoring
```

### **For Daily Development:**
Use **port-forward** - it's the most reliable:

```bash
# Start Grafana (most important - has everything)
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Then access: http://localhost:3000
```

---

## 📋 Quick Reference

### **All Services - Port-Forward Commands**

```bash
# Grafana (Visualization - Most Important!)
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
# Access: http://localhost:3000

# Prometheus (Metrics)
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
# Access: http://localhost:9090

# Vendure (Application)
kubectl port-forward -n vendure-local svc/vendure-local-vendure-stack-vendure 8001:8001
# Access: http://localhost:8001

# Loki (Logs)
kubectl port-forward -n monitoring svc/loki 3100:3100
# Access: http://localhost:3100

# Tempo (Tracing)
kubectl port-forward -n monitoring svc/tempo-query-frontend 3200:3200
# Access: http://localhost:3200
```

### **All Services - minikube service Commands**

```bash
# Grafana
minikube service prometheus-stack-grafana -n monitoring

# Prometheus
minikube service prometheus-stack-kube-prom-prometheus -n monitoring

# Vendure
minikube service vendure-local-vendure-stack-vendure -n vendure-local
```

---

## 🔍 Why This Happens

Minikube runs in a VM (or container), and NodePort services are exposed on the Minikube VM's IP, not directly on your host. To access them:

1. **minikube service**: Handles the routing automatically
2. **port-forward**: Creates a direct tunnel from your host to the pod
3. **minikube tunnel**: Creates a network route to make NodePort accessible

---

## ✅ Quick Fix (Right Now!)

**Just run this:**

```bash
# Start Grafana (has everything you need)
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
```

**Then open:** http://localhost:3000

**That's it!** Grafana has Prometheus, Loki, and Tempo already configured as datasources.

---

## 🚀 Start All Services (Background)

If you want to start all port-forwards in the background:

```bash
# Start all in background
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 &
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &
kubectl port-forward -n vendure-local svc/vendure-local-vendure-stack-vendure 8001:8001 &

# Access:
# - Grafana: http://localhost:3000
# - Prometheus: http://localhost:9090
# - Vendure: http://localhost:8001
```

**To stop all:**
```bash
pkill -f "kubectl port-forward"
```

---

## 📝 Summary

**Problem**: Can't access `http://192.168.49.2:30000`

**Solution**: Use one of these:
1. ✅ **Port-Forward** (Recommended): `kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80`
2. ✅ **minikube service**: `minikube service prometheus-stack-grafana -n monitoring`
3. ✅ **minikube tunnel**: `minikube tunnel` (in separate terminal)

**Best for daily use**: Port-forward to `localhost:3000` (Grafana)

---

**Fix Guide Complete** ✅

