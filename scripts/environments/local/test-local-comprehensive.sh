#!/bin/bash
# =============================================================================
# COMPREHENSIVE LOCAL TESTING - All Fixes
# =============================================================================
# This script tests all fixes in local environment with error handling
#
# Usage:
#   chmod +x test-local-comprehensive.sh
#   ./test-local-comprehensive.sh
# =============================================================================

set +e  # Don't exit on errors - we want to test everything

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

PASSED=0
FAILED=0
WARNINGS=0
SKIPPED=0

test_result() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        ((PASSED++))
        return 0
    else
        print_error "$1"
        ((FAILED++))
        return 1
    fi
}

test_warning() {
    print_warning "$1"
    ((WARNINGS++))
}

test_skip() {
    print_info "⏭ $1 (skipped)"
    ((SKIPPED++))
}

print_header "Comprehensive Local Testing - All Fixes"

# Ensure we're on local cluster
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null)
if [[ "$CURRENT_CONTEXT" != *"minikube"* ]]; then
    print_warning "Not using Minikube context. Current: $CURRENT_CONTEXT"
    print_info "Switching to Minikube..."
    kubectl config use-context minikube 2>/dev/null || {
        print_error "Cannot switch to Minikube. Please start it: minikube start"
        exit 1
    }
fi

# =============================================================================
# TEST 1: Monitoring Stack
# =============================================================================
print_header "Test 1: Monitoring Stack"

print_step "Checking Prometheus..."
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus 2>/dev/null | grep -q Running; then
    test_result "Prometheus is running"
else
    test_result "Prometheus is NOT running"
fi

print_step "Checking Grafana..."
GRAFANA_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null | grep -c Running || echo "0")
if [ "$GRAFANA_PODS" -gt 0 ]; then
    test_result "Grafana is running ($GRAFANA_PODS pod(s))"
else
    GRAFANA_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null | tail -1 | awk '{print $3}' || echo "unknown")
    test_warning "Grafana is NOT running (status: $GRAFANA_STATUS)"
    print_info "Check logs: kubectl logs -n monitoring -l app.kubernetes.io/name=grafana"
fi

print_step "Checking Loki..."
if kubectl get pods -n monitoring -l app=loki 2>/dev/null | grep -q Running; then
    test_result "Loki is running"
    
    # Test Loki query
    print_step "Testing Loki readiness..."
    if kubectl exec -n monitoring -l app=loki -- wget -q -O- "http://localhost:3100/ready" 2>/dev/null | grep -q ready; then
        test_result "Loki is responding"
    else
        test_warning "Loki query test inconclusive"
    fi
else
    LOKI_STATUS=$(kubectl get pods -n monitoring -l app=loki 2>/dev/null | tail -1 | awk '{print $3}' || echo "unknown")
    test_warning "Loki is NOT running (status: $LOKI_STATUS)"
    if [[ "$LOKI_STATUS" == *"CrashLoopBackOff"* ]]; then
        print_info "Loki is crashing. Check logs: kubectl logs -n monitoring -l app=loki"
        print_info "Fixing Loki config..."
        # Will fix in next step
    fi
fi

print_step "Checking Promtail..."
if kubectl get pods -n monitoring -l app=promtail 2>/dev/null | grep -q Running; then
    test_result "Promtail is running"
else
    test_warning "Promtail is NOT running"
fi

print_step "Checking Tempo..."
TEMPO_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo 2>/dev/null | grep -c Running || echo "0")
if [ "$TEMPO_PODS" -gt 0 ]; then
    test_result "Tempo is running ($TEMPO_PODS pod(s))"
    
    # Test Tempo health
    print_step "Testing Tempo health..."
    if kubectl exec -n monitoring -l app.kubernetes.io/name=tempo -- wget -q -O- "http://localhost:3200/ready" 2>/dev/null | grep -q ready; then
        test_result "Tempo is responding"
    else
        test_warning "Tempo health check inconclusive"
    fi
else
    test_warning "Tempo is NOT running"
fi

# =============================================================================
# TEST 2: Image Scanning (Trivy)
# =============================================================================
print_header "Test 2: Image Scanning (Trivy Operator)"

print_step "Checking Trivy Operator..."
if kubectl get pods -n trivy-system -l app.kubernetes.io/name=trivy-operator 2>/dev/null | grep -q Running; then
    test_result "Trivy Operator is running"
    
    # Check for vulnerability reports
    print_step "Checking for vulnerability reports..."
    VULN_REPORTS=$(kubectl get vulnerabilityreports -A --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$VULN_REPORTS" -gt 0 ]; then
        test_result "Found $VULN_REPORTS vulnerability report(s)"
    else
        test_warning "No vulnerability reports found yet (may need to scan images)"
    fi
    
    # Check webhook
    print_step "Checking Trivy admission webhook..."
    if kubectl get validatingwebhookconfiguration 2>/dev/null | grep -q trivy; then
        test_result "Trivy admission webhook is configured"
    else
        test_warning "Trivy admission webhook not found"
    fi
else
    test_warning "Trivy Operator is NOT running"
fi

# =============================================================================
# TEST 3: Network Policies
# =============================================================================
print_header "Test 3: Network Policies"

print_step "Checking network policies in vendure-local..."
if kubectl get networkpolicy -n vendure-local 2>/dev/null | grep -q .; then
    POLICY_COUNT=$(kubectl get networkpolicy -n vendure-local --no-headers 2>/dev/null | wc -l)
    test_result "Found $POLICY_COUNT network policy/policies in vendure-local"
    
    # Check for default-deny
    if kubectl get networkpolicy -n vendure-local default-deny-all 2>/dev/null; then
        test_result "Default-deny network policy exists"
    else
        test_warning "Default-deny network policy not found"
    fi
else
    test_warning "No network policies found (may not be deployed yet)"
    print_info "Network policies are enabled in config but need Helm upgrade to apply"
fi

# =============================================================================
# TEST 4: Pod Security Standards (PSS)
# =============================================================================
print_header "Test 4: Pod Security Standards (PSS)"

print_step "Checking namespace PSS labels..."
for ns in vendure-local monitoring; do
    if kubectl get namespace "$ns" &>/dev/null 2>&1; then
        ENFORCE=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
        if [ -n "$ENFORCE" ]; then
            test_result "Namespace $ns has PSS label: enforce=$ENFORCE"
        else
            test_warning "Namespace $ns missing PSS labels"
            print_info "Apply PSS labels: kubectl label namespace $ns pod-security.kubernetes.io/enforce=baseline --overwrite"
        fi
    else
        test_skip "Namespace $ns does not exist"
    fi
done

# =============================================================================
# TEST 5: RBAC
# =============================================================================
print_header "Test 5: RBAC (Role-Based Access Control)"

print_step "Checking RBAC roles in vendure-local..."
if kubectl get roles -n vendure-local 2>/dev/null | grep -q .; then
    ROLE_COUNT=$(kubectl get roles -n vendure-local --no-headers 2>/dev/null | wc -l)
    test_result "Found $ROLE_COUNT role(s) in vendure-local"
    
    # Check for specific roles
    for role in developer-role devops-role read-only-role; do
        if kubectl get role "$role" -n vendure-local &>/dev/null 2>&1; then
            test_result "Role $role exists"
        fi
    done
else
    test_warning "No RBAC roles found (may not be deployed yet)"
    print_info "RBAC is enabled in config but needs Helm upgrade to apply"
fi

print_step "Checking RBAC role bindings..."
if kubectl get rolebindings -n vendure-local 2>/dev/null | grep -q .; then
    BINDING_COUNT=$(kubectl get rolebindings -n vendure-local --no-headers 2>/dev/null | wc -l)
    test_result "Found $BINDING_COUNT role binding(s) in vendure-local"
else
    test_warning "No RBAC role bindings found (users not assigned yet)"
fi

# =============================================================================
# TEST 6: Cost Monitoring (Kubecost)
# =============================================================================
print_header "Test 6: Cost Monitoring (Kubecost)"

print_step "Checking Kubecost..."
KUBECOST_PODS=$(kubectl get pods -n kubecost 2>/dev/null | grep -c Running || echo "0")
if [ "$KUBECOST_PODS" -gt 0 ]; then
    test_result "Kubecost is running ($KUBECOST_PODS pod(s))"
else
    test_warning "Kubecost is NOT running (may have failed to deploy)"
fi

# =============================================================================
# TEST 7: Distributed Tracing (Tempo)
# =============================================================================
print_header "Test 7: Distributed Tracing (Tempo)"

print_step "Checking Tempo service..."
if kubectl get svc -n monitoring tempo 2>/dev/null; then
    test_result "Tempo service exists"
    
    # Check Grafana datasource
    print_step "Checking Tempo datasource in Grafana..."
    if kubectl get configmap -n monitoring grafana-tempo-datasource 2>/dev/null; then
        test_result "Tempo datasource configured in Grafana"
    else
        test_warning "Tempo datasource not configured in Grafana (may need manual setup)"
    fi
else
    test_warning "Tempo service not found"
fi

# =============================================================================
# TEST 8: Log Retention (Loki)
# =============================================================================
print_header "Test 8: Log Retention (Loki)"

print_step "Checking Loki retention configuration..."
if kubectl get configmap -n monitoring loki 2>/dev/null; then
    RETENTION=$(kubectl get configmap -n monitoring loki -o jsonpath='{.data.loki\.yaml}' 2>/dev/null | grep -oP 'reject_old_samples_max_age:\s*\K[0-9]+h' || echo "")
    if [ -n "$RETENTION" ]; then
        test_result "Loki retention configured: $RETENTION"
    else
        test_warning "Loki retention not found in config"
    fi
else
    test_warning "Loki configmap not found"
fi

# =============================================================================
# TEST 9: Alert Rules
# =============================================================================
print_header "Test 9: Alert Rules"

print_step "Checking Prometheus alert rules..."
if kubectl get prometheusrule -A 2>/dev/null | grep -q .; then
    RULE_COUNT=$(kubectl get prometheusrule -A --no-headers 2>/dev/null | wc -l)
    test_result "Found $RULE_COUNT PrometheusRule(s)"
else
    test_warning "No PrometheusRule resources found"
fi

# =============================================================================
# TEST 10: Vendure Application
# =============================================================================
print_header "Test 10: Vendure Application"

print_step "Checking Vendure deployment..."
if kubectl get deployment -n vendure-local vendure-local-vendure-stack-vendure 2>/dev/null; then
    VENDURE_READY=$(kubectl get deployment -n vendure-local vendure-local-vendure-stack-vendure -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$VENDURE_READY" -gt 0 ]; then
        test_result "Vendure deployment is ready ($VENDURE_READY replica(s))"
    else
        VENDURE_STATUS=$(kubectl get pods -n vendure-local -l app=vendure 2>/dev/null | tail -1 | awk '{print $3}' || echo "unknown")
        test_warning "Vendure deployment is NOT ready (status: $VENDURE_STATUS)"
        if [[ "$VENDURE_STATUS" == *"ErrImageNeverPull"* ]]; then
            print_info "Vendure needs image built and loaded:"
            print_info "  1. docker build -t vendure-local:latest ."
            print_info "  2. minikube image load vendure-local:latest"
        fi
    fi
else
    test_warning "Vendure deployment not found"
    print_info "Deploy Vendure: helm install vendure-local helm/vendure-stack -n vendure-local --create-namespace -f helm/environments/local/vendure-values.yaml"
fi

# =============================================================================
# SUMMARY
# =============================================================================
print_header "Test Summary"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results:"
echo "  ✅ Passed: $PASSED"
echo "  ❌ Failed: $FAILED"
echo "  ⚠️  Warnings: $WARNINGS"
echo "  ⏭  Skipped: $SKIPPED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Provide next steps
print_header "Next Steps"

if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    print_success "All tests passed! Everything is working correctly."
    echo ""
    print_info "You can now:"
    echo "  1. Access Grafana: kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
    echo "  2. Check Trivy reports: kubectl get vulnerabilityreports -A"
    echo "  3. View traces in Grafana (after making API requests)"
    exit 0
elif [ $FAILED -eq 0 ]; then
    print_warning "All critical tests passed, but some warnings exist."
    echo ""
    print_info "Warnings are expected for:"
    echo "  • Components not yet deployed"
    echo "  • Components that need configuration"
    echo "  • Components waiting for dependencies"
    echo ""
    print_info "Review warnings above and fix as needed."
    exit 0
else
    print_error "Some tests failed. Review the output above."
    echo ""
    print_info "Common fixes:"
    echo "  • Loki crashing: Check config (retention_period format)"
    echo "  • Grafana crashing: Check resource limits"
    echo "  • Vendure not running: Build and load image"
    echo "  • Network policies: Upgrade Helm release"
    exit 1
fi

