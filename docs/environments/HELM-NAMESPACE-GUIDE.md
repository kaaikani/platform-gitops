# Helm Namespace Management Guide

## ✅ You're Right - Use Helm for Namespaces!

If you're using Helm, you should use Helm's built-in namespace creation instead of manual `kubectl create namespace` commands.

---

## 🎯 Two Ways to Create Namespaces with Helm

### Option 1: Use `--create-namespace` Flag (Recommended)

Helm 3.1+ supports the `--create-namespace` flag which automatically creates the namespace if it doesn't exist.

```bash
# ⚠️ IMPORTANT: Run from workspace root: /home/adminuser/Desktop/vendure/K8s/Admin-ui

# Production
helm install vendure-prod helm/vendure-stack \
  -n vendure-production \
  --create-namespace \
  -f helm/environments/production/vendure-values.yaml

# Test
helm install vendure-test helm/vendure-stack \
  -n vendure-test \
  --create-namespace \
  -f helm/environments/test/vendure-values.yaml

# Local
helm install vendure-local helm/vendure-stack \
  -n vendure-local \
  --create-namespace \
  -f helm/environments/local/vendure-values.yaml
```

**Advantages:**
- ✅ Simple - one flag
- ✅ Helm manages it
- ✅ Works with `helm upgrade` too
- ✅ No separate scripts needed

**Note:** `--create-namespace` only creates the namespace, it doesn't apply Pod Security Standards labels. You'll need to apply PSS labels separately if needed.

---

### Option 2: Include Namespace in Helm Chart (Optional)

The Helm chart now includes a namespace template (`templates/namespace.yaml`) that can create the namespace with Pod Security Standards labels.

**Enable it in values.yaml:**
```yaml
namespace:
  create: true
  name: vendure-production
  podSecurity:
    enforce: restricted
    audit: restricted
    warn: restricted
```

**Then deploy (from workspace root):**
```bash
helm install vendure-prod helm/vendure-stack \
  -n vendure-production \
  -f helm/environments/production/vendure-values.yaml
```

**Advantages:**
- ✅ Namespace managed by Helm
- ✅ Can include PSS labels automatically
- ✅ Version controlled with chart

**Disadvantages:**
- ⚠️ Namespace is part of Helm release (deleted if you uninstall)
- ⚠️ Requires updating values.yaml

---

## 📋 Recommended Approach

**For Production:** Use `--create-namespace` flag + apply PSS labels separately

```bash
# 1. Install with --create-namespace (from workspace root)
helm install vendure-prod helm/vendure-stack \
  -n vendure-production \
  --create-namespace \
  -f helm/environments/production/vendure-values.yaml

# 2. Apply Pod Security Standards (one-time)
kubectl label namespace vendure-production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

**Why this approach?**
- Namespace creation is separate from Helm release lifecycle
- PSS labels are applied once and persist
- If you uninstall Helm release, namespace remains (safer)

---

## 🔄 Upgrading Existing Deployments

If namespace already exists, just use normal `helm upgrade`:

```bash
# From workspace root
helm upgrade vendure-prod helm/vendure-stack \
  -n vendure-production \
  -f helm/environments/production/vendure-values.yaml
```

The `--create-namespace` flag is only needed for initial installation.

---

## 📝 Updated Deployment Commands

### Production
```bash
# From workspace root: /home/adminuser/Desktop/vendure/K8s/Admin-ui
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui

helm install vendure-prod helm/vendure-stack \
  -n vendure-production \
  --create-namespace \
  -f helm/environments/production/vendure-values.yaml

# Apply PSS labels
kubectl label namespace vendure-production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

### Test
```bash
# From workspace root: /home/adminuser/Desktop/vendure/K8s/Admin-ui
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui

helm install vendure-test helm/vendure-stack \
  -n vendure-test \
  --create-namespace \
  -f helm/environments/test/vendure-values.yaml

# Apply PSS labels
kubectl label namespace vendure-test \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

### Local
```bash
# From workspace root: /home/adminuser/Desktop/vendure/K8s/Admin-ui
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui

helm install vendure-local helm/vendure-stack \
  -n vendure-local \
  --create-namespace \
  -f helm/environments/local/vendure-values.yaml

# Apply PSS labels
kubectl label namespace vendure-local \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

### Alternative: If you're in a different directory

**From `helm/environments/` directory:**
```bash
cd helm/environments
helm install vendure-prod ../vendure-stack \
  -n vendure-production \
  --create-namespace \
  -f production/vendure-values.yaml
```

**From `helm/vendure-stack/` directory:**
```bash
cd helm/vendure-stack
helm install vendure-prod . \
  -n vendure-production \
  --create-namespace \
  -f ../environments/production/vendure-values.yaml
```

---

## ❌ What NOT to Do

**Don't create namespaces manually if using Helm:**
```bash
# ❌ Don't do this
kubectl create namespace vendure-production
helm install vendure-prod ./helm/vendure-stack -n vendure-production
```

**Instead, use Helm (from workspace root):**
```bash
# ✅ Do this
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui
helm install vendure-prod helm/vendure-stack \
  -n vendure-production \
  --create-namespace \
  -f helm/environments/production/vendure-values.yaml
```

---

## 🎯 Summary

1. **Use `--create-namespace` flag** with `helm install` - Helm will create the namespace
2. **Apply PSS labels separately** after namespace creation (one-time)
3. **Don't create namespaces manually** - let Helm manage it
4. **For upgrades**, just use normal `helm upgrade` (no `--create-namespace` needed)

This way, Helm manages everything and you don't need separate namespace creation scripts!


