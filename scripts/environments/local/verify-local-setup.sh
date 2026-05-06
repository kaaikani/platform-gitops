#!/bin/bash
# =============================================================================
# VERIFY LOCAL MONITORING SETUP
# =============================================================================
# Checks if Grafana, Prometheus, Vendure, and Kubecost are correctly set up
#
# Usage:
#   ./helm/environments/local/verify-local-setup.sh
# =============================================================================

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 VERIFYING LOCAL MONITORING SETUP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check current context
CURRENT_CONTEXT=$(kubectl config current-context)
echo "📍 Current Kubernetes context: $CURRENT_CONTEXT"

if [[ "$CURRENT_CONTEXT" == *"eks"* ]] || [[ "$CURRENT_CONTEXT" == *"aws"* ]]; then
  echo "⚠️  WARNING: You're connected to AWS EKS, not local cluster!"
  echo "   Switch to local: kubectl config use-context minikube"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi
echo ""

# Check cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Cannot connect to cluster!"
  exit 1
fi
echo "✅ Cluster is accessible"
echo ""

# Function to check component
check_component() {
  local name=$1
  local namespace=$2
  local selector=$3
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Checking: $name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check namespace
  if ! kubectl get namespace "$namespace" &>/dev/null; then
    echo "❌ Namespace '$namespace' not found!"
    return 1
  fi
  echo "✅ Namespace exists"
  
  # Check pods
  if [ -n "$selector" ]; then
    PODS=$(kubectl get pods -n "$namespace" -l "$selector" -o name 2>/dev/null)
  else
    PODS=$(kubectl get pods -n "$namespace" -o name 2>/dev/null | head -5)
  fi
  
  if [ -z "$PODS" ]; then
    echo "❌ No pods found in namespace '$namespace'"
    return 1
  fi
  
  echo "✅ Pods found:"
  echo "$PODS" | while read pod; do
    POD_NAME=$(echo $pod | cut -d'/' -f2)
    STATUS=$(kubectl get pod -n "$namespace" "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
    READY=$(kubectl get pod -n "$namespace" "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
    if [ "$STATUS" == "Running" ] && [ "$READY" == "true" ]; then
      echo "   ✅ $POD_NAME: $STATUS (Ready)"
    else
      echo "   ⚠️  $POD_NAME: $STATUS (Not Ready)"
    fi
  done
  
  # Check services
  SERVICES=$(kubectl get svc -n "$namespace" -o name 2>/dev/null | head -3)
  if [ -n "$SERVICES" ]; then
    echo "✅ Services:"
    echo "$SERVICES" | while read svc; do
      echo "   - $svc"
    done
  fi
  
  echo ""
  return 0
}

# Check Grafana
check_component "Grafana" "monitoring" "app.kubernetes.io/name=grafana"

# Check Prometheus
check_component "Prometheus" "monitoring" "app.kubernetes.io/name=prometheus"

# Check Loki
check_component "Loki" "monitoring" "app=loki"

# Check Promtail
check_component "Promtail" "monitoring" "app=promtail"

# Check Vendure
check_component "Vendure" "vendure-local" "app.kubernetes.io/name=vendure"

# Check Kubecost
check_component "Kubecost" "kubecost" "app=cost-analyzer"

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Count running pods
GRAFANA_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running 2>/dev/null | wc -l)
PROMETHEUS_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --field-selector=status.phase=Running 2>/dev/null | wc -l)
LOKI_PODS=$(kubectl get pods -n monitoring -l app=loki --field-selector=status.phase=Running 2>/dev/null | wc -l)
VENDURE_PODS=$(kubectl get pods -n vendure-local --field-selector=status.phase=Running 2>/dev/null | wc -l)
KUBECOST_PODS=$(kubectl get pods -n kubecost --field-selector=status.phase=Running 2>/dev/null | wc -l)

echo "Running Pods:"
echo "  Grafana:    $GRAFANA_PODS"
echo "  Prometheus: $PROMETHEUS_PODS"
echo "  Loki:       $LOKI_PODS"
echo "  Vendure:    $VENDURE_PODS"
echo "  Kubecost:   $KUBECOST_PODS"
echo ""

# Access instructions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 ACCESS INSTRUCTIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$GRAFANA_PODS" -gt 0 ]; then
  echo "✅ Grafana:"
  echo "   kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
  echo "   http://localhost:3000 (admin/admin)"
  echo ""
fi

if [ "$PROMETHEUS_PODS" -gt 0 ]; then
  echo "✅ Prometheus:"
  echo "   kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090"
  echo "   http://localhost:9090"
  echo ""
fi

if [ "$LOKI_PODS" -gt 0 ]; then
  echo "✅ Loki:"
  echo "   kubectl port-forward -n monitoring svc/loki 3100:3100"
  echo "   Or access via Grafana (add datasource: http://loki:3100)"
  echo ""
fi

if [ "$VENDURE_PODS" -gt 0 ]; then
  echo "✅ Vendure:"
  echo "   kubectl port-forward -n vendure-local svc/vendure-local 8001:8001 3002:3002"
  echo "   http://localhost:8001/admin-api"
  echo ""
fi

if [ "$KUBECOST_PODS" -gt 0 ]; then
  echo "✅ Kubecost:"
  echo "   kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090"
  echo "   http://localhost:9090"
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ VERIFICATION COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

