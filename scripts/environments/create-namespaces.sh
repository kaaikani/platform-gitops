#!/bin/bash
# =============================================================================
# CREATE VENDURE NAMESPACES SCRIPT
# =============================================================================
# This script creates all Vendure namespaces with proper Pod Security Standards
#
# Namespaces Created:
#   - vendure-production (restricted PSS)
#   - vendure-test (baseline PSS)
#   - vendure-local (baseline PSS)
#
# Usage:
#   chmod +x create-namespaces.sh
#   ./create-namespaces.sh
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
print_success() { echo -e "${GREEN}✅ $1${NC}"; }

# =============================================================================
# CREATE NAMESPACE WITH PSS
# =============================================================================
create_namespace() {
    local namespace=$1
    local pss_level=$2
    
    if kubectl get namespace "$namespace" &>/dev/null; then
        print_warning "Namespace $namespace already exists"
        read -p "Update Pod Security Standards? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    else
        print_step "Creating namespace: $namespace"
        kubectl create namespace "$namespace"
    fi
    
    print_step "Applying Pod Security Standards ($pss_level) to $namespace"
    
    case "$pss_level" in
        restricted)
            kubectl label namespace "$namespace" \
                pod-security.kubernetes.io/enforce=restricted \
                pod-security.kubernetes.io/audit=restricted \
                pod-security.kubernetes.io/warn=restricted \
                --overwrite
            ;;
        baseline)
            kubectl label namespace "$namespace" \
                pod-security.kubernetes.io/enforce=baseline \
                pod-security.kubernetes.io/audit=baseline \
                pod-security.kubernetes.io/warn=restricted \
                --overwrite
            ;;
        privileged)
            kubectl label namespace "$namespace" \
                pod-security.kubernetes.io/enforce=privileged \
                pod-security.kubernetes.io/audit=privileged \
                pod-security.kubernetes.io/warn=privileged \
                --overwrite
            ;;
    esac
    
    print_success "Namespace $namespace configured"
}

# =============================================================================
# VERIFY NAMESPACES
# =============================================================================
verify_namespaces() {
    print_header "Verifying Namespaces"
    
    local namespaces=("vendure-production" "vendure-test" "vendure-local")
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            print_success "$ns exists"
            
            # Check PSS labels
            ENFORCE=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
            if [ -n "$ENFORCE" ]; then
                echo "   PSS Level: $ENFORCE"
            else
                print_warning "   No PSS labels found"
            fi
        else
            print_error "$ns does NOT exist"
        fi
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    print_header "Create Vendure Namespaces"
    
    echo ""
    echo "This script will create all Vendure namespaces:"
    echo "  • vendure-production (restricted PSS - most secure)"
    echo "  • vendure-test (baseline PSS)"
    echo "  • vendure-local (baseline PSS)"
    echo ""
    echo "Pod Security Standards (PSS) will be applied automatically."
    echo ""
    
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Aborted"
        exit 0
    fi
    
    # Create namespaces
    create_namespace "vendure-production" "restricted"
    create_namespace "vendure-test" "baseline"
    create_namespace "vendure-local" "baseline"
    
    # Verify
    verify_namespaces
    
    print_header "Setup Complete!"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NAMESPACES CREATED:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "✅ vendure-production (restricted PSS)"
    echo "✅ vendure-test (baseline PSS)"
    echo "✅ vendure-local (baseline PSS)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NEXT STEPS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Create RBAC roles:"
    echo "   cd production && ./create-rbac-roles.sh vendure-production"
    echo "   cd production && ./create-rbac-roles.sh vendure-test"
    echo "   cd production && ./create-rbac-roles.sh vendure-local"
    echo ""
    echo "2. Deploy Vendure to each namespace:"
    echo "   helm install vendure-prod ../../vendure-stack \\"
    echo "     -n vendure-production \\"
    echo "     -f production/vendure-values.yaml"
    echo ""
    echo "3. Verify namespaces:"
    echo "   kubectl get namespaces | grep vendure"
    echo ""
}

main "$@"


