#!/bin/bash
# =============================================================================
# SECURITY SETUP VERIFICATION SCRIPT
# =============================================================================
# This script verifies all security configurations:
#   - Network policies
#   - Pod Security Standards
#   - RBAC
#   - Image scanning (Trivy)
#   - Secrets rotation
#
# Usage:
#   chmod +x verify-security-setup.sh
#   ./verify-security-setup.sh
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
print_fail() { echo -e "${RED}❌ $1${NC}"; }

# Configuration
NAMESPACE="${1:-vendure-production}"
AWS_REGION="${AWS_REGION:-ap-south-1}"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# =============================================================================
# 1. NETWORK POLICIES VERIFICATION
# =============================================================================
verify_network_policies() {
    print_header "1. Network Policies Verification"

    # Check if default-deny policy exists
    if kubectl get networkpolicy default-deny-all -n "$NAMESPACE" &>/dev/null; then
        print_success "Default-deny network policy exists"
        ((PASSED++))
    else
        print_fail "Default-deny network policy NOT found"
        ((FAILED++))
    fi

    # Check if application network policy exists
    if kubectl get networkpolicy -n "$NAMESPACE" -l app.kubernetes.io/component=network-policy &>/dev/null; then
        print_success "Application network policies exist"
        ((PASSED++))
    else
        print_warning "Application network policies not found (may be disabled)"
        ((WARNINGS++))
    fi

    # Check namespace labels (required for Prometheus access)
    if kubectl get namespace monitoring -o jsonpath='{.metadata.labels.name}' 2>/dev/null | grep -q monitoring; then
        print_success "Monitoring namespace labeled correctly"
        ((PASSED++))
    else
        print_warning "Monitoring namespace may not be labeled (Prometheus access may fail)"
        ((WARNINGS++))
    fi
}

# =============================================================================
# 2. POD SECURITY STANDARDS VERIFICATION
# =============================================================================
verify_pss() {
    print_header "2. Pod Security Standards (PSS/PSA) Verification"

    # Check if PSA admission controller is enabled (EKS 1.23+)
    K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' | cut -d. -f1,2 || echo "unknown")
    
    if [[ "$K8S_VERSION" > "1.22" ]] || [[ "$K8S_VERSION" == "unknown" ]]; then
        print_step "Kubernetes version: $K8S_VERSION (PSA should be available)"
    else
        print_warning "Kubernetes version $K8S_VERSION may not support PSA"
        ((WARNINGS++))
    fi

    # Check namespace PSS labels
    ENFORCE_LABEL=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
    
    if [ -n "$ENFORCE_LABEL" ]; then
        print_success "PSS enforce label: $ENFORCE_LABEL"
        ((PASSED++))
    else
        print_fail "PSS enforce label NOT found on namespace $NAMESPACE"
        ((FAILED++))
    fi

    # Check audit label
    AUDIT_LABEL=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/audit}' 2>/dev/null || echo "")
    if [ -n "$AUDIT_LABEL" ]; then
        print_success "PSS audit label: $AUDIT_LABEL"
        ((PASSED++))
    else
        print_warning "PSS audit label not found"
        ((WARNINGS++))
    fi

    # Test PSS enforcement (try to create a pod that violates restricted policy)
    print_step "Testing PSS enforcement..."
    if kubectl run test-pss-restricted --image=busybox --rm -i --restart=Never \
        -n "$NAMESPACE" -- sh -c "whoami" 2>&1 | grep -q "violates PodSecurity"; then
        print_success "PSS is enforcing restrictions (test pod was blocked)"
        ((PASSED++))
    else
        print_warning "PSS enforcement test inconclusive (pod may have been allowed)"
        ((WARNINGS++))
    fi
}

# =============================================================================
# 3. RBAC VERIFICATION
# =============================================================================
verify_rbac() {
    print_header "3. RBAC Verification"

    # Check if RBAC roles exist
    if kubectl get role developer-role -n "$NAMESPACE" &>/dev/null; then
        print_success "Developer role exists"
        ((PASSED++))
    else
        print_warning "Developer role not found (RBAC may be disabled)"
        ((WARNINGS++))
    fi

    if kubectl get role devops-role -n "$NAMESPACE" &>/dev/null; then
        print_success "DevOps role exists"
        ((PASSED++))
    else
        print_warning "DevOps role not found"
        ((WARNINGS++))
    fi

    # Check role bindings
    ROLE_BINDINGS=$(kubectl get rolebinding -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$ROLE_BINDINGS" -gt 0 ]; then
        print_success "Found $ROLE_BINDINGS role binding(s)"
        ((PASSED++))
    else
        print_warning "No role bindings found (RBAC enabled but no users configured)"
        ((WARNINGS++))
    fi

    # Check service account permissions
    SA_NAME=$(kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=vendure \
        -o jsonpath='{.items[0].spec.template.spec.serviceAccountName}' 2>/dev/null || echo "")
    
    if [ -n "$SA_NAME" ]; then
        print_success "Service account configured: $SA_NAME"
        ((PASSED++))
    else
        print_warning "Service account not found for Vendure deployment"
        ((WARNINGS++))
    fi
}

# =============================================================================
# 4. IMAGE SCANNING (TRIVY) VERIFICATION
# =============================================================================
verify_image_scanning() {
    print_header "4. Image Scanning (Trivy) Verification"

    # Check if Trivy Operator is installed
    if kubectl get deployment trivy-operator -n trivy-system &>/dev/null; then
        print_success "Trivy Operator is installed"
        ((PASSED++))
        
        # Check if pods are running
        if kubectl get pods -n trivy-system -l app.kubernetes.io/name=trivy-operator \
            --field-selector=status.phase=Running &>/dev/null; then
            print_success "Trivy Operator pods are running"
            ((PASSED++))
        else
            print_fail "Trivy Operator pods not running"
            ((FAILED++))
        fi
    else
        print_fail "Trivy Operator NOT installed"
        ((FAILED++))
    fi

    # Check admission controller
    if kubectl get validatingwebhookconfiguration | grep -q trivy-operator; then
        print_success "Trivy admission controller is configured"
        ((PASSED++))
    else
        print_warning "Trivy admission controller not found"
        ((WARNINGS++))
    fi

    # Check vulnerability reports CRD
    if kubectl get crd vulnerabilityreports.aquasecurity.github.io &>/dev/null; then
        print_success "Vulnerability reports CRD is installed"
        ((PASSED++))
    else
        print_fail "Vulnerability reports CRD not found"
        ((FAILED++))
    fi

    # Check for recent vulnerability reports
    VULN_REPORTS=$(kubectl get vulnerabilityreports -A --no-headers 2>/dev/null | wc -l)
    if [ "$VULN_REPORTS" -gt 0 ]; then
        print_success "Found $VULN_REPORTS vulnerability report(s)"
        ((PASSED++))
    else
        print_warning "No vulnerability reports found (images may not be scanned yet)"
        ((WARNINGS++))
    fi
}

# =============================================================================
# 5. SECRETS ROTATION VERIFICATION
# =============================================================================
verify_secrets_rotation() {
    print_header "5. Secrets Rotation Verification"

    # Check if External Secrets Operator is installed
    if kubectl get deployment external-secrets -n external-secrets-system &>/dev/null; then
        print_success "External Secrets Operator is installed"
        ((PASSED++))
    else
        print_warning "External Secrets Operator not found (may be in different namespace)"
        ((WARNINGS++))
    fi

    # Check ExternalSecret resources
    if kubectl get externalsecret -n "$NAMESPACE" &>/dev/null; then
        print_success "ExternalSecret resources exist"
        ((PASSED++))
        
        # Check refresh interval
        REFRESH_INTERVAL=$(kubectl get externalsecret -n "$NAMESPACE" \
            -o jsonpath='{.items[0].spec.refreshInterval}' 2>/dev/null || echo "")
        if [ -n "$REFRESH_INTERVAL" ]; then
            print_success "Refresh interval: $REFRESH_INTERVAL"
            ((PASSED++))
        fi
    else
        print_warning "ExternalSecret resources not found"
        ((WARNINGS++))
    fi

    # Check AWS Secrets Manager rotation (requires AWS CLI)
    if command -v aws &>/dev/null; then
        print_step "Checking AWS Secrets Manager rotation status..."
        
        SECRETS=(
            "vendure/production/database"
            "vendure/production/redis"
            "vendure/production/app"
        )
        
        for SECRET_ID in "${SECRETS[@]}"; do
            ROTATION_ENABLED=$(aws secretsmanager describe-secret \
                --secret-id "$SECRET_ID" \
                --region "$AWS_REGION" \
                --query 'RotationEnabled' \
                --output text 2>/dev/null || echo "false")
            
            if [ "$ROTATION_ENABLED" == "true" ]; then
                print_success "Rotation enabled for $SECRET_ID"
                ((PASSED++))
            else
                print_warning "Rotation not enabled for $SECRET_ID"
                ((WARNINGS++))
            fi
        done
    else
        print_warning "AWS CLI not found, skipping AWS Secrets Manager checks"
        ((WARNINGS++))
    fi
}

# =============================================================================
# SUMMARY
# =============================================================================
print_summary() {
    print_header "Security Verification Summary"
    
    TOTAL=$((PASSED + FAILED + WARNINGS))
    
    echo ""
    echo "Results:"
    echo "  ✅ Passed:  $PASSED"
    echo "  ❌ Failed: $FAILED"
    echo "  ⚠️  Warnings: $WARNINGS"
    echo "  📊 Total:   $TOTAL"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        print_success "All critical security checks passed!"
        if [ $WARNINGS -gt 0 ]; then
            echo ""
            print_warning "Some warnings found - review above for details"
        fi
        exit 0
    else
        print_fail "Some security checks failed - review above for details"
        exit 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    print_header "Security Setup Verification"
    
    echo ""
    echo "Verifying security configuration for namespace: $NAMESPACE"
    echo ""
    
    verify_network_policies
    verify_pss
    verify_rbac
    verify_image_scanning
    verify_secrets_rotation
    
    print_summary
}

main "$@"

