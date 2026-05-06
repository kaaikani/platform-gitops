#!/bin/bash
# =============================================================================
# CREATE IAM USERS FOR EKS RBAC
# =============================================================================
# This script creates IAM users and configures them for EKS access
# Two methods:
#   1. IAM Users + aws-auth ConfigMap (legacy, but still works)
#   2. IAM Users + EKS Access Entries (newer, recommended)
#
# Usage:
#   chmod +x create-iam-users-for-eks.sh
#   ./create-iam-users-for-eks.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }

CLUSTER_NAME="${CLUSTER_NAME:-vendure-prod}"
AWS_REGION="${AWS_REGION:-ap-south-1}"

# =============================================================================
# CHECK PREREQUISITES
# =============================================================================
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! command -v aws &>/dev/null; then
        print_error "AWS CLI not found. Install it first:"
        echo "  sudo apt install awscli"
        echo "  or: brew install awscli"
        exit 1
    fi
    print_success "AWS CLI found"
    
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "AWS credentials not configured"
        echo "Run: aws configure"
        exit 1
    fi
    print_success "AWS credentials configured"
    
    # Check if cluster exists
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_success "EKS cluster '$CLUSTER_NAME' found"
    else
        print_warning "EKS cluster '$CLUSTER_NAME' not found"
        echo "  You can still create IAM users, but EKS access won't be configured"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

# =============================================================================
# CREATE IAM USER
# =============================================================================
create_iam_user() {
    local username=$1
    local email=$2
    
    print_step "Creating IAM user: $username"
    
    # Check if user already exists
    if aws iam get-user --user-name "$username" &>/dev/null; then
        print_warning "IAM user '$username' already exists"
        read -p "Use existing user? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
        return 0
    fi
    
    # Create user
    if aws iam create-user \
        --user-name "$username" \
        --tags "Key=Purpose,Value=EKS-RBAC" "Key=Email,Value=$email" \
        --output text &>/dev/null; then
        print_success "IAM user '$username' created"
    else
        print_error "Failed to create IAM user"
        return 1
    fi
    
    # Create access key (optional - for programmatic access)
    read -p "Create access key for programmatic access? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_step "Creating access key..."
        ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name "$username" --output json)
        ACCESS_KEY_ID=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
        SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')
        
        echo ""
        print_success "Access key created!"
        echo "  Access Key ID: $ACCESS_KEY_ID"
        echo "  Secret Access Key: $SECRET_ACCESS_KEY"
        echo ""
        print_warning "⚠️  SAVE THESE CREDENTIALS - Secret key won't be shown again!"
        echo ""
        read -p "Press Enter to continue..."
    fi
    
    return 0
}

# =============================================================================
# ATTACH EKS ACCESS POLICY
# =============================================================================
attach_eks_policy() {
    local username=$1
    
    print_step "Attaching EKS access policy to user: $username"
    
    # Attach AmazonEKSClusterPolicy (read-only)
    # For full access, use: arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
    # But we'll use a custom policy that allows kubectl access
    
    # Create inline policy for EKS access
    POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)
    
    if aws iam put-user-policy \
        --user-name "$username" \
        --policy-name "EKSAccess" \
        --policy-document "$POLICY_DOCUMENT" &>/dev/null; then
        print_success "EKS access policy attached"
    else
        print_warning "Failed to attach policy (user may need additional permissions)"
    fi
}

# =============================================================================
# CONFIGURE EKS ACCESS ENTRY (New Method - Recommended)
# =============================================================================
configure_eks_access_entry() {
    local username=$1
    local principal_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):user/$username"
    
    print_step "Configuring EKS access entry for: $username"
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_warning "Cluster not found, skipping EKS access entry"
        return 1
    fi
    
    # Create access entry
    if aws eks create-access-entry \
        --cluster-name "$CLUSTER_NAME" \
        --principal-arn "$principal_arn" \
        --region "$AWS_REGION" \
        --output text &>/dev/null; then
        print_success "EKS access entry created"
        
        # Associate access policy (read-only by default)
        print_step "Associating access policy..."
        if aws eks associate-access-policy \
            --cluster-name "$CLUSTER_NAME" \
            --principal-arn "$principal_arn" \
            --policy-arn "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" \
            --access-scope '{"type":"namespace","namespaces":["vendure-production","vendure-test"]}' \
            --region "$AWS_REGION" \
            --output text &>/dev/null; then
            print_success "Access policy associated"
        else
            print_warning "Failed to associate access policy (may need manual configuration)"
        fi
    else
        print_warning "Failed to create access entry (may already exist or need different permissions)"
    fi
}

# =============================================================================
# MAIN WORKFLOW
# =============================================================================
main() {
    print_header "Create IAM Users for EKS RBAC"
    
    echo ""
    echo "This script will:"
    echo "  1. Create IAM users for Kubernetes RBAC"
    echo "  2. Configure EKS access entries (if cluster exists)"
    echo "  3. Set up basic permissions"
    echo ""
    echo "After creating users, you can:"
    echo "  • Run configure-rbac-users.sh to assign them to RBAC roles"
    echo "  • Add them to vendure-values.yaml rbac section"
    echo ""
    
    check_prerequisites
    
    echo ""
    print_header "Create IAM Users"
    echo ""
    echo "Enter user details (empty username to finish):"
    echo ""
    
    declare -a CREATED_USERS
    
    while true; do
        read -p "Username (e.g., developer1): " username
        [ -z "$username" ] && break
        
        read -p "Email (for identification, e.g., developer1@company.com): " email
        [ -z "$email" ] && email="$username@example.com"
        
        if create_iam_user "$username" "$email"; then
            attach_eks_policy "$username"
            configure_eks_access_entry "$username"
            CREATED_USERS+=("$username")
            echo ""
        fi
        
        echo ""
        read -p "Create another user? (y/n): " -n 1 -r
        echo ""
        [[ ! $REPLY =~ ^[Yy]$ ]] && break
        echo ""
    done
    
    # Summary
    if [ ${#CREATED_USERS[@]} -gt 0 ]; then
        print_header "Summary"
        echo ""
        echo "Created IAM users:"
        for user in "${CREATED_USERS[@]}"; do
            echo "  • $user"
        done
        echo ""
        echo "Next steps:"
        echo "  1. Run: ./configure-rbac-users.sh"
        echo "  2. Or manually add users to vendure-values.yaml:"
        echo ""
        echo "     rbac:"
        echo "       enabled: true"
        echo "       developers:"
        for user in "${CREATED_USERS[@]}"; do
            echo "         - $user"
        done
        echo ""
    else
        print_warning "No users were created"
    fi
}

# Run main
main

