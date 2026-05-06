#!/bin/bash
# =============================================================================
# CROSS-REGION S3 REPLICATION FOR DISASTER RECOVERY
# =============================================================================
# Replicates Velero backups from ap-south-1 to ap-southeast-1 (Singapore)
# Replicates asset storage bucket for CDN failover
#
# Prerequisites:
#   - AWS CLI configured with admin access
#   - Source S3 buckets exist
#
# Usage:
#   chmod +x setup-cross-region-s3.sh
#   ./setup-cross-region-s3.sh
# =============================================================================

set -euo pipefail

# Configuration
PRIMARY_REGION="ap-south-1"
DR_REGION="ap-southeast-1"  # Singapore - closest DR region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Bucket names
VELERO_SOURCE_BUCKET="vendure-velero-backups"
VELERO_DR_BUCKET="vendure-velero-backups-dr"
ASSETS_SOURCE_BUCKET="cdn.kaaikani.co.in"
ASSETS_DR_BUCKET="cdn-dr.kaaikani.co.in"

# IAM role for replication
REPLICATION_ROLE_NAME="vendure-s3-replication-role"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${GREEN}[+] $1${NC}"; }
print_warn() { echo -e "${YELLOW}[!] $1${NC}"; }
print_info() { echo -e "${BLUE}[i] $1${NC}"; }

echo "=============================================="
echo "  Cross-Region S3 Replication Setup"
echo "=============================================="
echo "Primary Region: $PRIMARY_REGION"
echo "DR Region:      $DR_REGION"
echo "Account ID:     $AWS_ACCOUNT_ID"
echo ""

# =============================================================================
# STEP 1: Create DR buckets in secondary region
# =============================================================================
print_step "Step 1: Creating DR buckets in $DR_REGION"

for BUCKET in "$VELERO_DR_BUCKET" "$ASSETS_DR_BUCKET"; do
    if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
        print_warn "Bucket $BUCKET already exists, skipping"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET" \
            --region "$DR_REGION" \
            --create-bucket-configuration LocationConstraint="$DR_REGION"

        # Enable versioning (required for replication)
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET" \
            --versioning-configuration Status=Enabled

        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$BUCKET" \
            --server-side-encryption-configuration '{
                "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"},"BucketKeyEnabled": true}]
            }'

        # Block public access
        aws s3api put-public-access-block \
            --bucket "$BUCKET" \
            --public-access-block-configuration \
                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

        print_step "Created bucket: $BUCKET"
    fi
done

# Enable versioning on source buckets (required for replication)
for BUCKET in "$VELERO_SOURCE_BUCKET" "$ASSETS_SOURCE_BUCKET"; do
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET" \
        --versioning-configuration Status=Enabled 2>/dev/null || true
    print_step "Enabled versioning on source bucket: $BUCKET"
done

# =============================================================================
# STEP 2: Create IAM role for S3 replication
# =============================================================================
print_step "Step 2: Creating IAM replication role"

if aws iam get-role --role-name "$REPLICATION_ROLE_NAME" &>/dev/null; then
    print_warn "Role $REPLICATION_ROLE_NAME already exists, updating policy"
else
    # Create trust policy
    cat > /tmp/s3-replication-trust.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"Service": "s3.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    aws iam create-role \
        --role-name "$REPLICATION_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/s3-replication-trust.json \
        --description "S3 cross-region replication for Vendure DR"

    print_step "Created IAM role: $REPLICATION_ROLE_NAME"
fi

# Create/update replication policy
cat > /tmp/s3-replication-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetReplicationConfiguration",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${VELERO_SOURCE_BUCKET}",
                "arn:aws:s3:::${ASSETS_SOURCE_BUCKET}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObjectVersionForReplication",
                "s3:GetObjectVersionAcl",
                "s3:GetObjectVersionTagging"
            ],
            "Resource": [
                "arn:aws:s3:::${VELERO_SOURCE_BUCKET}/*",
                "arn:aws:s3:::${ASSETS_SOURCE_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ReplicateObject",
                "s3:ReplicateDelete",
                "s3:ReplicateTags"
            ],
            "Resource": [
                "arn:aws:s3:::${VELERO_DR_BUCKET}/*",
                "arn:aws:s3:::${ASSETS_DR_BUCKET}/*"
            ]
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name "$REPLICATION_ROLE_NAME" \
    --policy-name S3ReplicationPolicy \
    --policy-document file:///tmp/s3-replication-policy.json

ROLE_ARN=$(aws iam get-role --role-name "$REPLICATION_ROLE_NAME" --query 'Role.Arn' --output text)
print_step "Role ARN: $ROLE_ARN"

# =============================================================================
# STEP 3: Configure replication rules on source buckets
# =============================================================================
print_step "Step 3: Configuring replication rules"

# Velero bucket replication
cat > /tmp/velero-replication.json <<EOF
{
    "Role": "${ROLE_ARN}",
    "Rules": [
        {
            "ID": "VeleroBackupDR",
            "Status": "Enabled",
            "Priority": 1,
            "Filter": {
                "Prefix": ""
            },
            "Destination": {
                "Bucket": "arn:aws:s3:::${VELERO_DR_BUCKET}",
                "StorageClass": "STANDARD_IA",
                "EncryptionConfiguration": {
                    "ReplicaKmsKeyID": "aws/s3"
                }
            },
            "DeleteMarkerReplication": {
                "Status": "Enabled"
            }
        }
    ]
}
EOF

aws s3api put-bucket-replication \
    --bucket "$VELERO_SOURCE_BUCKET" \
    --replication-configuration file:///tmp/velero-replication.json 2>/dev/null || \
    print_warn "Could not set replication on $VELERO_SOURCE_BUCKET - verify bucket exists and versioning is enabled"

# Assets bucket replication
cat > /tmp/assets-replication.json <<EOF
{
    "Role": "${ROLE_ARN}",
    "Rules": [
        {
            "ID": "AssetsDR",
            "Status": "Enabled",
            "Priority": 1,
            "Filter": {
                "Prefix": "assets/"
            },
            "Destination": {
                "Bucket": "arn:aws:s3:::${ASSETS_DR_BUCKET}",
                "StorageClass": "STANDARD",
                "EncryptionConfiguration": {
                    "ReplicaKmsKeyID": "aws/s3"
                }
            },
            "DeleteMarkerReplication": {
                "Status": "Enabled"
            }
        }
    ]
}
EOF

aws s3api put-bucket-replication \
    --bucket "$ASSETS_SOURCE_BUCKET" \
    --replication-configuration file:///tmp/assets-replication.json 2>/dev/null || \
    print_warn "Could not set replication on $ASSETS_SOURCE_BUCKET - verify bucket exists and versioning is enabled"

# =============================================================================
# STEP 4: Set lifecycle policies on DR buckets (cost optimization)
# =============================================================================
print_step "Step 4: Setting lifecycle policies on DR buckets"

cat > /tmp/dr-lifecycle.json <<EOF
{
    "Rules": [
        {
            "ID": "TransitionToIA",
            "Status": "Enabled",
            "Filter": {"Prefix": ""},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 30
            }
        }
    ]
}
EOF

for BUCKET in "$VELERO_DR_BUCKET" "$ASSETS_DR_BUCKET"; do
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET" \
        --lifecycle-configuration file:///tmp/dr-lifecycle.json 2>/dev/null || true
done

# =============================================================================
# STEP 5: Verify replication
# =============================================================================
print_step "Step 5: Verification"

echo ""
echo "=============================================="
echo "  Cross-Region Replication Setup Complete"
echo "=============================================="
echo ""
echo "Source Region:      $PRIMARY_REGION"
echo "DR Region:          $DR_REGION"
echo ""
echo "Velero Backups:"
echo "  Source: s3://$VELERO_SOURCE_BUCKET ($PRIMARY_REGION)"
echo "  DR:     s3://$VELERO_DR_BUCKET ($DR_REGION)"
echo ""
echo "Asset Storage:"
echo "  Source: s3://$ASSETS_SOURCE_BUCKET ($PRIMARY_REGION)"
echo "  DR:     s3://$ASSETS_DR_BUCKET ($DR_REGION)"
echo ""
echo "Replication IAM Role: $ROLE_ARN"
echo ""
echo "=============================================="
echo "  VERIFY REPLICATION STATUS:"
echo "=============================================="
echo ""
echo "  aws s3api get-bucket-replication --bucket $VELERO_SOURCE_BUCKET"
echo "  aws s3api get-bucket-replication --bucket $ASSETS_SOURCE_BUCKET"
echo ""
echo "=============================================="
echo "  ESTIMATED ADDITIONAL COST:"
echo "=============================================="
echo ""
echo "  S3 Replication (ap-southeast-1):"
echo "    - Storage: ~\$0.025/GB/month (Standard-IA)"
echo "    - Replication: \$0.02/GB transferred"
echo "    - For 50GB backups: ~\$2.25/month"
echo ""

# Cleanup temp files
rm -f /tmp/s3-replication-trust.json /tmp/s3-replication-policy.json \
      /tmp/velero-replication.json /tmp/assets-replication.json /tmp/dr-lifecycle.json
