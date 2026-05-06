#!/bin/bash
# =============================================================================
# VERIFY VELERO BACKUP SETUP
# =============================================================================
# Verifies that Velero is properly configured and backups are working
#
# Usage:
#   ./helm/environments/production/verify-velero-backup.sh
# =============================================================================

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 VERIFYING VELERO BACKUP SETUP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if Velero CLI is installed
if ! command -v velero &> /dev/null; then
  echo "⚠️  Velero CLI not found. Install it:"
  echo "   https://velero.io/docs/main/basic-install/#install-the-cli"
  echo ""
  read -p "Continue with server-side checks only? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
  VELERO_CLI=false
else
  VELERO_CLI=true
fi

# Check Velero namespace
echo "1️⃣ Checking Velero namespace..."
if kubectl get namespace velero &>/dev/null; then
  echo "   ✅ Namespace exists"
else
  echo "   ❌ Namespace 'velero' not found"
  echo "   Create it: kubectl create namespace velero"
  exit 1
fi

# Check Velero deployment
echo ""
echo "2️⃣ Checking Velero deployment..."
VELERO_POD=$(kubectl get pods -n velero -l component=velero -o name 2>/dev/null | head -1)
if [ -z "$VELERO_POD" ]; then
  echo "   ❌ Velero pod not found"
  echo "   Install Velero first:"
  echo "   helm install velero vmware-tanzu/velero \\"
  echo "     -n velero \\"
  echo "     -f helm/environments/production/velero-values.yaml"
  exit 1
fi

VELERO_NAME=$(echo $VELERO_POD | cut -d'/' -f2)
VELERO_STATUS=$(kubectl get pod -n velero $VELERO_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
echo "   Pod: $VELERO_NAME (Status: $VELERO_STATUS)"

if [ "$VELERO_STATUS" != "Running" ]; then
  echo "   ⚠️  Velero pod is not Running"
  echo "   Check logs: kubectl logs -n velero $VELERO_NAME"
else
  echo "   ✅ Velero is running"
fi

# Check service account and IRSA
echo ""
echo "3️⃣ Checking service account and IRSA..."
SA_ROLE=$(kubectl get serviceaccount velero-server -n velero -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
if [ -z "$SA_ROLE" ]; then
  echo "   ⚠️  IRSA not configured"
  echo "   Set it up: ./helm/environments/production/setup-velero-s3.sh"
else
  echo "   ✅ IRSA configured: $SA_ROLE"
fi

# Check S3 bucket
echo ""
echo "4️⃣ Checking S3 bucket..."
BUCKET_NAME="vendure-velero-backups"
if aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
  echo "   ✅ Bucket exists: $BUCKET_NAME"
  
  # Check versioning
  VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --query 'Status' --output text 2>/dev/null || echo "NotEnabled")
  if [ "$VERSIONING" == "Enabled" ]; then
    echo "   ✅ Versioning: Enabled"
  else
    echo "   ❌ Versioning: Not enabled"
    echo "   Enable it: aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled"
  fi
  
  # Check encryption
  ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "$BUCKET_NAME" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null || echo "None")
  if [ "$ENCRYPTION" == "AES256" ] || [ "$ENCRYPTION" == "aws:kms" ]; then
    echo "   ✅ Encryption: $ENCRYPTION"
  else
    echo "   ⚠️  Encryption: Not configured"
  fi
else
  echo "   ❌ Bucket not found: $BUCKET_NAME"
  echo "   Create it: ./helm/environments/production/setup-velero-s3.sh"
fi

# Check backup schedule
echo ""
echo "5️⃣ Checking backup schedule..."
if [ "$VELERO_CLI" == "true" ]; then
  SCHEDULE=$(velero schedule get daily-backup -n velero 2>/dev/null || echo "")
  if [ -n "$SCHEDULE" ]; then
    echo "   ✅ Schedule 'daily-backup' exists"
    velero schedule get daily-backup -n velero
  else
    echo "   ⚠️  Schedule 'daily-backup' not found"
    echo "   It should be created automatically by Helm chart"
  fi
else
  SCHEDULE_CR=$(kubectl get schedule daily-backup -n velero 2>/dev/null || echo "")
  if [ -n "$SCHEDULE_CR" ]; then
    echo "   ✅ Schedule 'daily-backup' exists"
    kubectl get schedule daily-backup -n velero -o yaml | grep -A 5 "spec:"
  else
    echo "   ⚠️  Schedule 'daily-backup' not found"
  fi
fi

# Check recent backups
echo ""
echo "6️⃣ Checking recent backups..."
if [ "$VELERO_CLI" == "true" ]; then
  BACKUPS=$(velero backup get -n velero 2>/dev/null | head -10 || echo "")
  if [ -n "$BACKUPS" ]; then
    echo "   Recent backups:"
    velero backup get -n velero | head -10
  else
    echo "   ⚠️  No backups found yet"
    echo "   Wait for scheduled backup or create test backup:"
    echo "   velero backup create test-backup --include-namespaces vendure-production"
  fi
else
  BACKUPS=$(kubectl get backups -n velero 2>/dev/null | head -10 || echo "")
  if [ -n "$BACKUPS" ]; then
    echo "   Recent backups:"
    kubectl get backups -n velero | head -10
  else
    echo "   ⚠️  No backups found yet"
  fi
fi

# Check S3 backup files
echo ""
echo "7️⃣ Checking S3 backup files..."
S3_BACKUPS=$(aws s3 ls "s3://$BUCKET_NAME/backups/" 2>/dev/null | head -5 || echo "")
if [ -n "$S3_BACKUPS" ]; then
  echo "   ✅ Backups found in S3:"
  aws s3 ls "s3://$BUCKET_NAME/backups/" | head -5
else
  echo "   ⚠️  No backup files in S3 yet"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Configuration:"
echo "   - Schedule: Daily at 2 AM UTC (7:30 AM IST)"
echo "   - Retention: 7 days"
echo "   - Compression: Enabled (automatic)"
echo "   - S3 Versioning: Check status above"
echo ""
echo "📝 Useful Commands:"
echo ""
echo "   # View all backups:"
echo "   velero backup get"
echo ""
echo "   # View backup schedule:"
echo "   velero schedule get daily-backup"
echo ""
echo "   # Create manual backup:"
echo "   velero backup create manual-backup --include-namespaces vendure-production"
echo ""
echo "   # Restore from backup:"
echo "   velero restore create --from-backup <backup-name>"
echo ""
echo "   # Check S3 backups:"
echo "   aws s3 ls s3://vendure-velero-backups/backups/"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

