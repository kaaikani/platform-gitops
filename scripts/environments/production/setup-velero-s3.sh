#!/bin/bash
# =============================================================================
# SETUP VELERO S3 BACKEND
# =============================================================================
# Creates S3 bucket with versioning enabled for Velero backups
#
# Usage:
#   ./helm/environments/production/setup-velero-s3.sh
# =============================================================================

set -e

BUCKET_NAME="vendure-velero-backups"
REGION="ap-south-1"
CLUSTER_NAME="vendure-prod"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 SETTING UP VELERO S3 BACKEND"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Bucket: $BUCKET_NAME"
echo "Region: $REGION"
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
cat > /tmp/velero-lifecycle.json <<EOF
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
  --lifecycle-configuration file:///tmp/velero-lifecycle.json \
  --region "$REGION"
rm /tmp/velero-lifecycle.json
echo "   ✅ Lifecycle policy set (old versions → Glacier after 30 days)"

# Create IRSA for Velero
echo ""
echo "6️⃣ Creating IRSA for Velero..."
eksctl create iamserviceaccount \
  --name velero-server \
  --namespace velero \
  --cluster "$CLUSTER_NAME" \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEBSFullAccess \
  --approve \
  --override-existing-serviceaccounts

echo "   ✅ IRSA created"

# Get role ARN
ROLE_ARN=$(kubectl get serviceaccount velero-server -n velero -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")

if [ -z "$ROLE_ARN" ]; then
  echo "   ⚠️  Role ARN not found (namespace may not exist yet)"
  echo "   Create namespace first: kubectl create namespace velero"
else
  echo "   ✅ Role ARN: $ROLE_ARN"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ S3 BACKEND SETUP COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Summary:"
echo "   ✅ S3 Bucket: $BUCKET_NAME"
echo "   ✅ Versioning: Enabled"
echo "   ✅ Encryption: AES256"
echo "   ✅ Public Access: Blocked"
echo "   ✅ Lifecycle Policy: Enabled (Glacier after 30 days)"
echo "   ✅ IRSA: Created"
if [ -n "$ROLE_ARN" ]; then
  echo "   ✅ Role ARN: $ROLE_ARN"
fi
echo ""
echo "📝 Next Steps:"
echo ""
echo "1. Update velero-values.yaml with Role ARN:"
if [ -n "$ROLE_ARN" ]; then
  echo "   eks.amazonaws.com/role-arn: $ROLE_ARN"
else
  echo "   (Get it after creating namespace: kubectl get sa velero-server -n velero -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')"
fi
echo ""
echo "2. Install Velero:"
echo "   helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts"
echo "   helm repo update"
echo "   helm install velero vmware-tanzu/velero \\"
echo "     -n velero --create-namespace \\"
echo "     -f helm/environments/production/velero-values.yaml"
echo ""
echo "3. Verify installation:"
echo "   velero version"
echo "   velero backup get"
echo ""
echo "4. Verify S3 versioning:"
echo "   aws s3api get-bucket-versioning --bucket $BUCKET_NAME"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

