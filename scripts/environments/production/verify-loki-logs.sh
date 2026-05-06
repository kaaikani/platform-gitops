#!/bin/bash
# =============================================================================
# VERIFY LOKI IS COLLECTING ALL VENDURE LOGS (including console.log)
# =============================================================================

NAMESPACE="${1:-vendure-production}"
LOKI_NAMESPACE="monitoring"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 VERIFYING LOKI LOG COLLECTION FOR: $NAMESPACE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if Loki is running
echo "1️⃣ Checking Loki status..."
kubectl get pods -n $LOKI_NAMESPACE -l app=loki 2>/dev/null
if [ $? -ne 0 ]; then
  echo "❌ Loki pod not found!"
  exit 1
fi

# Check if Promtail is running
echo ""
echo "2️⃣ Checking Promtail status..."
kubectl get daemonset -n $LOKI_NAMESPACE -l app=promtail 2>/dev/null
if [ $? -ne 0 ]; then
  echo "⚠️  Promtail daemonset not found (might be using different label)"
  kubectl get pods -n $LOKI_NAMESPACE | grep promtail
fi

# Check Vendure pods
echo ""
echo "3️⃣ Checking Vendure pods in $NAMESPACE..."
VENDURE_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=vendure -o name 2>/dev/null | head -1)
if [ -z "$VENDURE_PODS" ]; then
  echo "⚠️  No Vendure pods found in $NAMESPACE"
  echo "   Trying alternative label..."
  VENDURE_PODS=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | head -1)
fi

if [ -z "$VENDURE_PODS" ]; then
  echo "❌ No pods found in $NAMESPACE"
  exit 1
fi

POD_NAME=$(echo $VENDURE_PODS | cut -d'/' -f2)
echo "   Found pod: $POD_NAME"

# Generate a test console.log
echo ""
echo "4️⃣ Generating test console.log in pod..."
kubectl exec -n $NAMESPACE $POD_NAME -- sh -c 'echo "TEST-LOKI-CONSOLE-LOG-$(date +%s): This is a test console.log output" > /proc/1/fd/1' 2>/dev/null
if [ $? -eq 0 ]; then
  echo "   ✅ Test log sent to stdout"
else
  echo "   ⚠️  Could not send test log (pod might be down)"
fi

# Check Promtail logs for errors
echo ""
echo "5️⃣ Checking Promtail logs for errors..."
PROMTAIL_POD=$(kubectl get pods -n $LOKI_NAMESPACE -l app=promtail -o name 2>/dev/null | head -1)
if [ -n "$PROMTAIL_POD" ]; then
  PROMTAIL_NAME=$(echo $PROMTAIL_POD | cut -d'/' -f2)
  echo "   Checking pod: $PROMTAIL_NAME"
  kubectl logs -n $LOKI_NAMESPACE $PROMTAIL_NAME --tail=20 2>&1 | grep -i "error\|warn" | head -5
  if [ $? -ne 0 ]; then
    echo "   ✅ No errors found in Promtail logs"
  fi
else
  echo "   ⚠️  Promtail pod not found"
fi

# Check Loki logs
echo ""
echo "6️⃣ Checking Loki logs..."
LOKI_POD=$(kubectl get pods -n $LOKI_NAMESPACE -l app=loki -o name 2>/dev/null | head -1)
if [ -n "$LOKI_POD" ]; then
  LOKI_NAME=$(echo $LOKI_POD | cut -d'/' -f2)
  echo "   Checking pod: $LOKI_NAME"
  kubectl logs -n $LOKI_NAMESPACE $LOKI_NAME --tail=20 2>&1 | grep -i "error\|warn\|s3" | head -5
  if [ $? -ne 0 ]; then
    echo "   ✅ No errors found in Loki logs"
  fi
fi

# Instructions for Grafana
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 HOW TO VERIFY IN GRAFANA:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Open Grafana: kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
echo "2. Go to Explore → Select Loki datasource"
echo "3. Run these queries:"
echo ""
echo "   # All logs from namespace:"
echo "   {namespace=\"$NAMESPACE\"}"
echo ""
echo "   # Console.log outputs:"
echo "   {namespace=\"$NAMESPACE\"} |= \"console.log\""
echo ""
echo "   # Test log we just generated:"
echo "   {namespace=\"$NAMESPACE\"} |= \"TEST-LOKI-CONSOLE-LOG\""
echo ""
echo "   # All errors:"
echo "   {namespace=\"$NAMESPACE\"} |~ \"(?i)(error|err)\""
echo ""
echo "   # Specific pod:"
echo "   {namespace=\"$NAMESPACE\", pod=\"$POD_NAME\"}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

