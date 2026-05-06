#!/bin/bash
# =============================================================================
# CREATE RBAC ROLES SCRIPT
# =============================================================================
# This script creates Kubernetes RBAC roles and role bindings for Vendure
#
# Roles Created:
#   1. developer-role: Read-only access (view pods, logs, deployments)
#   2. devops-role: Full access to application resources (can modify)
#   3. read-only-role: View-only access (cannot modify anything)
#
# Usage:
#   chmod +x create-rbac-roles.sh
#   ./create-rbac-roles.sh [namespace]
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

# Configuration
# Default namespace based on environment
# Production: vendure-production
# Test: vendure-test  
# Local: vendure-local
if [ -z "$1" ]; then
    # Try to detect environment from current directory
    if [[ "$PWD" == *"/production"* ]]; then
        NAMESPACE="vendure-production"
    elif [[ "$PWD" == *"/test"* ]]; then
        NAMESPACE="vendure-test"
    elif [[ "$PWD" == *"/local"* ]]; then
        NAMESPACE="vendure-local"
    else
        NAMESPACE="vendure-production"
    fi
else
    NAMESPACE="$1"
fi

# =============================================================================
# CREATE DEVELOPER ROLE
# =============================================================================
create_developer_role() {
    print_step "Creating developer-role..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer-role
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: vendure-stack
    app.kubernetes.io/component: rbac
rules:
  # Can view pods and logs
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/status"]
    verbs: ["get", "list", "watch"]
  
  # Can view services
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["get", "list", "watch"]
  
  # Can view configmaps and secrets (read-only)
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
  
  # Can view deployments and replicasets
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
  
  # Can view horizontal pod autoscalers
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch"]
EOF

    print_success "Developer role created"
}

# =============================================================================
# CREATE DEVOPS ROLE
# =============================================================================
create_devops_role() {
    print_step "Creating devops-role..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: devops-role
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: vendure-stack
    app.kubernetes.io/component: rbac
rules:
  # Full access to pods
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/status", "pods/exec"]
    verbs: ["*"]
  
  # Full access to services
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["*"]
  
  # Full access to configmaps and secrets
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["*"]
  
  # Full access to deployments
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["*"]
  
  # Full access to horizontal pod autoscalers
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["*"]
  
  # Full access to ingress
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["*"]
  
  # Full access to network policies
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["*"]
  
  # CANNOT delete namespaces or modify RBAC (safety)
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch"]
  
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
EOF

    print_success "DevOps role created"
}

# =============================================================================
# CREATE READ-ONLY ROLE
# =============================================================================
create_readonly_role() {
    print_step "Creating read-only-role..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: read-only-role
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: vendure-stack
    app.kubernetes.io/component: rbac
rules:
  # Can only view (get, list, watch) - no modifications
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/status", "services", "endpoints", "configmaps"]
    verbs: ["get", "list", "watch"]
  
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
  
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch"]
  
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch"]
  
  # Cannot view secrets (security)
  # Cannot modify anything
EOF

    print_success "Read-only role created"
}

# =============================================================================
# CREATE ROLE BINDING HELPER
# =============================================================================
create_role_binding() {
    local role_name=$1
    local user_name=$2
    local binding_name="${role_name}-binding-$(echo "$user_name" | tr '@.' '-' | tr '[:upper:]' '[:lower:]')"
    
    print_step "Creating role binding: $binding_name for user: $user_name"
    
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${binding_name}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: vendure-stack
    app.kubernetes.io/component: rbac
subjects:
  - kind: User
    name: ${user_name}
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${role_name}
  apiGroup: rbac.authorization.k8s.io
EOF

    print_success "Role binding created: $binding_name"
}

# =============================================================================
# VERIFY ROLES
# =============================================================================
verify_roles() {
    print_header "Verifying Roles"
    
    print_step "Checking roles in namespace: $NAMESPACE"
    
    if kubectl get role developer-role -n "$NAMESPACE" &>/dev/null; then
        print_success "developer-role exists"
    else
        print_error "developer-role NOT found"
    fi
    
    if kubectl get role devops-role -n "$NAMESPACE" &>/dev/null; then
        print_success "devops-role exists"
    else
        print_error "devops-role NOT found"
    fi
    
    if kubectl get role read-only-role -n "$NAMESPACE" &>/dev/null; then
        print_success "read-only-role exists"
    else
        print_error "read-only-role NOT found"
    fi
    
    echo ""
    print_step "Role bindings:"
    kubectl get rolebindings -n "$NAMESPACE" -l app.kubernetes.io/component=rbac 2>/dev/null || \
        kubectl get rolebindings -n "$NAMESPACE" 2>/dev/null | head -5
}

# =============================================================================
# INTERACTIVE ROLE BINDING CREATION
# =============================================================================
interactive_bindings() {
    print_header "Create Role Bindings"
    
    echo ""
    echo "Would you like to create role bindings now? (y/n)"
    read -p "> " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Skipping role binding creation"
        return
    fi
    
    while true; do
        echo ""
        echo "Select role to bind:"
        echo "  1) developer-role (read-only access)"
        echo "  2) devops-role (full access)"
        echo "  3) read-only-role (view-only)"
        echo "  4) Done"
        echo ""
        read -p "Selection (1-4): " role_choice
        
        case $role_choice in
            1) ROLE="developer-role" ;;
            2) ROLE="devops-role" ;;
            3) ROLE="read-only-role" ;;
            4) break ;;
            *) print_error "Invalid selection"; continue ;;
        esac
        
        if [ "$role_choice" != "4" ]; then
            echo ""
            read -p "Enter username (IAM user or EKS access entry): " username
            if [ -n "$username" ]; then
                create_role_binding "$ROLE" "$username"
            fi
        fi
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    print_header "Create RBAC Roles"
    
    echo ""
    echo "This script will create RBAC roles in namespace: $NAMESPACE"
    echo ""
    echo "Roles to be created:"
    echo "  • developer-role: Read-only access"
    echo "  • devops-role: Full access to application resources"
    echo "  • read-only-role: View-only access"
    echo ""
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_warning "Namespace $NAMESPACE does not exist"
        echo ""
        echo "The namespace needs to be created first. This is normal if you haven't"
        echo "deployed Vendure to this environment yet."
        echo ""
        read -p "Create namespace $NAMESPACE now? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_step "Creating namespace: $NAMESPACE"
            kubectl create namespace "$NAMESPACE"
            
            # Apply Pod Security Standards based on environment
            if [[ "$NAMESPACE" == "vendure-production" ]]; then
                print_step "Applying Pod Security Standards (restricted) to production namespace"
                kubectl label namespace "$NAMESPACE" \
                    pod-security.kubernetes.io/enforce=restricted \
                    pod-security.kubernetes.io/audit=restricted \
                    pod-security.kubernetes.io/warn=restricted \
                    --overwrite
            elif [[ "$NAMESPACE" == "vendure-test" ]]; then
                print_step "Applying Pod Security Standards (baseline) to test namespace"
                kubectl label namespace "$NAMESPACE" \
                    pod-security.kubernetes.io/enforce=baseline \
                    pod-security.kubernetes.io/audit=baseline \
                    pod-security.kubernetes.io/warn=restricted \
                    --overwrite
            elif [[ "$NAMESPACE" == "vendure-local" ]]; then
                print_step "Applying Pod Security Standards (baseline) to local namespace"
                kubectl label namespace "$NAMESPACE" \
                    pod-security.kubernetes.io/enforce=baseline \
                    pod-security.kubernetes.io/audit=baseline \
                    pod-security.kubernetes.io/warn=restricted \
                    --overwrite
            fi
            
            print_success "Namespace created and configured"
        else
            print_error "Cannot proceed without namespace"
            echo ""
            echo "You can create the namespace manually with:"
            echo "  kubectl create namespace $NAMESPACE"
            echo ""
            echo "Or run this script again and answer 'y' to create it."
            exit 1
        fi
    else
        print_success "Namespace $NAMESPACE exists"
    fi
    
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Aborted"
        exit 0
    fi
    
    # Create roles
    create_developer_role
    create_devops_role
    create_readonly_role
    
    # Verify
    verify_roles
    
    # Interactive role bindings
    interactive_bindings
    
    print_header "Setup Complete!"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NEXT STEPS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Verify roles:"
    echo "   kubectl get roles -n $NAMESPACE"
    echo ""
    echo "2. Verify role bindings:"
    echo "   kubectl get rolebindings -n $NAMESPACE"
    echo ""
    echo "3. Test access (as a bound user):"
    echo "   kubectl auth can-i get pods --namespace $NAMESPACE"
    echo ""
    echo "4. View role details:"
    echo "   kubectl describe role developer-role -n $NAMESPACE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TO CREATE MORE ROLE BINDINGS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Run this script again or use:"
    echo "  kubectl create rolebinding <name> \\"
    echo "    --role=developer-role \\"
    echo "    --user=<username> \\"
    echo "    -n $NAMESPACE"
    echo ""
}

main "$@"

