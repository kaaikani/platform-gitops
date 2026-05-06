#!/bin/bash

# Vendure Helm Deployment Script
# Run from workspace root: /home/adminuser/Desktop/vendure/K8s/Admin-ui

set -e

WORKSPACE_ROOT="/home/adminuser/Desktop/vendure/K8s/Admin-ui"
CHART_PATH="helm/vendure-stack"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Check if we're in the workspace root
if [ ! -d "$CHART_PATH" ]; then
    print_error "Chart not found at: $CHART_PATH"
    print_info "Please run this script from workspace root: $WORKSPACE_ROOT"
    exit 1
fi

# Function to deploy to an environment
deploy_environment() {
    local env=$1
    local namespace=$2
    local pss_enforce=$3
    local values_file="helm/environments/${env}/vendure-values.yaml"
    
    if [ ! -f "$values_file" ]; then
        print_error "Values file not found: $values_file"
        return 1
    fi
    
    print_info "Deploying to ${env} environment..."
    
    # Install/Upgrade Helm release
    if helm list -n "$namespace" | grep -q "vendure-${env}"; then
        print_info "Release exists, upgrading..."
        helm upgrade vendure-${env} "$CHART_PATH" \
            -n "$namespace" \
            -f "$values_file"
    else
        print_info "Release not found, installing..."
        helm install vendure-${env} "$CHART_PATH" \
            -n "$namespace" \
            --create-namespace \
            -f "$values_file"
    fi
    
    # Apply PSS labels
    print_info "Applying Pod Security Standards labels..."
    kubectl label namespace "$namespace" \
        pod-security.kubernetes.io/enforce="$pss_enforce" \
        pod-security.kubernetes.io/audit="$pss_enforce" \
        pod-security.kubernetes.io/warn=restricted \
        --overwrite 2>/dev/null || true
    
    print_success "Deployment to ${env} completed!"
}

# Main menu
case "${1:-}" in
    production|prod)
        deploy_environment "production" "vendure-production" "restricted"
        ;;
    test)
        deploy_environment "test" "vendure-test" "baseline"
        ;;
    local)
        deploy_environment "local" "vendure-local" "baseline"
        ;;
    *)
        echo "Usage: $0 {production|test|local}"
        echo ""
        echo "Examples:"
        echo "  $0 production  # Deploy to production"
        echo "  $0 test        # Deploy to test"
        echo "  $0 local       # Deploy to local"
        exit 1
        ;;
esac

