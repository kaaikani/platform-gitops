#!/bin/bash
# =============================================================================
# PRE-UPGRADE BACKUP SCRIPT
# =============================================================================
# Creates comprehensive backup before Kubernetes upgrade
#
# Usage:
#   ./helm/environments/production/backup-before-upgrade.sh
# =============================================================================

set -e

CLUSTER_NAME="vendure-prod"
REGION="ap-south-1"
BACKUP_DIR="./backups/pre-upgrade-$(date +%Y%m%d-%H%M%S)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 PRE-UPGRADE BACKUP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Backup directory: $BACKUP_DIR"
echo ""

mkdir -p "$BACKUP_DIR"

# 1. Kubernetes resources
echo "1️⃣ Backing up Kubernetes resources..."
kubectl get all -A -o yaml > "$BACKUP_DIR/all-resources.yaml"
kubectl get configmaps -A -o yaml > "$BACKUP_DIR/configmaps.yaml"
kubectl get secrets -A -o yaml > "$BACKUP_DIR/secrets.yaml"
kubectl get pvc -A -o yaml > "$BACKUP_DIR/persistentvolumeclaims.yaml"
echo "   ✅ Kubernetes resources backed up"

# 2. Helm releases
echo ""
echo "2️⃣ Backing up Helm releases..."
helm list -A -o json > "$BACKUP_DIR/helm-releases.json"
echo "   ✅ Helm releases backed up"

# 3. Velero backup (if available)
echo ""
echo "3️⃣ Creating Velero backup..."
if kubectl get deployment velero -n velero &>/dev/null; then
    if command -v velero &>/dev/null; then
        BACKUP_NAME="pre-upgrade-$(date +%Y%m%d-%H%M%S)"
        velero backup create "$BACKUP_NAME" \
            --include-namespaces vendure-production,monitoring,kubecost \
            --wait
        echo "   ✅ Velero backup created: $BACKUP_NAME"
    else
        echo "   ⚠️  Velero CLI not found, skipping"
    fi
else
    echo "   ⚠️  Velero not installed, skipping"
fi

# 4. Cluster information
echo ""
echo "4️⃣ Backing up cluster information..."
aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" > "$BACKUP_DIR/cluster-info.json"
kubectl version -o json > "$BACKUP_DIR/kubectl-version.json"
kubectl get nodes -o yaml > "$BACKUP_DIR/nodes.yaml"
echo "   ✅ Cluster information backed up"

# 5. Node group information
echo ""
echo "5️⃣ Backing up node group information..."
eksctl get nodegroup --cluster="$CLUSTER_NAME" -o json > "$BACKUP_DIR/nodegroups.json" 2>/dev/null || echo "[]" > "$BACKUP_DIR/nodegroups.json"
echo "   ✅ Node group information backed up"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ BACKUP COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
ls -lh "$BACKUP_DIR"
echo ""

