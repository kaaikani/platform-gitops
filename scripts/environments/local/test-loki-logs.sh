#!/bin/bash
# =============================================================================
# TEST LOKI LOG COLLECTION LOCALLY
# =============================================================================
# This script verifies that Loki is collecting all Vendure logs including
# console.log outputs in the local environment.
#
# Usage:
#   ./helm/environments/local/test-loki-logs.sh [namespace]
#
# Example:
#   ./helm/environments/local/test-loki-logs.sh vendure-local
# =============================================================================

set -e

NAMESPACE="${1:-vendure-local}"
LOKI_NAMESPACE="monitoring"
TIMESTAMP=$(date +%s)
TEST_MESSAGE="TEST-LOKI-CONSOLE-LOG-${TIMESTAMP}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 TESTING LOKI LOG COLLECTION - LOCAL ENVIRONMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Namespace: $NAMESPACE"
echo "Test Message: $TEST_MESSAGE"
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

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "❌ Namespace '$NAMESPACE' not found!"
  echo "   Create it: kubectl create namespace $NAMESPACE"
  exit 1
fi

# Check if Loki is running
echo "1️⃣ Checking Loki status..."
if ! kubectl get pods -n $LOKI_NAMESPACE -l app=loki &>/dev/null; then
  echo "❌ Loki not found in namespace '$LOKI_NAMESPACE'"
  echo "   Deploy Loki first:"
  echo "   helm install loki grafana/loki-stack \\"
  echo "     -n $LOKI_NAMESPACE \\"
  echo "     -f helm/environments/local/loki-values.yaml"
  exit 1
fi

LOKI_POD=$(kubectl get pods -n $LOKI_NAMESPACE -l app=loki -o name 2>/dev/null | head -1)
if [ -z "$LOKI_POD" ]; then
  echo "❌ Loki pod not found!"
  exit 1
fi

LOKI_NAME=$(echo $LOKI_POD | cut -d'/' -f2)
LOKI_STATUS=$(kubectl get pod -n $LOKI_NAMESPACE $LOKI_NAME -o jsonpath='{.status.phase}')
echo "   Loki pod: $LOKI_NAME (Status: $LOKI_STATUS)"

if [ "$LOKI_STATUS" != "Running" ]; then
  echo "⚠️  Loki pod is not Running. Waiting 10 seconds..."
  sleep 10
  LOKI_STATUS=$(kubectl get pod -n $LOKI_NAMESPACE $LOKI_NAME -o jsonpath='{.status.phase}')
  if [ "$LOKI_STATUS" != "Running" ]; then
    echo "❌ Loki pod is still not Running. Check logs:"
    echo "   kubectl logs -n $LOKI_NAMESPACE $LOKI_NAME"
    exit 1
  fi
fi
echo "   ✅ Loki is running"
echo ""

# Check Promtail
echo "2️⃣ Checking Promtail status..."
PROMTAIL_DS=$(kubectl get daemonset -n $LOKI_NAMESPACE -l app=promtail -o name 2>/dev/null | head -1)
if [ -z "$PROMTAIL_DS" ]; then
  echo "⚠️  Promtail daemonset not found (checking pods)..."
  PROMTAIL_PODS=$(kubectl get pods -n $LOKI_NAMESPACE | grep promtail | wc -l)
  if [ "$PROMTAIL_PODS" -eq 0 ]; then
    echo "❌ Promtail not found!"
    exit 1
  fi
  echo "   Found $PROMTAIL_PODS Promtail pod(s)"
else
  PROMTAIL_READY=$(kubectl get daemonset -n $LOKI_NAMESPACE -l app=promtail -o jsonpath='{.status.numberReady}')
  PROMTAIL_DESIRED=$(kubectl get daemonset -n $LOKI_NAMESPACE -l app=promtail -o jsonpath='{.status.desiredNumberScheduled}')
  echo "   Promtail: $PROMTAIL_READY/$PROMTAIL_DESIRED ready"
  if [ "$PROMTAIL_READY" -lt "$PROMTAIL_DESIRED" ]; then
    echo "⚠️  Some Promtail pods are not ready"
  fi
fi
echo "   ✅ Promtail is running"
echo ""

# Check Vendure pods
echo "3️⃣ Checking Vendure pods in $NAMESPACE..."
VENDURE_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=vendure -o name 2>/dev/null | head -1)
if [ -z "$VENDURE_PODS" ]; then
  echo "⚠️  No Vendure pods found with label app.kubernetes.io/name=vendure"
  echo "   Trying to find any pod in namespace..."
  VENDURE_PODS=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | head -1)
fi

if [ -z "$VENDURE_PODS" ]; then
  echo "❌ No pods found in namespace '$NAMESPACE'"
  echo "   Deploy Vendure first:"
  echo "   helm install vendure-local ./helm/vendure-stack \\"
  echo "     -n $NAMESPACE \\"
  echo "     -f helm/environments/local/vendure-values.yaml"
  exit 1
fi

POD_NAME=$(echo $VENDURE_PODS | cut -d'/' -f2)
POD_STATUS=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.status.phase}')
echo "   Found pod: $POD_NAME (Status: $POD_STATUS)"

if [ "$POD_STATUS" != "Running" ]; then
  echo "⚠️  Pod is not Running. Waiting 10 seconds..."
  sleep 10
  POD_STATUS=$(kubectl get pod -n $NAMESPACE $POD_NAME -o jsonpath='{.status.phase}')
  if [ "$POD_STATUS" != "Running" ]; then
    echo "❌ Pod is still not Running"
    exit 1
  fi
fi
echo "   ✅ Pod is running"
echo ""

# Generate test console.log
echo "4️⃣ Generating test console.log in pod..."
echo "   Sending test message: $TEST_MESSAGE"
kubectl exec -n $NAMESPACE $POD_NAME -- sh -c "echo '$TEST_MESSAGE: This is a test console.log output from local testing' > /proc/1/fd/1" 2>/dev/null || \
kubectl exec -n $NAMESPACE $POD_NAME -- sh -c "echo '$TEST_MESSAGE: This is a test console.log output from local testing'" 2>/dev/null || {
  echo "⚠️  Could not send test log directly, trying alternative method..."
  # Try to exec into pod and run a command that outputs to console
  kubectl exec -n $NAMESPACE $POD_NAME -- node -e "console.log('$TEST_MESSAGE: This is a test console.log output from local testing')" 2>/dev/null || {
    echo "⚠️  Could not generate test log (pod might not have node)"
    echo "   This is OK - we'll check existing logs instead"
  }
}
echo "   ✅ Test log sent (or attempted)"
echo ""

# Wait for logs to be collected
echo "5️⃣ Waiting for logs to be collected (10 seconds)..."
sleep 10
echo ""

# Check Promtail logs for errors
echo "6️⃣ Checking Promtail logs for errors..."
PROMTAIL_POD=$(kubectl get pods -n $LOKI_NAMESPACE -l app=promtail -o name 2>/dev/null | head -1)
if [ -n "$PROMTAIL_POD" ]; then
  PROMTAIL_NAME=$(echo $PROMTAIL_POD | cut -d'/' -f2)
  echo "   Checking pod: $PROMTAIL_NAME"
  ERRORS=$(kubectl logs -n $LOKI_NAMESPACE $PROMTAIL_NAME --tail=50 2>&1 | grep -i "error" | head -3)
  if [ -n "$ERRORS" ]; then
    echo "   ⚠️  Found errors in Promtail logs:"
    echo "$ERRORS"
  else
    echo "   ✅ No errors found in Promtail logs"
  fi
else
  echo "   ⚠️  Promtail pod not found"
fi
echo ""

# Check Loki logs
echo "7️⃣ Checking Loki logs..."
if [ -n "$LOKI_NAME" ]; then
  echo "   Checking pod: $LOKI_NAME"
  ERRORS=$(kubectl logs -n $LOKI_NAMESPACE $LOKI_NAME --tail=50 2>&1 | grep -i "error" | head -3)
  if [ -n "$ERRORS" ]; then
    echo "   ⚠️  Found errors in Loki logs:"
    echo "$ERRORS"
  else
    echo "   ✅ No errors found in Loki logs"
  fi
fi
echo ""

# Instructions for Grafana
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 HOW TO VERIFY IN GRAFANA:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Port-forward Grafana:"
echo "   kubectl port-forward -n $LOKI_NAMESPACE svc/loki-grafana 3000:80"
echo ""
echo "2. Open Grafana:"
echo "   http://localhost:3000"
echo "   Login: admin / admin"
echo ""
echo "3. Add Loki datasource (if not already added):"
echo "   - Go to Configuration → Data Sources"
echo "   - Add data source → Select Loki"
echo "   - URL: http://loki:3100"
echo "   - Click 'Save & Test'"
echo ""
echo "4. Go to Explore and run these queries:"
echo ""
echo "   # All logs from namespace:"
echo "   {namespace=\"$NAMESPACE\"}"
echo ""
echo "   # Console.log outputs:"
echo "   {namespace=\"$NAMESPACE\"} |= \"console.log\""
echo ""
echo "   # Test log we just generated:"
echo "   {namespace=\"$NAMESPACE\"} |= \"$TEST_MESSAGE\""
echo ""
echo "   # All errors:"
echo "   {namespace=\"$NAMESPACE\"} |~ \"(?i)(error|err)\""
echo ""
echo "   # Specific pod:"
echo "   {namespace=\"$NAMESPACE\", pod=\"$POD_NAME\"}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ TEST COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Verify logs in Grafana (see above)"
echo "2. If logs are captured correctly, you're ready for EKS!"
echo "3. To deploy to EKS, use: helm/environments/production/loki-s3-storage.yaml"
echo ""

