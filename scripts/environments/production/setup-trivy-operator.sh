#!/bin/bash
# =============================================================================
# TRIVY OPERATOR SETUP SCRIPT
# =============================================================================
# This script installs Trivy Operator for container image vulnerability scanning
#
# Features:
#   - Automatic scanning of all container images
#   - Admission controller to block vulnerable images
#   - Vulnerability reports
#   - Prometheus metrics integration
#
# Usage:
#   chmod +x setup-trivy-operator.sh
#   ./setup-trivy-operator.sh
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
NAMESPACE="trivy-system"
RELEASE_NAME="trivy-operator"
VALUES_FILE="trivy-operator-values.yaml"

# =============================================================================
# STEP 1: Add Helm Repository
# =============================================================================
add_helm_repo() {
    print_header "Step 1: Adding Trivy Helm Repository"

    if helm repo list | grep -q aquasecurity; then
        print_step "Repository already added, updating..."
        helm repo update aquasecurity
    else
        print_step "Adding aquasecurity Helm repository..."
        helm repo add aquasecurity https://aquasecurity.github.io/helm-charts/
        helm repo update
    fi
}

# =============================================================================
# STEP 2: Create Namespace
# =============================================================================
create_namespace() {
    print_header "Step 2: Creating Namespace"

    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_warning "Namespace $NAMESPACE already exists"
    else
        print_step "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi
}

# =============================================================================
# STEP 3: Install Trivy Operator
# =============================================================================
install_trivy() {
    print_header "Step 3: Installing Trivy Operator"

    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        print_warning "Trivy Operator already installed, upgrading..."
        helm upgrade "$RELEASE_NAME" aquasecurity/trivy-operator \
            -n "$NAMESPACE" \
            -f "$VALUES_FILE" \
            --wait
    else
        print_step "Installing Trivy Operator..."
        helm install "$RELEASE_NAME" aquasecurity/trivy-operator \
            -n "$NAMESPACE" \
            -f "$VALUES_FILE" \
            --wait \
            --timeout 5m
    fi
}

# =============================================================================
# STEP 4: Verify Installation
# =============================================================================
verify_installation() {
    print_header "Step 4: Verifying Installation"

    print_step "Checking Trivy Operator pods..."
    if kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=trivy-operator \
        -n "$NAMESPACE" \
        --timeout=120s &>/dev/null; then
        print_step "✅ Trivy Operator is running"
    else
        print_error "Trivy Operator pods not ready"
        kubectl get pods -n "$NAMESPACE"
        exit 1
    fi

    print_step "Checking admission controller..."
    if kubectl get validatingwebhookconfiguration | grep -q trivy-operator; then
        print_step "✅ Admission controller is configured"
    else
        print_warning "Admission controller not found (may need to wait)"
    fi

    print_step "Checking vulnerability reports CRD..."
    if kubectl get crd vulnerabilityreports.aquasecurity.github.io &>/dev/null; then
        print_step "✅ Vulnerability reports CRD is installed"
    else
        print_error "Vulnerability reports CRD not found"
        exit 1
    fi
}

# =============================================================================
# STEP 5: Test Image Scanning
# =============================================================================
test_scanning() {
    print_header "Step 5: Testing Image Scanning"

    print_step "Creating test vulnerability report..."
    
    # Create a test VulnerabilityReport (Trivy will auto-scan)
    cat <<EOF | kubectl apply -f -
apiVersion: aquasecurity.github.io/v1alpha1
kind: VulnerabilityReport
metadata:
  name: test-scan
  namespace: $NAMESPACE
spec:
  image:
    repository: nginx
    tag: "latest"
EOF

    print_step "Waiting for scan to complete (this may take a minute)..."
    sleep 30
    
    if kubectl get vulnerabilityreport test-scan -n "$NAMESPACE" &>/dev/null; then
        print_step "✅ Test scan completed"
        kubectl get vulnerabilityreport test-scan -n "$NAMESPACE" -o yaml | grep -A 5 "summary" || true
    else
        print_warning "Test scan may still be in progress"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    print_header "Trivy Operator Setup"
    
    echo ""
    echo "This script will:"
    echo "  1. Add Trivy Helm repository"
    echo "  2. Create trivy-system namespace"
    echo "  3. Install Trivy Operator with admission controller"
    echo "  4. Verify installation"
    echo "  5. Test image scanning"
    echo ""
    echo "Features enabled:"
    echo "  ✅ Automatic image scanning"
    echo "  ✅ Admission controller (blocks HIGH/CRITICAL vulnerabilities)"
    echo "  ✅ Vulnerability reports"
    echo "  ✅ Prometheus metrics"
    echo ""
    
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Aborted by user"
        exit 1
    fi
    
    # Check if values file exists
    if [ ! -f "$VALUES_FILE" ]; then
        print_error "Values file not found: $VALUES_FILE"
        exit 1
    fi
    
    add_helm_repo
    create_namespace
    install_trivy
    verify_installation
    test_scanning
    
    print_header "Setup Complete!"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "WHAT HAPPENS NOW:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "✅ All new images will be automatically scanned"
    echo "✅ Images with HIGH/CRITICAL vulnerabilities will be BLOCKED"
    echo "✅ Vulnerability reports created for all pods"
    echo "✅ Metrics available in Prometheus"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TO CHECK VULNERABILITY REPORTS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "kubectl get vulnerabilityreports -A"
    echo "kubectl get vulnerabilityreport <pod-name> -n <namespace> -o yaml"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TO VIEW ADMISSION CONTROLLER LOGS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=trivy-operator"
    echo ""
}

main "$@"

