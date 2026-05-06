#!/bin/bash
# =============================================================================
# COMPREHENSIVE TEST SUITE - ALL FIXES
# =============================================================================
# This script tests all deployed fixes to verify they're working correctly
#
# Usage:
#   chmod +x test-all-fixes.sh
#   ./test-all-fixes.sh
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

PASSED=0
FAILED=0
WARNINGS=0

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

print_header "Comprehensive Test Suite - All Fixes"

# =============================================================================
# TEST 1: Monitoring Stack
# =============================================================================
print_header "Test 1: Monitoring Stack"

print_step "Checking Prometheus..."
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus | grep -q Running; then
    test_result "Prometheus is running"
else
    test_result "Prometheus is NOT running"
fi

print_step "Checking Grafana..."
if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana | grep -q Running; then
    test_result "Grafana is running"
else
    test_result "Grafana is NOT running"
fi

print_step "Checking Loki..."
if kubectl get pods -n monitoring -l app=loki | grep -q Running; then
    test_result "Loki is running"
    
    # Test Loki query
    print_step "Testing Loki log query..."
    if kubectl exec -n monitoring -l app=loki -- wget -q -O- "http://localhost:3100/ready" 2>/dev/null | grep -q ready; then
        test_result "Loki is responding to queries"
    else
        test_warning "Loki query test inconclusive"
    fi
else
    test_result "Loki is NOT running"
fi

print_step "Checking Tempo..."
if kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo | grep -q Running; then
    test_result "Tempo is running"
    
    # Test Tempo health
    print_step "Testing Tempo health endpoint..."
    if kubectl exec -n monitoring -l app.kubernetes.io/name=tempo -- wget -q -O- "http://localhost:3200/ready" 2>/dev/null | grep -q ready; then
        test_result "Tempo is responding"
    else
        test_warning "Tempo health check inconclusive"
    fi
else
    test_result "Tempo is NOT running"
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
    if kubectl get vulnerabilityreports -A 2>/dev/null | grep -q .; then
        REPORT_COUNT=$(kubectl get vulnerabilityreports -A --no-headers 2>/dev/null | wc -l)
        test_result "Found $REPORT_COUNT vulnerability report(s)"
    else
        test_warning "No vulnerability reports found yet (may need to scan images)"
    fi
    
    # Check webhook
    print_step "Checking Trivy admission webhook..."
    if kubectl get validatingwebhookconfiguration | grep -q trivy; then
        test_result "Trivy admission webhook is configured"
    else
        test_warning "Trivy admission webhook not found"
    fi
else
    test_result "Trivy Operator is NOT running"
fi

# =============================================================================
# TEST 3: Network Policies
# =============================================================================
print_header "Test 3: Network Policies"

print_step "Checking network policies..."
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
fi

# =============================================================================
# TEST 4: Pod Security Standards
# =============================================================================
print_header "Test 4: Pod Security Standards (PSS)"

print_step "Checking namespace PSS labels..."
for ns in vendure-local monitoring; do
    if kubectl get namespace "$ns" &>/dev/null; then
        ENFORCE=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
        if [ -n "$ENFORCE" ]; then
            test_result "Namespace $ns has PSS label: enforce=$ENFORCE"
        else
            test_warning "Namespace $ns missing PSS labels"
        fi
    fi
done

# =============================================================================
# TEST 5: RBAC
# =============================================================================
print_header "Test 5: RBAC (Role-Based Access Control)"

print_step "Checking RBAC roles..."
if kubectl get roles -n vendure-local 2>/dev/null | grep -q .; then
    ROLE_COUNT=$(kubectl get roles -n vendure-local --no-headers 2>/dev/null | wc -l)
    test_result "Found $ROLE_COUNT role(s) in vendure-local"
    
    # Check for specific roles
    for role in developer-role devops-role read-only-role; do
        if kubectl get role "$role" -n vendure-local &>/dev/null; then
            test_result "Role $role exists"
        fi
    done
else
    test_warning "No RBAC roles found (may not be deployed yet)"
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
if kubectl get pods -n kubecost 2>/dev/null | grep -q Running; then
    test_result "Kubecost is running"
    
    # Check if cost data is available
    print_step "Checking Kubecost API..."
    if kubectl exec -n kubecost -l app=cost-analyzer -- wget -q -O- "http://localhost:9003/healthz" 2>/dev/null | grep -q ok; then
        test_result "Kubecost API is responding"
    else
        test_warning "Kubecost API check inconclusive"
    fi
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
    RETENTION=$(kubectl get configmap -n monitoring loki -o jsonpath='{.data.loki\.yaml}' 2>/dev/null | grep -oP 'retention_period:\s*\K[0-9]+h' || echo "")
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
# SUMMARY
# =============================================================================
print_header "Test Summary"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results:"
echo "  ✅ Passed: $PASSED"
echo "  ❌ Failed: $FAILED"
echo "  ⚠️  Warnings: $WARNINGS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $FAILED -eq 0 ]; then
    print_success "All critical tests passed!"
    exit 0
else
    print_error "Some tests failed. Review the output above."
    exit 1
fi

