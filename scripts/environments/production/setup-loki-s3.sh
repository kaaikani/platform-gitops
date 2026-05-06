#!/bin/bash
# =============================================================================
# LOKI S3 STORAGE SETUP SCRIPT
# =============================================================================
# This script sets up S3 storage for Loki logs
# Saves 71% on storage costs vs EBS ($0.023/GB vs $0.08/GB)
#
# What it does:
#   1. Creates S3 bucket for Loki logs
#   2. Creates IAM role for Loki (IRSA)
#   3. Configures bucket lifecycle (auto-delete old logs)
#   4. Shows you how to deploy Loki with S3
#
# Usage: ./setup-loki-s3.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AWS_REGION="ap-south-1"
AWS_ACCOUNT_ID="149536454380"
CLUSTER_NAME="vendure-prod"
BUCKET_NAME="vendure-loki-logs"
NAMESPACE="monitoring"
SERVICE_ACCOUNT_NAME="loki"

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_step() { echo -e "${GREEN}▶ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# =============================================================================
# STEP 1: Create S3 Bucket
# =============================================================================
create_s3_bucket() {
    print_header "Step 1: Creating S3 Bucket for Loki Logs"

    # Check if bucket already exists
    if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
        print_warning "Bucket ${BUCKET_NAME} already exists. Skipping creation..."
    else
        print_step "Creating S3 bucket: ${BUCKET_NAME}"
        
        aws s3 mb "s3://${BUCKET_NAME}" \
            --region "${AWS_REGION}"
        
        print_step "Bucket created successfully!"
    fi

    # Enable versioning (optional, for safety)
    print_step "Enabling versioning on bucket..."
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled \
        --region "${AWS_REGION}"

    # Enable encryption
    print_step "Enabling encryption on bucket..."
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }' \
        --region "${AWS_REGION}"

    # Set lifecycle policy (auto-delete logs older than 7 days)
    print_step "Setting lifecycle policy (auto-delete after 7 days)..."
    cat > /tmp/loki-lifecycle.json << EOF
{
    "Rules": [
        {
            "Id": "DeleteOldLogs",
            "Status": "Enabled",
            "Expiration": {
                "Days": 7
            },
            "Filter": {
                "Prefix": ""
            }
        }
    ]
}
EOF

    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${BUCKET_NAME}" \
        --lifecycle-configuration file:///tmp/loki-lifecycle.json \
        --region "${AWS_REGION}"

    rm -f /tmp/loki-lifecycle.json

    print_step "S3 bucket configured successfully!"
    echo ""
    echo "Bucket: s3://${BUCKET_NAME}"
    echo "Region: ${AWS_REGION}"
    echo "Encryption: Enabled (AES256)"
    echo "Lifecycle: Auto-delete after 7 days"
}

# =============================================================================
# STEP 2: Create IAM Policy for S3 Access
# =============================================================================
create_iam_policy() {
    print_header "Step 2: Creating IAM Policy for S3 Access"

    # Create policy document
    cat > /tmp/loki-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF

    # Check if policy exists
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LokiS3Access"
    if aws iam get-policy --policy-arn "${POLICY_ARN}" 2>/dev/null; then
        print_warning "Policy LokiS3Access already exists. Updating..."
        aws iam create-policy-version \
            --policy-arn "${POLICY_ARN}" \
            --policy-document file:///tmp/loki-s3-policy.json \
            --set-as-default
    else
        print_step "Creating IAM policy: LokiS3Access"
        aws iam create-policy \
            --policy-name LokiS3Access \
            --policy-document file:///tmp/loki-s3-policy.json \
            --description "Allows Loki to read/write logs to S3 bucket"
        
        print_step "Policy created: ${POLICY_ARN}"
    fi

    rm -f /tmp/loki-s3-policy.json
}

# =============================================================================
# STEP 3: Create IAM Role for Service Account (IRSA)
# =============================================================================
create_irsa() {
    print_header "Step 3: Creating IAM Role for Service Account (IRSA)"

    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LokiS3Access"

    print_step "Creating service account with IRSA..."
    
    eksctl create iamserviceaccount \
        --name "${SERVICE_ACCOUNT_NAME}" \
        --namespace "${NAMESPACE}" \
        --cluster "${CLUSTER_NAME}" \
        --attach-policy-arn "${POLICY_ARN}" \
        --approve \
        --override-existing-serviceaccounts

    print_step "IRSA created successfully!"
    
    # Get the role ARN
    ROLE_ARN=$(aws iam list-roles --query "Roles[?RoleName=='eksctl-${CLUSTER_NAME}-addon-iamserviceac-Role1'].Arn" --output text 2>/dev/null || \
               kubectl get serviceaccount "${SERVICE_ACCOUNT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || \
               echo "arn:aws:iam::${AWS_ACCOUNT_ID}:role/eksctl-${CLUSTER_NAME}-addon-iamserviceac-Role1")
    
    echo ""
    echo "Service Account: ${SERVICE_ACCOUNT_NAME}"
    echo "Namespace: ${NAMESPACE}"
    echo "IAM Role ARN: ${ROLE_ARN}"
}

# =============================================================================
# STEP 4: Verify Setup
# =============================================================================
verify_setup() {
    print_header "Step 4: Verifying Setup"

    # Check bucket exists
    if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
        print_step "✅ S3 bucket exists"
    else
        print_error "❌ S3 bucket not found"
        return 1
    fi

    # Check service account exists
    if kubectl get serviceaccount "${SERVICE_ACCOUNT_NAME}" -n "${NAMESPACE}" 2>/dev/null; then
        print_step "✅ Service account exists"
    else
        print_error "❌ Service account not found"
        return 1
    fi

    # Check IRSA annotation
    ROLE_ARN=$(kubectl get serviceaccount "${SERVICE_ACCOUNT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
    if [ -n "${ROLE_ARN}" ]; then
        print_step "✅ IRSA configured: ${ROLE_ARN}"
    else
        print_error "❌ IRSA not configured"
        return 1
    fi

    print_step "✅ All checks passed!"
}

# =============================================================================
# MAIN
# =============================================================================

print_header "Loki S3 Storage Setup"

echo ""
echo "This script will:"
echo "  1. Create S3 bucket: ${BUCKET_NAME}"
echo "  2. Create IAM policy for S3 access"
echo "  3. Create IRSA (IAM Role for Service Account)"
echo "  4. Verify setup"
echo ""
echo "Cost Savings:"
echo "  Before: EBS storage = \$0.08/GB/month"
echo "  After:  S3 storage = \$0.023/GB/month (71% cheaper!)"
echo ""

read -p "Continue? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Check prerequisites
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install it first."
    exit 1
fi

if ! command -v eksctl &> /dev/null; then
    print_error "eksctl not found. Please install it first."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    print_error "AWS credentials not configured."
    exit 1
fi

# Check cluster exists
if ! aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
    print_error "EKS cluster '${CLUSTER_NAME}' not found."
    exit 1
fi

# Create namespace if not exists
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Run setup steps
create_s3_bucket
create_iam_policy
create_irsa
verify_setup

# =============================================================================
# DEPLOYMENT INSTRUCTIONS
# =============================================================================
print_header "Setup Complete!"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NEXT STEPS: Deploy Loki with S3 Storage"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Update loki-s3-storage.yaml with your bucket name:"
echo "   (Already configured: ${BUCKET_NAME})"
echo ""
echo "2. Deploy Loki with S3:"
echo ""
echo "   helm repo add grafana https://grafana.github.io/helm-charts"
echo "   helm repo update"
echo ""
echo "   helm upgrade --install loki grafana/loki-stack \\"
echo "     -n ${NAMESPACE} \\"
echo "     -f helm/environments/production/loki-s3-storage.yaml"
echo ""
echo "3. Verify Loki is using S3:"
echo ""
echo "   kubectl logs -n ${NAMESPACE} deployment/loki | grep -i s3"
echo ""
echo "4. Check S3 bucket has logs:"
echo ""
echo "   aws s3 ls s3://${BUCKET_NAME}/"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "COST SAVINGS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Before (EBS): 10 Gi × \$0.08 = \$0.80/month"
echo "After (S3):   10 Gi × \$0.023 = \$0.23/month"
echo "Savings: \$0.57/month (71% reduction)"
echo ""
echo "Annual Savings: \$6.84/year"
echo ""

