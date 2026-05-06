#!/bin/bash
# =============================================================================
# POD SECURITY STANDARDS (PSS/PSA) SETUP SCRIPT
# =============================================================================
# This script applies Pod Security Standards labels to all namespaces
# 
# PSS Levels:
#   - privileged: Most permissive (system namespaces only)
#   - baseline: Medium security (test, monitoring)
#   - restricted: Most secure (production)
#
# Usage:
#   chmod +x setup-pod-security-standards.sh
#   ./setup-pod-security-standards.sh
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

# =============================================================================
# STEP 1: Label Production Namespace (RESTRICTED - Most Secure)
# =============================================================================
label_production() {
    print_step "Labeling production namespace (restricted)"
    
    if kubectl get namespace vendure-production &>/dev/null; then
        kubectl label namespace vendure-production \
            pod-security.kubernetes.io/enforce=restricted \
            pod-security.kubernetes.io/audit=restricted \
            pod-security.kubernetes.io/warn=restricted \
            --overwrite
        
        echo -e "${GREEN}✅ Production namespace labeled: restricted${NC}"
    else
        print_warning "Namespace 'vendure-production' not found - skipping"
    fi
}

# =============================================================================
# STEP 2: Label Test Namespace (BASELINE - Medium Security)
# =============================================================================
label_test() {
    print_step "Labeling test namespace (baseline)"
    
    if kubectl get namespace vendure-test &>/dev/null; then
        kubectl label namespace vendure-test \
            pod-security.kubernetes.io/enforce=baseline \
            pod-security.kubernetes.io/audit=baseline \
            pod-security.kubernetes.io/warn=restricted \
            --overwrite
        
        echo -e "${GREEN}✅ Test namespace labeled: baseline${NC}"
    else
        print_warning "Namespace 'vendure-test' not found - skipping"
    fi
}

# =============================================================================
# STEP 3: Label Monitoring Namespace (BASELINE - Some tools need privileges)
# =============================================================================
label_monitoring() {
    print_step "Labeling monitoring namespace (baseline)"
    
    if kubectl get namespace monitoring &>/dev/null; then
        kubectl label namespace monitoring \
            pod-security.kubernetes.io/enforce=baseline \
            pod-security.kubernetes.io/audit=baseline \
            pod-security.kubernetes.io/warn=restricted \
            --overwrite
        
        echo -e "${GREEN}✅ Monitoring namespace labeled: baseline${NC}"
    else
        print_warning "Namespace 'monitoring' not found - skipping"
    fi
}

# =============================================================================
# STEP 4: Label System Namespaces (PRIVILEGED - Required for system components)
# =============================================================================
label_system() {
    print_step "Labeling system namespaces (privileged)"
    
    # kube-system - Required for system components
    if kubectl get namespace kube-system &>/dev/null; then
        kubectl label namespace kube-system \
            pod-security.kubernetes.io/enforce=privileged \
            pod-security.kubernetes.io/audit=privileged \
            pod-security.kubernetes.io/warn=privileged \
            --overwrite
        
        echo -e "${GREEN}✅ kube-system namespace labeled: privileged${NC}"
    fi
    
    # kube-public - Public namespace
    if kubectl get namespace kube-public &>/dev/null; then
        kubectl label namespace kube-public \
            pod-security.kubernetes.io/enforce=baseline \
            pod-security.kubernetes.io/audit=baseline \
            pod-security.kubernetes.io/warn=restricted \
            --overwrite
        
        echo -e "${GREEN}✅ kube-public namespace labeled: baseline${NC}"
    fi
    
    # kube-node-lease - Node lease namespace
    if kubectl get namespace kube-node-lease &>/dev/null; then
        kubectl label namespace kube-node-lease \
            pod-security.kubernetes.io/enforce=privileged \
            pod-security.kubernetes.io/audit=privileged \
            pod-security.kubernetes.io/warn=privileged \
            --overwrite
        
        echo -e "${GREEN}✅ kube-node-lease namespace labeled: privileged${NC}"
    fi
}

# =============================================================================
# STEP 5: Label Default Namespace (BASELINE)
# =============================================================================
label_default() {
    print_step "Labeling default namespace (baseline)"
    
    if kubectl get namespace default &>/dev/null; then
        kubectl label namespace default \
            pod-security.kubernetes.io/enforce=baseline \
            pod-security.kubernetes.io/audit=baseline \
            pod-security.kubernetes.io/warn=restricted \
            --overwrite
        
        echo -e "${GREEN}✅ default namespace labeled: baseline${NC}"
    fi
}

# =============================================================================
# STEP 6: Label Other Application Namespaces (BASELINE)
# =============================================================================
label_other() {
    print_step "Labeling other application namespaces (baseline)"
    
    # List of other namespaces to label
    OTHER_NAMESPACES=(
        "vendure-local"
        "external-secrets-system"
        "argocd"
    )
    
    for ns in "${OTHER_NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            kubectl label namespace "$ns" \
                pod-security.kubernetes.io/enforce=baseline \
                pod-security.kubernetes.io/audit=baseline \
                pod-security.kubernetes.io/warn=restricted \
                --overwrite
            
            echo -e "${GREEN}✅ $ns namespace labeled: baseline${NC}"
        fi
    done
}

# =============================================================================
# STEP 7: Verify Labels
# =============================================================================
verify_labels() {
    print_header "Verifying PSS Labels"
    
    echo ""
    echo "Namespace PSS Labels:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    kubectl get namespaces -o custom-columns=\
NAME:.metadata.name,\
ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce,\
AUDIT:.metadata.labels.pod-security\.kubernetes\.io/audit,\
WARN:.metadata.labels.pod-security\.kubernetes\.io/warn \
    | grep -E "NAME|vendure|monitoring|default|kube-system|kube-public|kube-node-lease" || true
    
    echo ""
    echo -e "${GREEN}✅ Verification complete${NC}"
}

# =============================================================================
# STEP 8: Test PSS Enforcement
# =============================================================================
test_enforcement() {
    print_header "Testing PSS Enforcement"
    
    echo ""
    print_step "Testing restricted namespace (production)"
    
    # Try to create a pod as root in production (should fail)
    if kubectl run test-pss-restricted --image=busybox --rm -i --restart=Never \
        -n vendure-production -- sh -c "whoami" 2>&1 | grep -q "violates PodSecurity"; then
        echo -e "${GREEN}✅ PSS is working! Pod as root was blocked in production${NC}"
    else
        print_warning "PSS test inconclusive - check manually"
    fi
    
    echo ""
    print_step "Testing baseline namespace (test)"
    
    # Try to create a pod as root in test (should work but warn)
    if kubectl run test-pss-baseline --image=busybox --rm -i --restart=Never \
        -n vendure-test -- sh -c "whoami" &>/dev/null; then
        echo -e "${GREEN}✅ Baseline namespace allows pods (with warnings)${NC}"
    fi
    
    echo ""
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    print_header "Pod Security Standards (PSS/PSA) Setup"
    
    echo ""
    echo "This script will apply PSS labels to all namespaces:"
    echo "  • Production: restricted (most secure)"
    echo "  • Test/Monitoring: baseline (medium security)"
    echo "  • System: privileged (required for system components)"
    echo ""
    
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Aborted by user"
        exit 1
    fi
    
    # Apply labels
    label_production
    label_test
    label_monitoring
    label_system
    label_default
    label_other
    
    # Verify
    verify_labels
    
    # Test
    read -p "Run PSS enforcement test? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_enforcement
    fi
    
    print_header "Setup Complete!"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "WHAT HAPPENS NOW:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "✅ Production namespace: Pods MUST comply with 'restricted' policy"
    echo "   - Cannot run as root"
    echo "   - Cannot use privileged containers"
    echo "   - Cannot access host network"
    echo ""
    echo "✅ Test/Monitoring namespaces: Pods should comply with 'baseline'"
    echo "   - Warnings shown for non-compliant pods"
    echo "   - Some privileges allowed for debugging"
    echo ""
    echo "✅ System namespaces: Use 'privileged' (required for system)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TO CHECK PSS STATUS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "kubectl get namespaces -o custom-columns=\\"
    echo "  NAME:.metadata.name,\\"
    echo "  ENFORCE:.metadata.labels.pod-security\\.kubernetes\\.io/enforce"
    echo ""
}

# Run main function
main

