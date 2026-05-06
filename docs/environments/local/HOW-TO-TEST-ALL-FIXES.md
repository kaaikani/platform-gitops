# How to Test All Fixes - Complete Guide

## 📋 Overview

This guide shows you how to test all deployed fixes to verify they're working correctly.

---

## 🚀 Quick Start: Deploy and Test Everything

### Option 1: Automated (Recommended)

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui
./helm/environments/local/deploy-and-test-all.sh
```

This script will:
1. Deploy all monitoring components (Prometheus, Grafana, Loki, Tempo)
2. Deploy Trivy Operator (image scanning)
3. Configure network policies
4. Apply Pod Security Standards
5. Run comprehensive tests

### Option 2: Manual Testing

Follow the sections below to test each component individually.

---

## ✅ Test 1: Monitoring Stack

### Check Pods Are Running

```bash
# Prometheus
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Grafana
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Loki
kubectl get pods -n monitoring -l app=loki

# Tempo
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
```

**Expected**: All pods should be in `Running` state

### Test Grafana Access

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Login: admin / admin
# (Get password: kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
```

**Test Steps**:
1. Login to Grafana
2. Go to **Configuration** → **Data Sources**
3. Verify:
   - ✅ Prometheus datasource exists
   - ✅ Loki datasource exists
   - ✅ Tempo datasource exists (if deployed)

### Test Loki Log Collection

```bash
# Check Loki is ready
kubectl exec -n monitoring -l app=loki -- wget -q -O- "http://localhost:3100/ready"

# Query logs (via Grafana or API)
kubectl port-forward -n monitoring svc/loki 3100:3100
curl "http://localhost:3100/loki/api/v1/query?query={namespace=\"vendure-local\"}" | jq
```

**Expected**: Should return log entries from vendure-local namespace

### Test Tempo Tracing

```bash
# Check Tempo is ready
kubectl exec -n monitoring -l app.kubernetes.io/name=tempo -- wget -q -O- "http://localhost:3200/ready"

# Access Tempo UI (if available)
kubectl port-forward -n monitoring svc/tempo 3200:3200
# Open: http://localhost:3200
```

**Test Steps**:
1. Make API requests to Vendure
2. Go to Grafana → **Explore** → Select **Tempo** datasource
3. Search for traces: `service.name=vendure-local`
4. Verify traces appear

---

## ✅ Test 2: Image Scanning (Trivy Operator)

### Check Trivy Operator

```bash
# Check Trivy Operator pod
kubectl get pods -n trivy-system

# Check Trivy webhook
kubectl get validatingwebhookconfiguration | grep trivy
```

**Expected**: 
- Trivy Operator pod should be `Running`
- Validating webhook should exist

### Test Image Scanning

```bash
# Check vulnerability reports
kubectl get vulnerabilityreports -A

# View a specific report
kubectl get vulnerabilityreport <pod-name> -n vendure-local -o yaml

# Check for critical vulnerabilities
kubectl get vulnerabilityreports -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.report.summary.criticalCount}{"\n"}{end}'
```

**Test Steps**:
1. Deploy a test pod with a vulnerable image
2. Trivy should scan it automatically
3. Check for vulnerability reports
4. Verify admission webhook blocks HIGH/CRITICAL vulnerabilities

### Test Admission Control

```bash
# Try to deploy a pod with a known vulnerable image
kubectl run test-vulnerable --image=nginx:1.18.0 -n vendure-local

# Check if it was blocked or allowed
kubectl get pod test-vulnerable -n vendure-local
```

**Expected**: Pods with HIGH/CRITICAL vulnerabilities should be blocked

---

## ✅ Test 3: Network Policies

### Check Network Policies

```bash
# List all network policies
kubectl get networkpolicy -A

# Check vendure-local namespace
kubectl get networkpolicy -n vendure-local

# View default-deny policy
kubectl get networkpolicy default-deny-all -n vendure-local -o yaml
```

**Expected**: 
- Default-deny policy should exist
- Application-specific policies should exist

### Test Network Isolation

```bash
# Create a test pod
kubectl run test-pod --image=busybox --rm -i --restart=Never -n vendure-local -- sh

# Inside the pod, try to access Vendure service
wget -O- --timeout=3 http://vendure-local:8001

# Should fail if default-deny is working
```

**Expected**: 
- Unauthorized pods should NOT be able to access Vendure
- Vendure pods should be able to access required services

### Test Legitimate Traffic

```bash
# Port-forward Vendure
kubectl port-forward -n vendure-local svc/vendure-local 8001:8001

# From host, test access
curl http://localhost:8001/health

# Should work (traffic from outside cluster)
```

**Expected**: Legitimate traffic should work

---

## ✅ Test 4: Pod Security Standards (PSS)

### Check Namespace Labels

```bash
# Check PSS labels
kubectl get namespace vendure-local -o jsonpath='{.metadata.labels}' | jq

# Should show:
# pod-security.kubernetes.io/enforce: baseline
# pod-security.kubernetes.io/audit: baseline
# pod-security.kubernetes.io/warn: restricted
```

**Expected**: All namespaces should have PSS labels

### Test Enforcement

```bash
# Try to create a pod that violates PSS
kubectl run test-pss-violation --image=busybox --rm -i --restart=Never \
  -n vendure-local \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' \
  -- sh -c "whoami"

# Should be blocked or warned if PSS is enforced
```

**Expected**: 
- In `restricted` namespace: Pod should be blocked
- In `baseline` namespace: Pod may be allowed with warning

---

## ✅ Test 5: RBAC (Role-Based Access Control)

### Check Roles

```bash
# List roles
kubectl get roles -n vendure-local

# Check specific role
kubectl get role developer-role -n vendure-local -o yaml
kubectl get role devops-role -n vendure-local -o yaml
kubectl get role read-only-role -n vendure-local -o yaml
```

**Expected**: Three roles should exist:
- `developer-role` (read-only)
- `devops-role` (full access)
- `read-only-role` (view-only)

### Check Role Bindings

```bash
# List role bindings
kubectl get rolebindings -n vendure-local

# Check if users are bound
kubectl get rolebindings -n vendure-local -o yaml | grep -A 5 subjects
```

**Expected**: Role bindings should exist for configured users

### Test Access Control

```bash
# Test if current user can perform actions
kubectl auth can-i get pods --namespace vendure-local
kubectl auth can-i create pods --namespace vendure-local
kubectl auth can-i delete pods --namespace vendure-local

# Test specific user (if configured)
kubectl auth can-i get pods --namespace vendure-local --as=devops@kk
```

**Expected**: Access should match role permissions

---

## ✅ Test 6: Cost Monitoring (Kubecost)

### Check Kubecost

```bash
# Check Kubecost pods
kubectl get pods -n kubecost

# Port-forward Kubecost UI
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090

# Open: http://localhost:9090
```

**Test Steps**:
1. Access Kubecost UI
2. Check cost breakdown by namespace
3. Verify cost allocation labels are working
4. Check cost reports

### Test Cost Tracking

```bash
# Check cost allocation
kubectl get pods -n vendure-local --show-labels | grep cost

# Check Kubecost API
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090 &
curl "http://localhost:9090/model/allocation?window=1d" | jq
```

**Expected**: Should show cost breakdown by namespace/application

---

## ✅ Test 7: Distributed Tracing (Tempo)

### Check Tempo

```bash
# Check Tempo pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo

# Check Tempo service
kubectl get svc -n monitoring tempo

# Test Tempo health
kubectl exec -n monitoring -l app.kubernetes.io/name=tempo -- wget -q -O- "http://localhost:3200/ready"
```

**Expected**: Tempo should be running and healthy

### Test Tracing

```bash
# 1. Make API requests to Vendure
kubectl port-forward -n vendure-local svc/vendure-local 8001:8001 &
curl http://localhost:8001/shop-api
curl http://localhost:8001/admin-api

# 2. Check traces in Grafana
# - Go to Grafana → Explore → Tempo
# - Search: service.name=vendure-local
# - Verify traces appear
```

**Expected**: 
- Traces should appear in Grafana
- Should see HTTP requests, database queries
- Should be able to correlate with logs/metrics

---

## ✅ Test 8: Log Retention (Loki)

### Check Retention Configuration

```bash
# Check Loki config
kubectl get configmap -n monitoring loki -o yaml | grep retention

# Should show: retention_period: 168h (7 days)
```

**Expected**: Retention should be configured (7 days for local)

### Test Retention

```bash
# Check Loki storage usage
kubectl exec -n monitoring -l app=loki -- df -h /data/loki

# Query old logs (should be deleted after retention period)
# Note: This test requires waiting for retention period to expire
```

**Expected**: Old logs should be deleted after retention period

---

## ✅ Test 9: Alert Rules

### Check Alert Rules

```bash
# List PrometheusRules
kubectl get prometheusrule -A

# View specific rule
kubectl get prometheusrule vendure-local-vendure-stack-alerts -n vendure-local -o yaml
```

**Expected**: Alert rules should exist

### Test Alert Firing

```bash
# Check active alerts in Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &
curl "http://localhost:9090/api/v1/alerts" | jq '.data.alerts[] | select(.state=="firing")'
```

**Expected**: Alerts should fire when conditions are met

---

## 🧪 Run All Tests Automatically

### Comprehensive Test Script

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui
./helm/environments/local/test-all-fixes.sh
```

This will test:
- ✅ Monitoring stack (Prometheus, Grafana, Loki, Tempo)
- ✅ Image scanning (Trivy)
- ✅ Network policies
- ✅ Pod Security Standards
- ✅ RBAC
- ✅ Cost monitoring (Kubecost)
- ✅ Distributed tracing
- ✅ Log retention
- ✅ Alert rules

---

## 📊 Test Results Interpretation

### ✅ Passed
- Component is working correctly
- No action needed

### ❌ Failed
- Component is not working
- Review error messages
- Check pod logs: `kubectl logs -n <namespace> <pod-name>`

### ⚠️ Warning
- Component may not be fully configured
- May need additional setup
- Review warnings for details

---

## 🔧 Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -A

# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Check pod events
kubectl describe pod -n <namespace> <pod-name>
```

### Services Not Accessible

```bash
# Check services
kubectl get svc -A

# Check endpoints
kubectl get endpoints -A

# Test connectivity
kubectl run test-curl --image=curlimages/curl --rm -i --restart=Never -- <service-url>
```

### Configuration Issues

```bash
# Check ConfigMaps
kubectl get configmap -A

# Check Secrets
kubectl get secrets -A

# View configuration
kubectl get configmap <name> -n <namespace> -o yaml
```

---

## 📝 Next Steps

After testing:

1. **Review Test Results**: Check which tests passed/failed
2. **Fix Issues**: Address any failed tests
3. **Document Findings**: Note any issues or improvements needed
4. **Deploy to Production**: Once local tests pass, deploy to EKS

---

**Testing Complete** ✅

