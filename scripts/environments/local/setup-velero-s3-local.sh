#!/bin/bash
# =============================================================================
# SETUP VELERO S3 BACKEND (LOCAL TESTING)
# =============================================================================
# Creates S3 bucket with versioning for local Velero testing
# Uses separate bucket from production: vendure-velero-backups-local
#
# Usage:
#   ./helm/environments/local/setup-velero-s3-local.sh
# =============================================================================

set -e

BUCKET_NAME="vendure-velero-backups-local"
REGION="ap-south-1"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 SETTING UP VELERO S3 BACKEND (LOCAL TESTING)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Bucket: $BUCKET_NAME (separate from production)"
echo "Region: $REGION"
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  echo "❌ AWS credentials not configured"
  echo "   Configure AWS CLI: aws configure"
  echo "   Or set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
  exit 1
fi

echo "✅ AWS credentials configured"
echo ""

# Check if bucket already exists
if aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
  echo "⚠️  Bucket '$BUCKET_NAME' already exists"
  read -p "Continue with setup? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
else
  # Create S3 bucket
  echo "1️⃣ Creating S3 bucket..."
  aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
  echo "   ✅ Bucket created"
fi

# Enable versioning (CRITICAL for backup safety)
echo ""
echo "2️⃣ Enabling S3 versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled \
  --region "$REGION"
echo "   ✅ Versioning enabled"

# Enable encryption
echo ""
echo "3️⃣ Enabling S3 encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }' \
  --region "$REGION"
echo "   ✅ Encryption enabled"

# Block public access
echo ""
echo "4️⃣ Blocking public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --region "$REGION"
echo "   ✅ Public access blocked"

# Set lifecycle policy (move old versions to cheaper storage after 30 days)
echo ""
echo "5️⃣ Setting lifecycle policy (cost optimization)..."
cat > /tmp/velero-lifecycle-local.json <<EOF
{
  "Rules": [
    {
      "ID": "MoveOldVersionsToGlacier",
      "Status": "Enabled",
      "Filter": {},
      "NoncurrentVersionTransitions": [
        {
          "NoncurrentDays": 30,
          "StorageClass": "GLACIER"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    },
    {
      "ID": "DeleteOldBackups",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "backups/"
      },
      "Expiration": {
        "Days": 7
      }
    }
  ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET_NAME" \
  --lifecycle-configuration file:///tmp/velero-lifecycle-local.json \
  --region "$REGION"
rm /tmp/velero-lifecycle-local.json
echo "   ✅ Lifecycle policy set (old versions → Glacier after 30 days)"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ S3 BACKEND SETUP COMPLETE (LOCAL)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Summary:"
echo "   ✅ S3 Bucket: $BUCKET_NAME"
echo "   ✅ Versioning: Enabled"
echo "   ✅ Encryption: AES256"
echo "   ✅ Public Access: Blocked"
echo "   ✅ Lifecycle Policy: Enabled (Glacier after 30 days)"
echo ""
echo "📝 Next Steps:"
echo ""
echo "1. Verify AWS credentials are accessible from Kubernetes:"
echo "   (For local: AWS credentials from ~/.aws/credentials will be used)"
echo ""
echo "2. Install Velero:"
echo "   helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts"
echo "   helm repo update"
echo "   helm install velero vmware-tanzu/velero \\"
echo "     -n velero --create-namespace \\"
echo "     -f helm/environments/local/velero-values.yaml"
echo ""
echo "3. Verify installation:"
echo "   velero version"
echo "   velero backup get"
echo ""
echo "4. Test backup:"
echo "   velero backup create test-backup --include-namespaces vendure-local"
echo ""
echo "5. Verify S3 versioning:"
echo "   aws s3api get-bucket-versioning --bucket $BUCKET_NAME"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  NOTE: This is for LOCAL TESTING"
echo "   Production bucket: vendure-velero-backups"
echo "   Local bucket: vendure-velero-backups-local"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

