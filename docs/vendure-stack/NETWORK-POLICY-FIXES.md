# Network Policy Security Fixes - Summary

## ✅ What Was Fixed

### 1. Added Default-Deny Policy
- **File**: `networkpolicy-default-deny.yaml`
- **Effect**: All pods in namespace are denied network access by default
- **Security**: Prevents unauthorized communication

### 2. Tightened Ingress Rules
- **Before**: Allowed traffic from ALL namespaces (`namespaceSelector: {}`)
- **After**: Only allows from:
  - Same namespace (for ALB and pod-to-pod)
  - kube-system (for ALB controller)
  - monitoring namespace (for Prometheus only)
- **Security**: Much more restrictive, prevents cross-namespace attacks

### 3. Improved Egress Rules
- **Before**: Too permissive with empty selectors
- **After**: Same functionality but with better comments and structure
- **Note**: External services (RDS, Redis Cloud) still need empty selectors, but ports are restricted

### 4. Added Testing Script
- **File**: `networkpolicy-test.sh`
- **Purpose**: Automated testing of network policies
- **Tests**: Default-deny, legitimate traffic, unauthorized access

## 🔒 Security Improvements

| Aspect | Before | After |
|--------|--------|-------|
| Default-Deny | ❌ Not implemented | ✅ Implemented |
| Ingress from all namespaces | ❌ Allowed | ✅ Blocked |
| Ingress from monitoring | ❌ All namespaces | ✅ Only monitoring namespace |
| Pod-to-pod in namespace | ✅ Working | ✅ Working (more explicit) |
| Egress to external | ⚠️ Too permissive | ⚠️ Still permissive (necessary for RDS/Redis) |

## 📋 Deployment Steps

### Step 1: Label Namespaces (Required for Prometheus)

```bash
# Label monitoring namespace (if not already labeled)
kubectl label namespace monitoring name=monitoring --overwrite

# Label kube-system namespace (if not already labeled)
kubectl label namespace kube-system name=kube-system --overwrite

# Verify labels
kubectl get namespace monitoring -o jsonpath='{.metadata.labels}'
kubectl get namespace kube-system -o jsonpath='{.metadata.labels}'
```

### Step 2: Deploy Network Policies

```bash
# Deploy with network policies enabled
helm upgrade vendure ./helm/vendure-stack \
  -n vendure-production \
  -f helm/environments/production/vendure-values.yaml

# Verify policies are created
kubectl get networkpolicy -n vendure-production
```

### Step 3: Test Network Policies

```bash
# Run automated tests
./helm/vendure-stack/templates/networkpolicy-test.sh vendure-production

# Or test manually
kubectl run test-pod --image=busybox -n vendure-production --rm -it -- sh
# Try: wget -O- http://vendure-service:80 (should work from same namespace)
```

### Step 4: Verify Application Works

```bash
# Check Vendure pods are running
kubectl get pods -n vendure-production

# Check logs for connection errors
kubectl logs -n vendure-production -l app=vendure --tail=50

# Test database connection
kubectl exec -n vendure-production deployment/vendure -- \
  nc -zv <rds-endpoint> 3306
```

## ⚠️ Important Notes

### Namespace Labels Required

The network policies assume namespaces have labels:
- `monitoring` namespace: `name=monitoring`
- `kube-system` namespace: `name=kube-system`

If these labels don't exist, Prometheus scraping may fail. Label them before deploying.

### ALB Traffic

ALB traffic comes from nodes (not pods), so we allow from:
- Same namespace (for service routing)
- kube-system (for ALB controller)

This is more permissive than ideal but necessary for ALB to work.

### External Services

Egress to external services (RDS, Redis Cloud) uses empty selectors because:
- They're outside the cluster
- We don't know their IPs in advance
- Ports are restricted (3306, 6379, 443, 80)

For better security, consider restricting to specific IP ranges if known.

## 🧪 Testing Checklist

- [ ] Default-deny policy exists
- [ ] Vendure network policy exists
- [ ] DNS resolution works
- [ ] Database connection works
- [ ] Redis connection works
- [ ] HTTPS to AWS works
- [ ] Prometheus can scrape metrics
- [ ] Unauthorized pods are blocked
- [ ] ALB traffic reaches pods

## 🔧 Troubleshooting

### Issue: Prometheus can't scrape

**Solution**: Label monitoring namespace
```bash
kubectl label namespace monitoring name=monitoring --overwrite
```

### Issue: ALB can't reach pods

**Solution**: Check kube-system namespace label
```bash
kubectl label namespace kube-system name=kube-system --overwrite
```

### Issue: Database connection fails

**Solution**: Check egress rules allow port 3306
```bash
kubectl describe networkpolicy -n vendure-production | grep 3306
```

## 📚 Files Changed

1. `helm/vendure-stack/templates/networkpolicy-default-deny.yaml` (NEW)
2. `helm/vendure-stack/templates/networkpolicy.yaml` (UPDATED)
3. `helm/vendure-stack/templates/networkpolicy-test.sh` (NEW)
4. `helm/vendure-stack/NETWORK-POLICY-SECURITY.md` (NEW)

## ✅ Security Status

- ✅ Default-deny implemented
- ✅ Ingress restricted to specific namespaces
- ✅ Egress restricted to necessary ports
- ✅ Testing script available
- ⚠️ External services still use empty selectors (necessary for functionality)
- ⚠️ ALB traffic requires namespace-level access (necessary for functionality)

## 🎯 Next Steps (Future Enhancements)

1. Restrict egress to specific IP ranges for RDS/Redis
2. Use VPC CIDR for ALB traffic instead of namespace selector
3. Restrict SMTP to specific email provider IPs
4. Add network policy monitoring/alerting

