#!/bin/bash
# =============================================================================
# DEPLOY AND TEST ALL FIXES - LOCAL ENVIRONMENT
# =============================================================================
# This script deploys all fixes and then runs comprehensive tests
#
# Usage:
#   chmod +x deploy-and-test-all.sh
#   ./deploy-and-test-all.sh
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

WORKSPACE_ROOT="/home/adminuser/Desktop/vendure/K8s/Admin-ui"
cd "$WORKSPACE_ROOT"

# Ensure we're using local cluster
kubectl config use-context minikube 2>/dev/null || {
    print_error "Minikube not found. Start it with: minikube start"
    exit 1
}

print_header "Deploying All Fixes - Local Environment"

# =============================================================================
# PHASE 1: Deploy Monitoring Stack
# =============================================================================
print_header "Phase 1: Deploying Monitoring Stack"

print_step "Deploying Prometheus, Grafana, Loki, Tempo..."
./helm/environments/local/setup-local-monitoring.sh || {
    print_warning "Some monitoring components failed to deploy"
}

# =============================================================================
# PHASE 2: Deploy Trivy Operator (Image Scanning)
# =============================================================================
print_header "Phase 2: Deploying Trivy Operator (Image Scanning)"

print_step "Adding Trivy Helm repository..."
helm repo add aquasecurity https://aquasecurity.github.io/helm-charts/ 2>/dev/null || true
helm repo update

print_step "Deploying Trivy Operator..."
if helm list -n trivy-system | grep -q trivy-operator; then
    print_info "Trivy Operator already installed, upgrading..."
    helm upgrade trivy-operator aquasecurity/trivy-operator \
        -n trivy-system \
        --create-namespace \
        --set trivy.ignoreUnfixed=true \
        --set trivy.severity=CRITICAL,HIGH \
        --set trivy.resources.requests.cpu=100m \
        --set trivy.resources.requests.memory=128Mi \
        --set trivy.resources.limits.cpu=500m \
        --set trivy.resources.limits.memory=512Mi 2>/dev/null || {
        print_warning "Trivy upgrade failed"
    }
else
    helm install trivy-operator aquasecurity/trivy-operator \
        -n trivy-system \
        --create-namespace \
        --set trivy.ignoreUnfixed=true \
        --set trivy.severity=CRITICAL,HIGH \
        --set trivy.resources.requests.cpu=100m \
        --set trivy.resources.requests.memory=128Mi \
        --set trivy.resources.limits.cpu=500m \
        --set trivy.resources.limits.memory=512Mi || {
        print_error "Trivy Operator installation failed"
        exit 1
    }
fi

print_success "Trivy Operator deployed"

# =============================================================================
# PHASE 3: Deploy Network Policies
# =============================================================================
print_header "Phase 3: Deploying Network Policies"

print_step "Upgrading Vendure with Network Policies enabled..."
if helm list -n vendure-local | grep -q vendure-local; then
    helm upgrade vendure-local helm/vendure-stack \
        -n vendure-local \
        -f helm/environments/local/vendure-values.yaml \
        --set networkPolicies.enabled=true || {
        print_warning "Network policies deployment failed (may need to deploy Vendure first)"
    }
    print_success "Network policies configured"
else
    print_warning "Vendure not deployed yet. Deploy it first, then network policies will be applied."
fi

# =============================================================================
# PHASE 4: Verify Pod Security Standards
# =============================================================================
print_header "Phase 4: Verifying Pod Security Standards"

print_step "Checking namespace labels..."
for ns in vendure-local monitoring; do
    if kubectl get namespace "$ns" &>/dev/null; then
        ENFORCE=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
        if [ -z "$ENFORCE" ]; then
            print_info "Applying PSS labels to $ns..."
            kubectl label namespace "$ns" \
                pod-security.kubernetes.io/enforce=baseline \
                pod-security.kubernetes.io/audit=baseline \
                pod-security.kubernetes.io/warn=restricted \
                --overwrite 2>/dev/null || true
            print_success "PSS labels applied to $ns"
        else
            print_success "PSS labels already exist on $ns: enforce=$ENFORCE"
        fi
    fi
done

# =============================================================================
# PHASE 5: Wait for Deployments
# =============================================================================
print_header "Phase 5: Waiting for Deployments"

print_step "Waiting for pods to be ready..."
sleep 15

# Wait for key components
for component in "prometheus" "grafana" "loki" "tempo" "trivy"; do
    print_info "Checking $component..."
    if kubectl get pods -n monitoring -l "app.kubernetes.io/name=$component" &>/dev/null 2>&1; then
        kubectl wait --for=condition=ready pod \
            -l "app.kubernetes.io/name=$component" \
            -n monitoring \
            --timeout=60s 2>/dev/null && print_success "$component is ready" || print_warning "$component not ready yet"
    elif kubectl get pods -n trivy-system -l "app.kubernetes.io/name=$component" &>/dev/null 2>&1; then
        kubectl wait --for=condition=ready pod \
            -l "app.kubernetes.io/name=$component" \
            -n trivy-system \
            --timeout=60s 2>/dev/null && print_success "$component is ready" || print_warning "$component not ready yet"
    fi
done

# =============================================================================
# PHASE 6: Run Tests
# =============================================================================
print_header "Phase 6: Running Tests"

print_step "Running comprehensive test suite..."
./helm/environments/local/test-all-fixes.sh

print_header "Deployment Complete!"
echo ""
print_success "All fixes have been deployed to local cluster"
echo ""
print_info "Next steps:"
echo "  1. Review test results above"
echo "  2. Access Grafana: kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
echo "  3. Check Trivy reports: kubectl get vulnerabilityreports -A"
echo "  4. View network policies: kubectl get networkpolicy -A"
echo ""

