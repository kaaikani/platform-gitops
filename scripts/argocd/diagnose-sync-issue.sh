#!/bin/bash
# =============================================================================
# ArgoCD Sync Diagnostic Script
# =============================================================================
# This script diagnoses why ArgoCD is not syncing after GitHub pipeline pushes
# =============================================================================

set -e

echo "🔍 ArgoCD Sync Diagnostics"
echo "================================"
echo ""

# Check if ArgoCD is installed
echo "1️⃣  Checking if ArgoCD is installed..."
if kubectl get namespace argocd &>/dev/null; then
  echo "   ✅ ArgoCD namespace exists"
else
  echo "   ❌ ArgoCD namespace not found. Install ArgoCD first!"
  exit 1
fi

# Check ArgoCD pods
echo ""
echo "2️⃣  Checking ArgoCD pod status..."
kubectl get pods -n argocd
echo ""

# Check if applications exist
echo "3️⃣  Checking ArgoCD applications..."
if kubectl get applications -n argocd &>/dev/null; then
  kubectl get applications -n argocd
else
  echo "   ❌ No applications found. Deploy app-of-apps.yaml first!"
  exit 1
fi
echo ""

# Check sync status for each app
echo "4️⃣  Checking sync status..."
for app in vendure-production vendure-test; do
  if kubectl get application $app -n argocd &>/dev/null; then
    echo "   📦 $app:"
    SYNC_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    REVISION=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null || echo "Unknown")

    echo "      Sync: $SYNC_STATUS"
    echo "      Health: $HEALTH_STATUS"
    echo "      Revision: $REVISION"
  fi
done
echo ""

# Check repository configuration
echo "5️⃣  Checking repository access..."
REPO_URL=$(kubectl get application vendure-production -n argocd -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || echo "Not found")
echo "   Repository: $REPO_URL"

# Check if repo credentials exist
echo ""
echo "6️⃣  Checking repository credentials..."
if kubectl get secrets -n argocd | grep -q "repo-"; then
  echo "   ✅ Repository credentials found:"
  kubectl get secrets -n argocd | grep "repo-" | awk '{print "      - " $1}'
else
  echo "   ⚠️  No repository credentials found"
  echo "      If your repo is private, you need to configure credentials!"
fi
echo ""

# Check argocd-cm for webhook and polling config
echo "7️⃣  Checking ArgoCD configuration..."
echo "   Polling interval:"
RECONCILIATION_TIMEOUT=$(kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.timeout\.reconciliation}' 2>/dev/null || echo "Default (3m)")
echo "      $RECONCILIATION_TIMEOUT"

echo ""
echo "   Webhook configuration:"
WEBHOOK_SECRET=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.webhook\.github\.secret}' 2>/dev/null || echo "Not configured")
if [ "$WEBHOOK_SECRET" = "Not configured" ]; then
  echo "      ❌ No webhook secret configured"
  echo "      → ArgoCD is using POLLING mode (3-minute delay)"
else
  echo "      ✅ Webhook secret exists"
fi
echo ""

# Check recent sync operations
echo "8️⃣  Checking recent sync operations..."
for app in vendure-production vendure-test; do
  if kubectl get application $app -n argocd &>/dev/null; then
    echo "   📦 $app - Last sync operation:"
    LAST_SYNC=$(kubectl get application $app -n argocd -o jsonpath='{.status.operationState.finishedAt}' 2>/dev/null || echo "Never")
    echo "      Finished: $LAST_SYNC"
  fi
done
echo ""

# Check application controller logs for errors
echo "9️⃣  Checking for sync errors in logs (last 20 lines)..."
kubectl logs -n argocd deployment/argocd-application-controller --tail=20 | grep -i "error\|failed\|unable" || echo "   ✅ No recent errors found"
echo ""

# Summary and recommendations
echo "================================"
echo "📊 Summary & Recommendations:"
echo "================================"
echo ""

# Check if webhook is configured
if [ "$WEBHOOK_SECRET" = "Not configured" ]; then
  echo "⚠️  ISSUE: No webhook configured"
  echo "   → ArgoCD polls GitHub every $RECONCILIATION_TIMEOUT"
  echo "   → Changes take 3 minutes to sync by default"
  echo ""
  echo "   ✅ SOLUTION:"
  echo "      1. Configure GitHub webhook (instant sync)"
  echo "         See: helm/argocd/WEBHOOK-SETUP.md"
  echo ""
  echo "      2. OR reduce polling interval:"
  echo "         kubectl patch configmap argocd-cm -n argocd \\"
  echo "           --type merge -p '{\"data\":{\"timeout.reconciliation\":\"30s\"}}'"
  echo "         kubectl rollout restart deployment argocd-application-controller -n argocd"
fi

# Check if apps are out of sync
for app in vendure-production vendure-test; do
  if kubectl get application $app -n argocd &>/dev/null; then
    SYNC_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    if [ "$SYNC_STATUS" != "Synced" ]; then
      echo ""
      echo "⚠️  ISSUE: $app is $SYNC_STATUS"
      echo "   → Manually sync the application:"
      echo "      kubectl patch application $app -n argocd \\"
      echo "        --type merge -p '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}'"
    fi
  fi
done

# Check repository access
if [ "$REPO_URL" = "Not found" ]; then
  echo ""
  echo "❌ ISSUE: Application not found"
  echo "   → Deploy the app-of-apps.yaml first:"
  echo "      kubectl apply -f helm/argocd/app-of-apps.yaml"
fi

echo ""
echo "================================"
echo "For detailed webhook setup instructions:"
echo "cat helm/argocd/WEBHOOK-SETUP.md"
echo "================================"
