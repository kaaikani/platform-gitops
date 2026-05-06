#!/bin/bash
# =============================================================================
# EKS Production Hardening — Control Plane Logging + Secrets Encryption
# =============================================================================
# Enables:
#   1. EKS control plane logging (API, Audit, Authenticator)
#   2. KMS envelope encryption for Kubernetes secrets in etcd
#
# Prerequisites:
#   - AWS CLI v2 configured with cluster admin permissions
#   - KMS key created (or use aws/eks default)
#
# Usage:
#   chmod +x eks-enable-logging-encryption.sh
#   ./eks-enable-logging-encryption.sh
#
# Cost:
#   - CloudWatch Logs: ~$0.50/GB ingested (typically $5-15/month)
#   - KMS: $1/month per key + $0.03 per 10,000 API calls
# =============================================================================

CLUSTER_NAME="vendure-test"
REGION="ap-south-1"
ACCOUNT_ID="149536454380"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  EKS Production Hardening${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# =============================================================================
# Step 1: Enable EKS Control Plane Logging
# =============================================================================
echo -e "${YELLOW}[1/3] Enabling EKS control plane logging...${NC}"
echo "  Enabling: api, audit, authenticator"
echo "  (scheduler and controllerManager not accessible in EKS managed)"

aws eks update-cluster-config \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --logging '{
        "clusterLogging": [
            {
                "types": ["api", "audit", "authenticator"],
                "enabled": true
            },
            {
                "types": ["scheduler", "controllerManager"],
                "enabled": false
            }
        ]
    }' 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ✓ Control plane logging enabled${NC}"
    echo "  Logs available at: CloudWatch → Log Groups → /aws/eks/${CLUSTER_NAME}/cluster"
else
    echo -e "${RED}  ERROR: Failed to enable logging. Check IAM permissions.${NC}"
fi

# =============================================================================
# Step 2: Create KMS Key for Secrets Encryption
# =============================================================================
echo ""
echo -e "${YELLOW}[2/3] Setting up KMS encryption for Kubernetes secrets...${NC}"

# Check if KMS key already exists
KMS_ALIAS="alias/eks-${CLUSTER_NAME}-secrets"
EXISTING_KEY=$(aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" 2>/dev/null | grep -o '"KeyId": "[^"]*"' | cut -d'"' -f4)

if [ -n "$EXISTING_KEY" ]; then
    echo -e "${GREEN}  ✓ KMS key already exists: $EXISTING_KEY${NC}"
    KMS_KEY_ARN="arn:aws:kms:${REGION}:${ACCOUNT_ID}:key/${EXISTING_KEY}"
else
    echo "  Creating new KMS key..."
    KMS_KEY_ID=$(aws kms create-key \
        --region "$REGION" \
        --description "EKS ${CLUSTER_NAME} secrets encryption" \
        --tags TagKey=Project,TagValue=vendure TagKey=Environment,TagValue=production TagKey=ManagedBy,TagValue=eks \
        --query 'KeyMetadata.KeyId' \
        --output text 2>&1)

    if [ $? -eq 0 ] && [ -n "$KMS_KEY_ID" ]; then
        echo -e "${GREEN}  ✓ KMS key created: $KMS_KEY_ID${NC}"
        KMS_KEY_ARN="arn:aws:kms:${REGION}:${ACCOUNT_ID}:key/${KMS_KEY_ID}"

        # Create alias for easy reference
        aws kms create-alias \
            --alias-name "$KMS_ALIAS" \
            --target-key-id "$KMS_KEY_ID" \
            --region "$REGION" 2>/dev/null
        echo -e "${GREEN}  ✓ KMS alias created: $KMS_ALIAS${NC}"
    else
        echo -e "${RED}  ERROR: Failed to create KMS key: $KMS_KEY_ID${NC}"
        echo "  You can create it manually and re-run this script."
        exit 1
    fi
fi

# =============================================================================
# Step 3: Associate Encryption Config with EKS Cluster
# =============================================================================
echo ""
echo -e "${YELLOW}[3/3] Associating encryption config with EKS cluster...${NC}"

aws eks associate-encryption-config \
    --cluster-name "$CLUSTER_NAME" \
    --region "$REGION" \
    --encryption-config "[{
        \"resources\": [\"secrets\"],
        \"provider\": {
            \"keyArn\": \"${KMS_KEY_ARN}\"
        }
    }]" 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ✓ Encryption config associated${NC}"
    echo "  Note: Existing secrets will be encrypted on next update."
    echo "  To encrypt all existing secrets, run:"
    echo "    kubectl get secrets -A -o json | kubectl replace -f -"
else
    echo -e "${YELLOW}  WARNING: Association may have failed or already exists.${NC}"
    echo "  Check: aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.encryptionConfig'"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Hardening Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Enabled:"
echo "  [x] Control plane logging (api, audit, authenticator)"
echo "  [x] KMS secrets encryption (${KMS_KEY_ARN:-pending})"
echo ""
echo "Verify:"
echo "  aws eks describe-cluster --name $CLUSTER_NAME --region $REGION \\"
echo "    --query '{logging: cluster.logging, encryption: cluster.encryptionConfig}'"
echo ""
echo "CloudWatch Logs:"
echo "  https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#logsV2:log-groups/log-group/\$252Faws\$252Feks\$252F${CLUSTER_NAME}\$252Fcluster"
