#!/bin/bash
# =============================================================================
# Quick Fix for ArgoCD Sync Delay
# =============================================================================
# This script provides immediate fixes for ArgoCD sync issues
# =============================================================================

set -e

echo "🔧 ArgoCD Sync Fix Script"
echo "================================"
echo ""
echo "Choose a fix:"
echo ""
echo "1) Reduce polling interval to 30 seconds (quick fix, no webhook needed)"
echo "2) Force manual sync for all applications (one-time sync)"
echo "3) Hard refresh applications (force ArgoCD to re-check Git)"
echo "4) Show current sync status"
echo "5) Exit"
echo ""
read -p "Enter your choice (1-5): " choice

case $choice in
  1)
    echo ""
    echo "📝 Reducing polling interval to 30 seconds..."
    echo ""

    # Check if argocd-cm exists
    if ! kubectl get configmap argocd-cm -n argocd &>/dev/null; then
      echo "Creating argocd-cm ConfigMap..."
      kubectl create configmap argocd-cm -n argocd
    fi

    # Update polling interval
    kubectl patch configmap argocd-cm -n argocd \
      --type merge \
      -p '{"data":{"timeout.reconciliation":"30s"}}'

    echo "✅ Polling interval updated to 30 seconds"
    echo ""
    echo "⚠️  Restarting ArgoCD components to apply changes..."
    kubectl rollout restart deployment argocd-repo-server -n argocd
    kubectl rollout restart deployment argocd-application-controller -n argocd

    echo ""
    echo "✅ Done! ArgoCD will now check Git every 30 seconds instead of 3 minutes"
    echo "   Note: This still uses polling. For instant sync, configure webhooks."
    echo "   See: helm/argocd/WEBHOOK-SETUP.md"
    ;;

  2)
    echo ""
    echo "🔄 Force syncing all applications..."
    echo ""

    for app in vendure-production vendure-test monitoring-stack karpenter; do
      if kubectl get application $app -n argocd &>/dev/null; then
        echo "   Syncing $app..."
        kubectl patch application $app -n argocd \
          --type merge \
          -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main","syncOptions":[]}}}'
        echo "   ✅ $app sync initiated"
      else
        echo "   ⏭️  $app not found, skipping"
      fi
    done

    echo ""
    echo "✅ All applications synced!"
    echo "   Check status with: kubectl get applications -n argocd"
    ;;

  3)
    echo ""
    echo "🔄 Hard refreshing all applications..."
    echo ""

    for app in vendure-production vendure-test monitoring-stack karpenter; do
      if kubectl get application $app -n argocd &>/dev/null; then
        echo "   Refreshing $app..."
        kubectl patch application $app -n argocd \
          --type merge \
          -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
        echo "   ✅ $app refreshed"
      else
        echo "   ⏭️  $app not found, skipping"
      fi
    done

    echo ""
    echo "✅ All applications hard refreshed!"
    echo "   ArgoCD will re-check Git repository immediately"
    ;;

  4)
    echo ""
    echo "📊 Current Sync Status:"
    echo "================================"
    kubectl get applications -n argocd
    echo ""
    echo "Detailed status:"
    echo "================================"
    for app in vendure-production vendure-test; do
      if kubectl get application $app -n argocd &>/dev/null; then
        echo ""
        echo "📦 $app:"
        SYNC_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.status}')
        HEALTH_STATUS=$(kubectl get application $app -n argocd -o jsonpath='{.status.health.status}')
        REVISION=$(kubectl get application $app -n argocd -o jsonpath='{.status.sync.revision}')
        DESIRED_REVISION=$(kubectl get application $app -n argocd -o jsonpath='{.spec.source.targetRevision}')

        echo "   Sync: $SYNC_STATUS"
        echo "   Health: $HEALTH_STATUS"
        echo "   Current Revision: ${REVISION:0:8}"
        echo "   Target Revision: $DESIRED_REVISION"
      fi
    done
    echo ""
    ;;

  5)
    echo "Exiting..."
    exit 0
    ;;

  *)
    echo "❌ Invalid choice"
    exit 1
    ;;
esac

echo ""
echo "================================"
echo "For permanent fix with webhooks:"
echo "cat helm/argocd/WEBHOOK-SETUP.md"
echo "================================"
