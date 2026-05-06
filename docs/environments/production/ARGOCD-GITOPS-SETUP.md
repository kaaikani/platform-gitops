# ArgoCD GitOps Setup Guide

## 📋 Overview

This guide covers the complete setup of ArgoCD for GitOps-based continuous deployment in your Vendure Kubernetes cluster.

**Current Status:**
- ✅ ArgoCD Application definitions exist
- ⚠️ ArgoCD needs to be installed
- ⚠️ Git repository needs to be configured
- ⚠️ Repository credentials need to be set up

---

## 🎯 What is GitOps?

**GitOps** is a methodology where:
- **Git is the single source of truth** for infrastructure and application configurations
- **ArgoCD continuously monitors Git** and syncs changes to the cluster
- **Automatic deployments** happen when code is pushed to Git
- **Self-healing** ensures cluster state always matches Git state

**Benefits:**
- ✅ Version control for all configurations
- ✅ Audit trail of all changes
- ✅ Rollback by reverting Git commits
- ✅ Consistent deployments across environments
- ✅ Reduced manual errors

---

## 🏗️ Architecture

### App of Apps Pattern

```
┌─────────────────────────────────────┐
│  Root Application (app-of-apps)    │
│  - Watches: helm/argocd/applications│
└──────────────┬──────────────────────┘
               │
       ┌───────┴────────┐
       │                │
   ┌───▼───┐      ┌─────▼─────┐
   │ Child │      │   Child   │
   │  Apps │      │    Apps   │
   └───────┘      └───────────┘
```

### Application Structure

```
helm/argocd/
├── app-of-apps.yaml              # Root application
├── applications/
│   ├── vendure-production.yaml   # Production Vendure
│   ├── vendure-test.yaml          # Test/Staging Vendure
│   ├── monitoring-stack.yaml      # Prometheus/Grafana
│   └── karpenter.yaml             # Karpenter config
└── README.md
```

---

## 📦 Prerequisites

1. **Kubernetes Cluster** (EKS or local)
2. **kubectl** configured
3. **Git Repository** with your Helm charts
4. **Repository Access** (SSH key or HTTPS token)

---

## 🚀 Installation Steps

### Step 1: Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n argocd

# Verify installation
kubectl get pods -n argocd
```

### Step 2: Get ArgoCD Admin Password

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Save it securely!
```

### Step 3: Configure Git Repository Access

#### Option A: HTTPS with Personal Access Token (Recommended)

```bash
# Create secret for Git repository
kubectl create secret generic git-repo-credentials \
  --from-literal=type=git \
  --from-literal=url=https://github.com/your-org/vendure-k8s.git \
  --from-literal=username=your-username \
  --from-literal=password=your-github-token \
  -n argocd

# Configure ArgoCD to use the secret
kubectl patch secret argocd-secret \
  -n argocd \
  -p '{"stringData":{"repositories":"{\"https://github.com/your-org/vendure-k8s.git\":{\"type\":\"git\",\"url\":\"https://github.com/your-org/vendure-k8s.git\",\"password\":\"'$(kubectl get secret git-repo-credentials -n argocd -o jsonpath='{.data.password}' | base64 -d)'\",\"username\":\"'$(kubectl get secret git-repo-credentials -n argocd -o jsonpath='{.data.username}' | base64 -d)'\"}}"}}'
```

#### Option B: SSH Key

```bash
# Generate SSH key (if not exists)
ssh-keygen -t ed25519 -C "argocd@vendure" -f ~/.ssh/argocd_rsa -N ""

# Add public key to Git repository (GitHub/GitLab settings)

# Create secret in ArgoCD
kubectl create secret generic git-repo-ssh \
  --from-file=sshPrivateKey=~/.ssh/argocd_rsa \
  --from-file=type=git \
  --from-file=url=git@github.com:your-org/vendure-k8s.git \
  -n argocd

# Label secret for ArgoCD
kubectl label secret git-repo-ssh argocd.argoproj.io/secret-type=repository -n argocd
```

### Step 4: Update Application Files

Update the Git repository URL in all application files:

```bash
# Update repository URL
sed -i 's|https://github.com/your-org/vendure-k8s.git|https://github.com/YOUR-ORG/YOUR-REPO.git|g' \
  helm/argocd/app-of-apps.yaml \
  helm/argocd/applications/*.yaml
```

### Step 5: Deploy Root Application

```bash
# Apply root application (App of Apps)
kubectl apply -f helm/argocd/app-of-apps.yaml

# Wait for child applications to be created
kubectl get applications -n argocd

# Check sync status
kubectl get applications -n argocd -o wide
```

### Step 6: Access ArgoCD UI

#### Option A: Port Forward (Development)

```bash
# Port forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access: https://localhost:8080
# Username: admin
# Password: (from Step 2)
```

#### Option B: Ingress (Production)

See `helm/environments/production/argocd-ingress.yaml` for production ingress setup.

---

## 🔧 Configuration Details

### Sync Policies

**Automated Sync:**
- Changes in Git automatically sync to cluster
- No manual intervention needed

**Self-Healing:**
- Manual changes in cluster are reverted to match Git
- Ensures Git is always the source of truth

**Prune:**
- Resources deleted from Git are removed from cluster
- Keeps cluster clean

### Application Configuration

Each application has:
- **Source**: Git repository path or Helm chart
- **Destination**: Target namespace
- **Sync Policy**: Automated with self-healing
- **Value Files**: Merged for environment-specific configs
- **Ignore Differences**: For dynamic resources (secrets, replicas)

### Value File Hierarchy

For Vendure applications:
```yaml
valueFiles:
  - values.yaml                                    # Base values
  - values-production.yaml                         # Environment-specific
  - ../environments/production/vendure-values.yaml # Overrides
```

Files are merged in order (last wins).

---

## 📊 Monitoring Applications

### CLI Commands

```bash
# List all applications
kubectl get applications -n argocd

# Get application details
kubectl get application vendure-production -n argocd -o yaml

# Check sync status
kubectl get application vendure-production -n argocd -o jsonpath='{.status.sync.status}'

# Force sync (if needed)
kubectl patch application vendure-production -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main"}}}'
```

### ArgoCD CLI

```bash
# Install ArgoCD CLI
brew install argocd  # macOS
# or download from: https://github.com/argoproj/argo-cd/releases

# Login
argocd login localhost:8080

# List applications
argocd app list

# Get application status
argocd app get vendure-production

# Sync application
argocd app sync vendure-production
```

---

## 🔐 Security Best Practices

### 1. RBAC Configuration

Create ArgoCD projects with restricted permissions:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: vendure-production
  namespace: argocd
spec:
  description: Production Vendure applications
  sourceRepos:
    - 'https://github.com/your-org/vendure-k8s.git'
  destinations:
    - namespace: vendure-production
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
```

### 2. Repository Access

- Use **read-only** tokens for Git access
- Rotate credentials regularly
- Use separate tokens per environment

### 3. Sync Windows

Configure sync windows for production:

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
  syncWindows:
    - kind: allow
      schedule: '10 0 * * *'  # Only sync at midnight
      duration: 1h
      applications:
        - 'vendure-production'
```

### 4. Secrets Management

- Use **External Secrets Operator** for secrets
- Never commit secrets to Git
- Use `ignoreDifferences` for Secret resources

---

## 🚨 Troubleshooting

### Application Out of Sync

```bash
# Check why application is out of sync
kubectl describe application vendure-production -n argocd

# Check repository access
kubectl logs -n argocd deployment/argocd-repo-server --tail=50

# Test repository connection
argocd repo get https://github.com/your-org/vendure-k8s.git
```

### Sync Failed

```bash
# Check application events
kubectl get events -n argocd --field-selector involvedObject.name=vendure-production

# Check Helm chart errors
kubectl logs -n argocd deployment/argocd-repo-server --tail=100 | grep -i error

# Validate Helm chart
helm template helm/vendure-stack -f helm/vendure-stack/values-production.yaml
```

### Repository Access Issues

```bash
# Verify repository secret
kubectl get secret git-repo-credentials -n argocd -o yaml

# Test repository access
kubectl exec -n argocd deployment/argocd-repo-server -- \
  git ls-remote https://github.com/your-org/vendure-k8s.git
```

### Resources Not Created

```bash
# Check if namespace exists
kubectl get namespace vendure-production

# Verify CreateNamespace option
kubectl get application vendure-production -n argocd \
  -o jsonpath='{.spec.syncPolicy.syncOptions}'

# Check application controller logs
kubectl logs -n argocd deployment/argocd-application-controller --tail=100
```

---

## 📈 Advanced Features

### 1. ApplicationSets (Multi-Environment)

Use ApplicationSets to manage multiple environments:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: vendure-environments
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: production
            namespace: vendure-production
          - env: test
            namespace: vendure-test
  template:
    metadata:
      name: 'vendure-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/vendure-k8s.git
        path: helm/vendure-stack
        helm:
          valueFiles:
            - values.yaml
            - values-{{env}}.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
```

### 2. Sync Waves

Control deployment order:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Deploy first
```

### 3. Health Checks

Custom health checks for Vendure:

```yaml
spec:
  source:
    helm:
      values: |
        healthCheck:
          enabled: true
          path: /health
```

### 4. Notifications

Configure Slack/Email notifications:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
    channel: #vendure-deployments
```

---

## ✅ Verification Checklist

- [ ] ArgoCD installed and running
- [ ] Git repository configured
- [ ] Repository credentials set up
- [ ] Root application deployed
- [ ] Child applications created
- [ ] Applications synced and healthy
- [ ] ArgoCD UI accessible
- [ ] RBAC configured (if needed)
- [ ] Monitoring configured
- [ ] Documentation updated

---

## 📚 Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitOps Best Practices](https://www.gitops.tech/)
- [ArgoCD Examples](https://github.com/argoproj/argocd-example-apps)

---

**Last Updated:** 2026-02-09

