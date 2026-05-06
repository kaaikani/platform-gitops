#!/bin/bash
# =============================================================================
# SETUP LOCAL MONITORING STACK
# =============================================================================
# This script sets up Grafana, Prometheus, Vendure, and Kubecost for local testing
#
# Usage:
#   ./helm/environments/local/setup-local-monitoring.sh
# =============================================================================

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 SETTING UP LOCAL MONITORING STACK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check current context
CURRENT_CONTEXT=$(kubectl config current-context)
echo "📍 Current Kubernetes context: $CURRENT_CONTEXT"

if [[ "$CURRENT_CONTEXT" == *"eks"* ]] || [[ "$CURRENT_CONTEXT" == *"aws"* ]]; then
  echo "⚠️  WARNING: You're connected to AWS EKS!"
  echo "   Switching to local cluster (minikube)..."
  kubectl config use-context minikube 2>/dev/null || {
    echo "❌ Minikube context not found!"
    echo "   Available contexts:"
    kubectl config get-contexts
    echo ""
    echo "   Please switch to local cluster manually:"
    echo "   kubectl config use-context <local-context-name>"
    exit 1
  }
  echo "✅ Switched to local cluster"
fi

# Verify local cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Cannot connect to local cluster!"
  echo "   Start your local cluster first:"
  echo "   - Minikube: minikube start"
  echo "   - Docker Desktop: Enable Kubernetes in settings"
  echo "   - Kind: kind create cluster"
  exit 1
fi

echo "✅ Local cluster is accessible"
echo ""

# Create namespaces
echo "1️⃣ Creating namespaces..."
for ns in monitoring vendure-local kubecost; do
  if kubectl get namespace "$ns" &>/dev/null; then
    echo "   ✓ Namespace '$ns' already exists"
  else
    kubectl create namespace "$ns"
    echo "   ✅ Created namespace '$ns'"
  fi
done
echo ""

# Add Helm repos
echo "2️⃣ Adding Helm repositories..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || echo "   ✓ Grafana repo already added"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || echo "   ✓ Prometheus repo already added"
helm repo add kubecost https://kubecost.github.io/cost-analyzer/ 2>/dev/null || echo "   ✓ Kubecost repo already added"
helm repo update
echo "✅ Helm repos updated"
echo ""

# Deploy Prometheus Stack (includes Grafana)
echo "3️⃣ Deploying Prometheus Stack (includes Grafana)..."
if helm list -n monitoring | grep -q prometheus-stack; then
  echo "   ⚠️  Prometheus Stack already installed, upgrading..."
  helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
    -n monitoring \
    -f helm/environments/local/prometheus-stack-values.yaml \
    --create-namespace 2>/dev/null || {
    echo "   ⚠️  Upgrade failed, trying install..."
    helm install prometheus-stack prometheus-community/kube-prometheus-stack \
      -n monitoring \
      -f helm/environments/local/prometheus-stack-values.yaml \
      --create-namespace
  }
else
  helm install prometheus-stack prometheus-community/kube-prometheus-stack \
    -n monitoring \
    -f helm/environments/local/prometheus-stack-values.yaml \
    --create-namespace
fi
echo "✅ Prometheus Stack deployed"
echo ""

# Deploy Loki (for logs)
echo "4️⃣ Deploying Loki (for log collection)..."
if helm list -n monitoring | grep -q loki; then
  echo "   ⚠️  Loki already installed, upgrading..."
  helm upgrade loki grafana/loki-stack \
    -n monitoring \
    -f helm/environments/local/loki-values.yaml 2>/dev/null || {
    echo "   ⚠️  Upgrade failed, trying install..."
    helm install loki grafana/loki-stack \
      -n monitoring \
      -f helm/environments/local/loki-values.yaml
  }
else
  helm install loki grafana/loki-stack \
    -n monitoring \
    -f helm/environments/local/loki-values.yaml
fi
echo "✅ Loki deployed"
echo ""

# Deploy Tempo (for distributed tracing)
echo "5️⃣ Deploying Tempo (for distributed tracing)..."
if helm list -n monitoring | grep -q tempo; then
  echo "   ⚠️  Tempo already installed, upgrading..."
  helm upgrade tempo grafana/tempo-distributed \
    -n monitoring \
    -f helm/environments/local/tempo-values.yaml 2>/dev/null || {
    echo "   ⚠️  Upgrade failed, trying install..."
    helm install tempo grafana/tempo-distributed \
      -n monitoring \
      -f helm/environments/local/tempo-values.yaml
  }
else
  helm install tempo grafana/tempo-distributed \
    -n monitoring \
    -f helm/environments/local/tempo-values.yaml
fi
echo "✅ Tempo deployed"
echo ""

# Deploy Kubecost (cost monitoring)
echo "6️⃣ Deploying Kubecost (cost monitoring)..."
if helm list -n kubecost | grep -q kubecost; then
  echo "   ⚠️  Kubecost already installed, skipping..."
else
  helm install kubecost kubecost/cost-analyzer \
    -n kubecost \
    -f helm/environments/local/kubecost-values.yaml \
    --create-namespace 2>/dev/null || {
    echo "   ⚠️  Kubecost install failed (may need different values)"
    echo "   Continuing without Kubecost..."
  }
fi
echo "✅ Kubecost deployment attempted"
echo ""

# Wait for pods to be ready
echo "7️⃣ Waiting for pods to be ready..."
sleep 10
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=120s 2>/dev/null || echo "   ⚠️  Prometheus not ready yet"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=120s 2>/dev/null || echo "   ⚠️  Grafana not ready yet"
kubectl wait --for=condition=ready pod -l app=loki -n monitoring --timeout=120s 2>/dev/null || echo "   ⚠️  Loki not ready yet"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tempo -n monitoring --timeout=120s 2>/dev/null || echo "   ⚠️  Tempo not ready yet"
echo ""

# Show status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 DEPLOYMENT STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Prometheus Stack:"
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus 2>/dev/null || echo "   Not found"
echo ""

echo "Grafana:"
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null || echo "   Not found"
echo ""

echo "Loki:"
kubectl get pods -n monitoring -l app=loki 2>/dev/null || echo "   Not found"
echo ""

echo "Promtail:"
kubectl get pods -n monitoring -l app=promtail 2>/dev/null || echo "   Not found"
echo ""

echo "Tempo:"
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo 2>/dev/null || echo "   Not found"
echo ""

echo "Kubecost:"
kubectl get pods -n kubecost 2>/dev/null | head -3 || echo "   Not found"
echo ""

echo "Vendure:"
kubectl get pods -n vendure-local 2>/dev/null || echo "   Not found (deploy separately)"
echo ""

# Access instructions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 ACCESS INSTRUCTIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Grafana:"
echo "  kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
echo "  Open: http://localhost:3000"
echo "  Login: admin / admin (or check secret: kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo ""
echo "Prometheus:"
echo "  kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090"
echo "  Open: http://localhost:9090"
echo ""
echo "Loki:"
echo "  kubectl port-forward -n monitoring svc/loki 3100:3100"
echo "  Or access via Grafana (add datasource: http://loki:3100)"
echo ""
echo "Tempo:"
echo "  kubectl port-forward -n monitoring svc/tempo 3200:3200"
echo "  Or access via Grafana (add datasource: http://tempo:3200)"
echo ""
echo "Kubecost:"
echo "  kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090"
echo "  Open: http://localhost:9090"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SETUP COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Deploy Vendure: ./helm/environments/local/deploy-vendure-local.sh"
echo "2. Test Loki logs: ./helm/environments/local/test-loki-logs.sh vendure-local"
echo "3. Access Grafana and verify all datasources are working"
echo ""

