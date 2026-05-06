#!/bin/bash
# =============================================================================
# SECRETS INFRASTRUCTURE SETUP
# =============================================================================
# This script is run ONCE by DevOps Lead to set up the entire secrets
# infrastructure. After this, secrets are managed automatically.
#
# WHO RUNS THIS: DevOps Lead / SRE (not regular developers)
# WHEN: Once during initial cluster setup
#
# WHAT IT DOES:
#   1. Creates secrets in AWS Secrets Manager
#   2. Creates IAM policies and roles
#   3. Installs External Secrets Operator
#   4. Sets up IRSA (IAM Roles for Service Accounts)
#
# AFTER THIS:
#   - Developers NEVER touch secrets
#   - Pods automatically get secrets
#   - Secrets rotate automatically
#
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
CLUSTER_NAME="vendure-cluster"

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
# STEP 1: Create Secrets in AWS Secrets Manager
# =============================================================================
create_aws_secrets() {
    print_header "Step 1: Creating Secrets in AWS Secrets Manager"

    echo ""
    print_warning "You will be prompted to enter secret values."
    print_warning "These are stored ONLY in AWS, never in files or Git."
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # TEST ENVIRONMENT SECRETS
    # ─────────────────────────────────────────────────────────────────────────
    print_step "Creating TEST environment secrets..."

    # Check if secret exists
    if aws secretsmanager describe-secret --secret-id "vendure/test/database" --region $AWS_REGION 2>/dev/null; then
        print_warning "Secret vendure/test/database already exists. Skipping..."
    else
        read -p "TEST DB Host [test-5.cbq8i48yyklk.ap-south-1.rds.amazonaws.com]: " TEST_DB_HOST
        TEST_DB_HOST=${TEST_DB_HOST:-"test-5.cbq8i48yyklk.ap-south-1.rds.amazonaws.com"}
        read -s -p "TEST DB Password: " TEST_DB_PASSWORD
        echo ""

        aws secretsmanager create-secret \
            --name "vendure/test/database" \
            --description "Vendure TEST Database Credentials" \
            --secret-string "{
                \"host\": \"$TEST_DB_HOST\",
                \"port\": \"3306\",
                \"database\": \"wow_vendure\",
                \"username\": \"admin\",
                \"password\": \"$TEST_DB_PASSWORD\"
            }" \
            --region $AWS_REGION

        print_step "Created vendure/test/database"
    fi

    # Redis secret for test
    if ! aws secretsmanager describe-secret --secret-id "vendure/test/redis" --region $AWS_REGION 2>/dev/null; then
        read -s -p "TEST Redis Password: " TEST_REDIS_PASSWORD
        echo ""

        aws secretsmanager create-secret \
            --name "vendure/test/redis" \
            --description "Vendure TEST Redis Credentials" \
            --secret-string "{
                \"host\": \"redis-17207.crce179.ap-south-1-1.ec2.redns.redis-cloud.com\",
                \"port\": \"17207\",
                \"username\": \"default\",
                \"password\": \"$TEST_REDIS_PASSWORD\"
            }" \
            --region $AWS_REGION

        print_step "Created vendure/test/redis"
    fi

    # App secrets for test
    if ! aws secretsmanager describe-secret --secret-id "vendure/test/app" --region $AWS_REGION 2>/dev/null; then
        read -s -p "TEST Superadmin Password: " TEST_ADMIN_PASSWORD
        echo ""
        COOKIE_SECRET=$(openssl rand -base64 32)

        aws secretsmanager create-secret \
            --name "vendure/test/app" \
            --description "Vendure TEST Application Secrets" \
            --secret-string "{
                \"cookieSecret\": \"$COOKIE_SECRET\",
                \"superadminUsername\": \"superadmin\",
                \"superadminPassword\": \"$TEST_ADMIN_PASSWORD\"
            }" \
            --region $AWS_REGION

        print_step "Created vendure/test/app"
    fi

    # AWS credentials for test
    if ! aws secretsmanager describe-secret --secret-id "vendure/test/aws" --region $AWS_REGION 2>/dev/null; then
        read -p "TEST AWS Access Key ID: " TEST_AWS_KEY
        read -s -p "TEST AWS Secret Access Key: " TEST_AWS_SECRET
        echo ""

        aws secretsmanager create-secret \
            --name "vendure/test/aws" \
            --description "Vendure TEST AWS Credentials" \
            --secret-string "{
                \"accessKeyId\": \"$TEST_AWS_KEY\",
                \"secretAccessKey\": \"$TEST_AWS_SECRET\",
                \"region\": \"ap-south-1\",
                \"s3Bucket\": \"cdn.kaaikani.co.in\"
            }" \
            --region $AWS_REGION

        print_step "Created vendure/test/aws"
    fi

    echo ""
    print_step "TEST environment secrets created!"

    # ─────────────────────────────────────────────────────────────────────────
    # PRODUCTION ENVIRONMENT SECRETS (Optional - do later)
    # ─────────────────────────────────────────────────────────────────────────
    echo ""
    read -p "Do you want to create PRODUCTION secrets now? (y/n): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_step "Creating PRODUCTION environment secrets..."

        # Production secrets with different paths
        # vendure/production/database
        # vendure/production/redis
        # vendure/production/app
        # vendure/production/aws
        # vendure/production/razorpay

        print_warning "Production secret creation - implement similar to test"
    fi
}

# =============================================================================
# STEP 2: Create IAM Policy
# =============================================================================
create_iam_policy() {
    print_header "Step 2: Creating IAM Policy"

    # Policy for TEST environment
    cat > /tmp/vendure-test-secrets-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": [
                "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:vendure/test/*"
            ]
        }
    ]
}
EOF

    # Check if policy exists
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/VendureTestSecretsAccess" 2>/dev/null; then
        print_warning "Policy VendureTestSecretsAccess already exists"
    else
        aws iam create-policy \
            --policy-name VendureTestSecretsAccess \
            --policy-document file:///tmp/vendure-test-secrets-policy.json

        print_step "Created IAM policy: VendureTestSecretsAccess"
    fi

    # Policy for PRODUCTION environment (separate, more restrictive)
    cat > /tmp/vendure-prod-secrets-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": [
                "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:vendure/production/*"
            ]
        }
    ]
}
EOF

    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/VendureProductionSecretsAccess" 2>/dev/null; then
        aws iam create-policy \
            --policy-name VendureProductionSecretsAccess \
            --policy-document file:///tmp/vendure-prod-secrets-policy.json

        print_step "Created IAM policy: VendureProductionSecretsAccess"
    fi

    rm -f /tmp/vendure-test-secrets-policy.json /tmp/vendure-prod-secrets-policy.json
}

# =============================================================================
# STEP 3: Install External Secrets Operator
# =============================================================================
install_external_secrets() {
    print_header "Step 3: Installing External Secrets Operator"

    # Add helm repo
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update

    # Install operator
    helm upgrade --install external-secrets external-secrets/external-secrets \
        --namespace external-secrets \
        --create-namespace \
        --set installCRDs=true \
        --wait

    print_step "External Secrets Operator installed!"
}

# =============================================================================
# STEP 4: Create IRSA (IAM Roles for Service Accounts)
# =============================================================================
create_irsa() {
    print_header "Step 4: Creating IRSA for Service Accounts"

    # Create service account for TEST namespace
    eksctl create iamserviceaccount \
        --name external-secrets-sa \
        --namespace vendure-test \
        --cluster $CLUSTER_NAME \
        --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/VendureTestSecretsAccess" \
        --approve \
        --override-existing-serviceaccounts

    print_step "Created IRSA for vendure-test namespace"

    # Create service account for PRODUCTION namespace
    eksctl create iamserviceaccount \
        --name external-secrets-sa \
        --namespace vendure-production \
        --cluster $CLUSTER_NAME \
        --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/VendureProductionSecretsAccess" \
        --approve \
        --override-existing-serviceaccounts

    print_step "Created IRSA for vendure-production namespace"
}

# =============================================================================
# STEP 5: Create ClusterSecretStore
# =============================================================================
create_secret_store() {
    print_header "Step 5: Creating ClusterSecretStore"

    cat << EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${AWS_REGION}
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
EOF

    print_step "ClusterSecretStore created!"
}

# =============================================================================
# STEP 6: Apply ExternalSecret for TEST
# =============================================================================
apply_external_secrets() {
    print_header "Step 6: Applying ExternalSecrets"

    # Create namespace if not exists
    kubectl create namespace vendure-test 2>/dev/null || true

    # Apply the ExternalSecret
    kubectl apply -f helm/environments/test/external-secrets.yaml

    print_step "ExternalSecret applied for vendure-test!"

    # Wait for secret to be created
    echo ""
    print_step "Waiting for secret to sync..."
    sleep 10

    # Verify
    if kubectl get secret vendure-secrets -n vendure-test 2>/dev/null; then
        print_step "Secret 'vendure-secrets' created successfully!"
        echo ""
        echo "Secret keys:"
        kubectl get secret vendure-secrets -n vendure-test -o jsonpath='{.data}' | \
            python3 -c "import sys,json; print('\n'.join(['  - ' + k for k in json.loads(sys.stdin.read()).keys()]))"
    else
        print_error "Secret not found. Check External Secrets Operator logs."
    fi
}

# =============================================================================
# MAIN
# =============================================================================

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     VENDURE SECRETS INFRASTRUCTURE SETUP                      ║"
echo "║                                                               ║"
echo "║     This script sets up production-grade secret management    ║"
echo "║     Run this ONCE during initial cluster setup                ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

print_warning "This script should only be run by DevOps Lead / SRE"
print_warning "Regular developers should NOT run this script"
echo ""

read -p "Are you the DevOps Lead setting up the cluster? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "This script is only for DevOps Lead. Exiting."
    exit 1
fi

# Run setup steps
create_aws_secrets
create_iam_policy
install_external_secrets
create_irsa
create_secret_store
apply_external_secrets

print_header "Setup Complete!"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WHAT HAPPENS NOW:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Secrets are stored in AWS Secrets Manager"
echo "2. External Secrets Operator syncs them to Kubernetes"
echo "3. Pods automatically get secrets via environment variables"
echo "4. NO ONE needs to type or share passwords anymore"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TO ROTATE A SECRET:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Update in AWS Secrets Manager (console or CLI)"
echo "2. External Secrets Operator will auto-sync within 1 hour"
echo "3. Restart pods to pick up new values:"
echo "   kubectl rollout restart deployment/vendure -n vendure-test"
echo ""
