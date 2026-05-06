# ArgoCD GitOps Configuration

This directory contains ArgoCD Application definitions for GitOps-based continuous delivery.

## 📋 Quick Status

**Current State:**
- ✅ Application definitions configured
- ⚠️ ArgoCD needs to be installed
- ⚠️ Git repository needs to be configured

**Quick Setup:**
```bash
# See complete guide:
cat ../environments/production/ARGOCD-GITOPS-SETUP.md

# Or run automated setup:
./../environments/production/setup-argocd.sh \
  --git-repo-url https://github.com/your-org/vendure-k8s.git \
  --git-username your-username \
  --git-token ghp_xxxxxxxxxxxx
```

## Architecture

ArgoCD follows an "App of Apps" pattern:
- **Root Application** (`app-of-apps.yaml`): Manages all child applications
- **Child Applications**: Individual applications for each component

## Application Structure

```
helm/argocd/
├── app-of-apps.yaml              # Root application
├── applications/
│   ├── vendure-production.yaml   # Production Vendure app
│   ├── vendure-test.yaml         # Test Vendure app
│   ├── monitoring-stack.yaml    # Prometheus/Grafana stack
│   └── karpenter.yaml            # Karpenter NodePools
└── README.md                     # This file
```

## How It Works

1. **Git Repository**: All Helm charts and configurations are stored in Git
2. **ArgoCD Watches Git**: ArgoCD continuously monitors the Git repository
3. **Automatic Sync**: When changes are detected, ArgoCD automatically syncs to cluster
4. **Self-Healing**: ArgoCD ensures cluster state matches Git state

## Deployment Flow

```
Developer commits → Git push → ArgoCD detects change → Syncs to cluster → Deployment updated
```

## Application Details

### vendure-production
- **Source**: Helm chart from Git repository
- **Namespace**: `vendure-production`
- **Sync Policy**: Automated with self-healing
- **Value Files**: Merges base values with production overrides

### vendure-test
- **Source**: Helm chart from Git repository
- **Namespace**: `vendure-test`
- **Sync Policy**: Automated with self-healing
- **Value Files**: Merges base values with test overrides

### monitoring-stack
- **Source**: External Helm repository (prometheus-community)
- **Namespace**: `monitoring`
- **Chart**: kube-prometheus-stack
- **Value Files**: Can be managed via:
  - ConfigMap in Git repository
  - Inline values in Application manifest
  - ApplicationSet with multiple sources (ArgoCD 2.6+)
  - External Secrets Operator

### karpenter-config
- **Source**: Kubernetes manifests from Git
- **Namespace**: `default`
- **Resources**: NodePools and EC2NodeClass CRDs
- **Sync Policy**: Automated

## Setup Instructions

1. **Install ArgoCD**:
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```

2. **Configure Git Repository**:
   - Update `repoURL` in all application files with your Git repository URL
   - Ensure ArgoCD has access to the repository (SSH key or HTTPS token)

3. **Deploy Root Application**:
   ```bash
   kubectl apply -f helm/argocd/app-of-apps.yaml
   ```

4. **Verify**:
   - Access ArgoCD UI (port-forward or ingress)
   - Check that all applications are synced and healthy

## Sync Policies

- **Automated**: Changes in Git automatically sync to cluster
- **Self-Heal**: Manual changes in cluster are reverted to match Git
- **Prune**: Resources deleted from Git are removed from cluster

## Best Practices

1. **Pin Chart Versions**: Use specific chart versions for external repositories
2. **Separate Environments**: Use different applications for test/production
3. **Value File Hierarchy**: Merge multiple value files for flexibility
4. **Ignore Differences**: Configure ignoreDifferences for dynamic resources (secrets, replicas)
5. **Retry Policy**: Configure retry for transient failures

## Accessing ArgoCD

```bash
# Port forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Troubleshooting

- **Application OutOfSync**: Check Git repository access and permissions
- **Sync Failed**: Check Helm chart syntax and value file paths
- **Resources Not Created**: Verify namespace exists or CreateNamespace=true is set

