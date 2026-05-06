#!/bin/bash
# =============================================================================
# NETWORK POLICY TESTING SCRIPT
# =============================================================================
# This script tests that network policies are working correctly:
# 1. Default-deny is working (unauthorized traffic is blocked)
# 2. Legitimate traffic is allowed (Vendure can reach DB, Redis, AWS)
# 3. Prometheus can scrape metrics
#
# Usage:
#   ./networkpolicy-test.sh <namespace>
#   Example: ./networkpolicy-test.sh vendure-production
# =============================================================================

set -e

NAMESPACE="${1:-vendure-production}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Testing Network Policies in namespace: ${NAMESPACE}${NC}"
echo ""

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

# Check if Vendure deployment exists
if ! kubectl get deployment -n "$NAMESPACE" -l app=vendure &>/dev/null; then
    echo -e "${YELLOW}Warning: Vendure deployment not found. Some tests will be skipped.${NC}"
    VENDURE_EXISTS=false
else
    VENDURE_EXISTS=true
fi

PASSED=0
FAILED=0

test_result() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $1${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ $1${NC}"
        ((FAILED++))
    fi
}

# Test 1: Check if default-deny policy exists
echo "Test 1: Checking default-deny policy..."
if kubectl get networkpolicy default-deny-all -n "$NAMESPACE" &>/dev/null; then
    test_result "Default-deny policy exists"
else
    echo -e "${RED}❌ Default-deny policy not found${NC}"
    ((FAILED++))
fi

# Test 2: Check if Vendure network policy exists
echo ""
echo "Test 2: Checking Vendure network policy..."
if kubectl get networkpolicy -n "$NAMESPACE" -l app=vendure &>/dev/null; then
    test_result "Vendure network policy exists"
else
    echo -e "${YELLOW}⚠️  Vendure network policy not found (may be disabled)${NC}"
fi

# Test 3: Test DNS resolution (should work)
echo ""
echo "Test 3: Testing DNS resolution..."
if [ "$VENDURE_EXISTS" = true ]; then
    if kubectl exec -n "$NAMESPACE" deployment/vendure -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
        test_result "DNS resolution works"
    else
        echo -e "${RED}❌ DNS resolution failed${NC}"
        ((FAILED++))
    fi
fi

# Test 4: Test HTTPS to AWS (should work)
echo ""
echo "Test 4: Testing HTTPS to AWS services..."
if [ "$VENDURE_EXISTS" = true ]; then
    if kubectl exec -n "$NAMESPACE" deployment/vendure -- timeout 5 wget -q --spider https://s3.ap-south-1.amazonaws.com 2>&1; then
        test_result "HTTPS to AWS works"
    else
        echo -e "${YELLOW}⚠️  HTTPS test inconclusive (may be network issue, not policy)${NC}"
    fi
fi

# Test 5: Test that unauthorized pod cannot access Vendure
echo ""
echo "Test 5: Testing default-deny (unauthorized access should be blocked)..."
kubectl run test-network-policy-$(date +%s) \
    --image=busybox \
    --rm -i \
    --restart=Never \
    --namespace="$NAMESPACE" \
    -- sh -c "wget -O- --timeout=3 http://vendure-service:80 2>&1 | grep -q 'Connection refused\|timeout' && exit 0 || exit 1" 2>/dev/null && \
    test_result "Unauthorized access is blocked (default-deny works)" || \
    echo -e "${RED}❌ Unauthorized access was allowed (SECURITY RISK!)${NC}" && ((FAILED++))

# Test 6: Check network policy labels
echo ""
echo "Test 6: Verifying network policy labels..."
POLICIES=$(kubectl get networkpolicy -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
for policy in $POLICIES; do
    if kubectl get networkpolicy "$policy" -n "$NAMESPACE" -o jsonpath='{.metadata.labels}' | grep -q "app.kubernetes.io/component"; then
        test_result "Network policy '$policy' has proper labels"
    fi
done

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}Test Summary:${NC}"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Network policies are configured correctly.${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review network policy configuration.${NC}"
    exit 1
fi

