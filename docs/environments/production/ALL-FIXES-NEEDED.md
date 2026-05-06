# All Fixes Needed - Comprehensive Checklist

## 📋 Summary Date
2026-02-10

## 🎯 Overview

This document consolidates ALL fixes needed across:
- Security gaps
- Monitoring & observability
- Infrastructure & cost
- Application resilience

**Current Status**: Most fixes are **created** but **NOT deployed** to the cluster.

---

## 🔴 Priority 0: Critical Security (Deploy Immediately)

### 1. Deploy Image Scanning (Trivy Operator)
**Status**: Script created, not deployed  
**Risk**: 🔴 HIGH - Vulnerable images can be deployed  
**Action**:
```bash
cd helm/environments/production
./setup-trivy-operator.sh
```
**Verification**:
```bash
kubectl get pods -n trivy-system
kubectl get vulnerabilityreports -A
```

### 2. Deploy Secrets Rotation
**Status**: Script created, not deployed  
**Risk**: 🔴 HIGH - Secrets not rotating automatically  
**Action**:
```bash
cd helm/environments/production
./setup-secrets-rotation.sh
```
**Verification**:
```bash
aws secretsmanager describe-secret --secret-id vendure/production/database
```

---

## 🟡 Priority 1: High Priority (Deploy Soon)

### 3. Deploy Network Policies
**Status**: Enabled in config, not deployed  
**Risk**: 🟡 MEDIUM - No network isolation  
**Action**:
```bash
helm upgrade vendure-prod ../../vendure-stack \
  -n vendure-production \
  -f vendure-values.yaml
```
**Verification**:
```bash
kubectl get networkpolicy -n vendure-production
./networkpolicy-test.sh vendure-production
```

### 4. Verify Pod Security Standards
**Status**: Scripts created, not verified  
**Risk**: 🟡 MEDIUM - Enforcement status unknown  
**Action**:
```bash
cd helm/environments/production
./verify-security-setup.sh vendure-production
# If labels not applied:
./setup-pod-security-standards.sh
```
**Verification**:
```bash
kubectl get namespace vendure-production -o jsonpath='{.metadata.labels}'
```

### 5. Complete RBAC Deployment
**Status**: User created, not deployed to cluster  
**Risk**: 🟡 MEDIUM - RBAC not active  
**Action**:
```bash
# When EKS cluster is ready:
# 1. Create EKS access entry
aws eks create-access-entry \
  --cluster-name vendure-prod \
  --principal-arn arn:aws:iam::ACCOUNT_ID:user/devops@kk \
  --region ap-south-1

# 2. Upgrade Helm release
helm upgrade vendure-prod ../../vendure-stack \
  -n vendure-production \
  -f vendure-values.yaml
```
**Verification**:
```bash
kubectl get roles -n vendure-production
kubectl get rolebindings -n vendure-production
```

### 6. Deploy Distributed Tracing (Tempo)
**Status**: Fully configured, not deployed  
**Risk**: 🟡 MEDIUM - No tracing visibility  
**Action**:
```bash
# 1. Install Tempo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install tempo grafana/tempo-distributed \
  -n monitoring \
  --create-namespace \
  -f helm/environments/production/tempo-values.yaml

# 2. Install npm dependencies
npm install @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-http

# 3. Configure Grafana datasource
kubectl apply -f helm/environments/production/grafana-tempo-datasource.yaml
```
**Verification**:
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
# Make test requests and check traces in Grafana
```

### 7. Deploy Cost Monitoring (Kubecost/OpenCost)
**Status**: Configs exist, not deployed  
**Risk**: 🟡 MEDIUM - No cost visibility  
**Action**:
```bash
# Option 1: Kubecost (commercial, free tier)
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm install kubecost kubecost/cost-analyzer \
  -n kubecost --create-namespace \
  -f helm/environments/production/kubecost-values.yaml

# Option 2: OpenCost (open source, free)
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm install opencost opencost/opencost \
  -n opencost --create-namespace \
  -f helm/kubecost/values.yaml
```
**Verification**:
```bash
kubectl get pods -n kubecost  # or opencost
# Access UI and verify cost tracking
```

### 8. Tune Alert Thresholds
**Status**: Alerts configured, not tuned  
**Risk**: 🟡 MEDIUM - Alert fatigue  
**Action**:
- Edit `helm/vendure-stack/templates/prometheusrule.yaml`
- Change pod down threshold: `1m` → `2-3m`
- Add grace period for deployments
- Configure alert grouping in AlertManager
**Verification**:
- Monitor alert volume
- Test alert behavior
- Verify no false positives during deployments

---

## 🟢 Priority 2: Medium Priority (Optimize When Possible)

### 9. Deploy S3 Storage for Loki
**Status**: Config exists, using EBS  
**Benefit**: 71% cost savings ($0.80 → $0.23/month)  
**Action**:
```bash
cd helm/environments/production
./setup-loki-s3.sh
# Then upgrade Loki with S3 config
helm upgrade loki grafana/loki-stack \
  -n monitoring \
  -f loki-s3-storage.yaml
```
**Verification**:
```bash
kubectl get pods -n monitoring -l app=loki
# Check logs are being stored in S3
```

### 10. Add Storage Growth Monitoring
**Status**: Not configured  
**Benefit**: Early warning of storage issues  
**Action**:
- Add Prometheus alerts for storage growth
- Track daily growth rate
- Alert if growth exceeds expected rate
**Verification**:
- Check alerts fire correctly
- Verify growth tracking

### 11. Add Cost Alerts
**Status**: Not configured  
**Benefit**: Early warning of cost overruns  
**Action**:
- Configure Kubecost/OpenCost alerts
- Alert when daily costs exceed threshold
- Alert when namespace costs spike
**Verification**:
- Test alert firing
- Verify cost tracking accuracy

### 12. Configure Alert Grouping & Suppression
**Status**: Not configured  
**Benefit**: Reduce alert fatigue  
**Action**:
- Configure AlertManager grouping
- Set up alert suppression for maintenance windows
- Configure alert routing
**Verification**:
- Test alert grouping
- Verify suppression works

---

## 📊 Deployment Status Summary

| Category | Total Items | Created | Deployed | Status |
|----------|-------------|---------|----------|--------|
| **Security** | 5 | ✅ 5 | ⚠️ 0.5 | 10% deployed |
| **Monitoring** | 4 | ✅ 4 | ⚠️ 1 | 25% deployed |
| **Total** | 9 | ✅ 9 | ⚠️ 1.5 | **17% deployed** |

---

## 🚀 Deployment Order (Recommended)

### Phase 1: Critical Security (Do First)
1. Deploy Trivy Operator (image scanning)
2. Deploy Secrets Rotation

### Phase 2: High Priority (Do Next)
3. Deploy Network Policies
4. Verify Pod Security Standards
5. Deploy Tempo (distributed tracing)
6. Deploy Kubecost/OpenCost (cost monitoring)
7. Tune Alert Thresholds

### Phase 3: Complete RBAC (When Cluster Ready)
8. Create EKS access entry
9. Upgrade Helm release with RBAC

### Phase 4: Optimizations (When Time Permits)
10. Deploy S3 storage for Loki
11. Add storage growth monitoring
12. Add cost alerts
13. Configure alert grouping

---

## 📋 Quick Deployment Checklist

### Pre-Deployment
- [ ] EKS cluster exists and is accessible
- [ ] Helm release exists in cluster
- [ ] AWS credentials configured
- [ ] kubectl configured for cluster
- [ ] All scripts are executable

### Critical Security (Priority 0)
- [ ] Deploy Trivy Operator
- [ ] Deploy Secrets Rotation

### High Priority (Priority 1)
- [ ] Deploy Network Policies
- [ ] Verify Pod Security Standards
- [ ] Deploy Tempo
- [ ] Deploy Cost Monitoring
- [ ] Tune Alert Thresholds
- [ ] Complete RBAC (when cluster ready)

### Optimizations (Priority 2)
- [ ] Deploy S3 storage for Loki
- [ ] Add storage growth monitoring
- [ ] Add cost alerts
- [ ] Configure alert grouping

### Post-Deployment Verification
- [ ] Run comprehensive verification: `./verify-security-setup.sh`
- [ ] Test network policies: `./networkpolicy-test.sh`
- [ ] Verify Trivy scanning: `kubectl get vulnerabilityreports`
- [ ] Verify secrets rotation: `aws secretsmanager describe-secret`
- [ ] Test RBAC access: `kubectl auth can-i ...`
- [ ] Verify tracing: Check traces in Grafana
- [ ] Verify cost monitoring: Check cost dashboard

---

## ⚠️ Important Notes

1. **Deployment Dependency**: Many fixes require EKS cluster to exist. Current status: cluster not found.

2. **Local vs Production**: 
   - Some fixes are for production only (EKS)
   - Local (Minikube) has different requirements
   - Test in local first when possible

3. **Deployment Order Matters**:
   - Image scanning should be first (blocks vulnerable images)
   - Then secrets rotation (protects credentials)
   - Then network policies (network isolation)
   - Then verify PSS (pod security)
   - Finally complete RBAC (access control)

4. **Testing**: All deployments should be tested in a non-production environment first.

5. **Verification**: After each deployment, verify it's working correctly.

---

## 📈 Progress Tracking

### Configuration Progress: 100% ✅
- ✅ All security configurations created
- ✅ All monitoring configurations created
- ✅ All scripts written
- ✅ All values files updated

### Deployment Progress: 17% ⚠️
- ✅ IAM user created (1/9)
- ❌ Trivy Operator not deployed (0/1)
- ❌ Secrets rotation not deployed (0/1)
- ❌ Network policies not deployed (0/1)
- ❌ PSS not verified (0/1)
- ⚠️ RBAC partially deployed (0.5/1)
- ❌ Tempo not deployed (0/1)
- ❌ Cost monitoring not deployed (0/1)
- ❌ Alert tuning not done (0/1)

### Overall Status
- **Before**: 🔴 **CRITICAL** - Multiple high-risk gaps
- **After (Config)**: 🟡 **IMPROVED** - All fixes created
- **After (Deployed)**: 🔴 **CRITICAL** - Not deployed yet

---

## 🎯 Next Steps

1. **Immediate**: Deploy critical security fixes (Trivy, Secrets Rotation)
2. **This Week**: Deploy high-priority fixes (Network Policies, Tempo, Cost Monitoring)
3. **This Month**: Complete all fixes and optimizations
4. **Ongoing**: Monitor, tune, and optimize

---

**All Fixes Needed** ✅

**Key Takeaway**: All fixes have been **created and configured**, but they need to be **deployed and verified** in the actual cluster to be effective. Start with critical security fixes first.

