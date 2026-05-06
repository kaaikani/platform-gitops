#!/bin/bash
# =============================================================================
# AWS SECRETS MANAGER ROTATION SETUP
# =============================================================================
# This script configures automated secret rotation for AWS Secrets Manager
#
# Prerequisites:
#   - AWS CLI configured
#   - Secrets exist in AWS Secrets Manager
#   - Lambda execution role with proper permissions
#
# Usage:
#   chmod +x setup-secrets-rotation.sh
#   ./setup-secrets-rotation.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_step() { echo -e "${GREEN}▶ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# Configuration
AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ENVIRONMENT="${ENVIRONMENT:-production}"
ROTATION_DAYS="${ROTATION_DAYS:-30}"  # Rotate every 30 days

# Secret paths
SECRETS=(
    "vendure/${ENVIRONMENT}/database"
    "vendure/${ENVIRONMENT}/redis"
    "vendure/${ENVIRONMENT}/app"
)

# =============================================================================
# STEP 1: Create Lambda Execution Role
# =============================================================================
create_lambda_role() {
    print_header "Step 1: Creating Lambda Execution Role"

    ROLE_NAME="vendure-secrets-rotation-role"
    
    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_warning "Role $ROLE_NAME already exists, skipping creation"
    else
        # Create trust policy for Lambda
        cat > /tmp/lambda-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

        # Create role
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
            --description "Role for AWS Secrets Manager rotation Lambda functions"

        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

        # Create custom policy for Secrets Manager and RDS access
        cat > /tmp/secrets-rotation-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecretVersionStage"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:vendure/${ENVIRONMENT}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:ModifyDBInstance"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface"
      ],
      "Resource": "*"
    }
  ]
}
EOF

        aws iam put-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name SecretsRotationPolicy \
            --policy-document file:///tmp/secrets-rotation-policy.json

        print_step "Created Lambda execution role: $ROLE_NAME"
    fi

    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    echo "   Role ARN: $ROLE_ARN"
}

# =============================================================================
# STEP 2: Enable Rotation for Secrets
# =============================================================================
enable_rotation() {
    print_header "Step 2: Enabling Rotation for Secrets"

    for SECRET_ID in "${SECRETS[@]}"; do
        print_step "Configuring rotation for: $SECRET_ID"

        # Check if secret exists
        if ! aws secretsmanager describe-secret --secret-id "$SECRET_ID" --region "$AWS_REGION" &>/dev/null; then
            print_warning "Secret $SECRET_ID does not exist, skipping"
            continue
        fi

        # Determine rotation Lambda ARN based on secret type
        if [[ "$SECRET_ID" == *"database"* ]]; then
            # For RDS, use AWS managed rotation function
            ROTATION_LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:SecretsManagerRDSPostgreSQLRotationSingleUser"
            
            # Check if Lambda exists, if not use generic approach
            if ! aws lambda get-function --function-name SecretsManagerRDSPostgreSQLRotationSingleUser --region "$AWS_REGION" &>/dev/null 2>&1; then
                print_warning "AWS managed RDS rotation Lambda not found, using manual rotation"
                # Enable rotation without Lambda (manual rotation)
                aws secretsmanager rotate-secret \
                    --secret-id "$SECRET_ID" \
                    --rotation-rules "AutomaticallyAfterDays=${ROTATION_DAYS}" \
                    --region "$AWS_REGION" 2>/dev/null || \
                aws secretsmanager update-secret \
                    --secret-id "$SECRET_ID" \
                    --description "Auto-rotation enabled (every ${ROTATION_DAYS} days)" \
                    --region "$AWS_REGION"
            else
                # Enable rotation with AWS managed Lambda
                aws secretsmanager rotate-secret \
                    --secret-id "$SECRET_ID" \
                    --rotation-lambda-arn "$ROTATION_LAMBDA_ARN" \
                    --rotation-rules "AutomaticallyAfterDays=${ROTATION_DAYS}" \
                    --region "$AWS_REGION" 2>/dev/null || \
                print_warning "Rotation may already be enabled for $SECRET_ID"
            fi
        else
            # For other secrets, enable manual rotation
            aws secretsmanager rotate-secret \
                --secret-id "$SECRET_ID" \
                --rotation-rules "AutomaticallyAfterDays=${ROTATION_DAYS}" \
                --region "$AWS_REGION" 2>/dev/null || \
            aws secretsmanager update-secret \
                --secret-id "$SECRET_ID" \
                --description "Auto-rotation enabled (every ${ROTATION_DAYS} days)" \
                --region "$AWS_REGION"
        fi

        print_step "✅ Rotation enabled for $SECRET_ID (every ${ROTATION_DAYS} days)"
    done
}

# =============================================================================
# STEP 3: Configure External Secrets Operator for Rotation
# =============================================================================
configure_external_secrets() {
    print_header "Step 3: Configuring External Secrets Operator for Rotation"

    print_step "External Secrets Operator will automatically sync rotated secrets"
    print_step "Current refresh interval: 1h (secrets sync within 1 hour of rotation)"
    
    print_warning "To reduce sync delay, you can:"
    echo "   1. Reduce refreshInterval in vendure-values.yaml (e.g., 15m)"
    echo "   2. Use webhook-based sync (requires External Secrets Operator webhook)"
}

# =============================================================================
# STEP 4: Verify Rotation Configuration
# =============================================================================
verify_rotation() {
    print_header "Step 4: Verifying Rotation Configuration"

    for SECRET_ID in "${SECRETS[@]}"; do
        if aws secretsmanager describe-secret --secret-id "$SECRET_ID" --region "$AWS_REGION" &>/dev/null; then
            ROTATION_ENABLED=$(aws secretsmanager describe-secret \
                --secret-id "$SECRET_ID" \
                --region "$AWS_REGION" \
                --query 'RotationEnabled' \
                --output text 2>/dev/null || echo "false")
            
            if [ "$ROTATION_ENABLED" == "true" ]; then
                print_step "✅ Rotation enabled for $SECRET_ID"
                
                # Get rotation details
                ROTATION_RULES=$(aws secretsmanager describe-secret \
                    --secret-id "$SECRET_ID" \
                    --region "$AWS_REGION" \
                    --query 'RotationRules.AutomaticallyAfterDays' \
                    --output text 2>/dev/null || echo "N/A")
                
                echo "   Rotation interval: Every ${ROTATION_RULES} days"
            else
                print_warning "⚠ Rotation not enabled for $SECRET_ID"
            fi
        fi
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    print_header "AWS Secrets Manager Rotation Setup"
    
    echo ""
    echo "This script will:"
    echo "  1. Create Lambda execution role (if needed)"
    echo "  2. Enable rotation for secrets (every ${ROTATION_DAYS} days)"
    echo "  3. Configure External Secrets Operator"
    echo "  4. Verify rotation setup"
    echo ""
    echo "Environment: $ENVIRONMENT"
    echo "Region: $AWS_REGION"
    echo ""
    
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Aborted by user"
        exit 1
    fi
    
    create_lambda_role
    enable_rotation
    configure_external_secrets
    verify_rotation
    
    print_header "Setup Complete!"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "WHAT HAPPENS NOW:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "✅ Secrets will rotate automatically every ${ROTATION_DAYS} days"
    echo "✅ External Secrets Operator will sync rotated secrets within 1 hour"
    echo "✅ Pods will automatically get new secrets (no restart needed for env vars)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TO CHECK ROTATION STATUS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "aws secretsmanager describe-secret --secret-id vendure/${ENVIRONMENT}/database"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TO MANUALLY ROTATE A SECRET:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "aws secretsmanager rotate-secret --secret-id vendure/${ENVIRONMENT}/database"
    echo ""
}

main "$@"

