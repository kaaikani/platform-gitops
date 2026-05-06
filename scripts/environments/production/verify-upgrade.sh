#!/bin/bash
# =============================================================================
# POST-UPGRADE VERIFICATION SCRIPT
# =============================================================================
# Verifies cluster health and application functionality after upgrade
#
# Usage:
#   ./helm/environments/production/verify-upgrade.sh
# =============================================================================

set -e

CLUSTER_NAME="vendure-prod"
REGION="ap-south-1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔍 POST-UPGRADE VERIFICATION${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# =============================================================================
# CLUSTER VERSION
# =============================================================================

echo -e "${YELLOW}[1/8] Verifying cluster version...${NC}"
CLUSTER_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.version' --output text)
CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.status' --output text)

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo -e "${GREEN}✓ Cluster status: $CLUSTER_STATUS${NC}"
else
    echo -e "${RED}❌ Cluster status: $CLUSTER_STATUS${NC}"
fi

echo -e "${GREEN}✓ Cluster version: $CLUSTER_VERSION${NC}"
echo ""

# =============================================================================
# NODE STATUS
# =============================================================================

echo -e "${YELLOW}[2/8] Verifying node status...${NC}"
NODES=$(kubectl get nodes --no-headers)
NODE_COUNT=$(echo "$NODES" | wc -l)
READY_NODES=$(echo "$NODES" | grep -c "Ready" || echo "0")
NOT_READY_NODES=$(echo "$NODES" | grep -v "Ready" | grep -v "^$" | wc -l || echo "0")

echo "   Total nodes: $NODE_COUNT"
echo "   Ready nodes: $READY_NODES"
if [ "$NOT_READY_NODES" -gt 0 ]; then
    echo -e "${RED}   Not ready nodes: $NOT_READY_NODES${NC}"
    echo "$NODES" | grep -v "Ready"
else
    echo -e "${GREEN}✓ All nodes are Ready${NC}"
fi
echo ""

# =============================================================================
# POD STATUS
# =============================================================================

echo -e "${YELLOW}[3/8] Verifying pod status...${NC}"
ALL_PODS=$(kubectl get pods -A --no-headers)
POD_COUNT=$(echo "$ALL_PODS" | wc -l)
RUNNING_PODS=$(echo "$ALL_PODS" | grep -c "Running" || echo "0")
FAILED_PODS=$(echo "$ALL_PODS" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | wc -l || echo "0")
PENDING_PODS=$(echo "$ALL_PODS" | grep -c "Pending" || echo "0")

echo "   Total pods: $POD_COUNT"
echo "   Running: $RUNNING_PODS"

if [ "$FAILED_PODS" -gt 0 ]; then
    echo -e "${RED}   Failed pods: $FAILED_PODS${NC}"
    echo "$ALL_PODS" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff"
else
    echo -e "${GREEN}✓ No failed pods${NC}"
fi

if [ "$PENDING_PODS" -gt 0 ]; then
    echo -e "${YELLOW}   Pending pods: $PENDING_PODS${NC}"
    echo "$ALL_PODS" | grep "Pending" | head -5
fi
echo ""

# =============================================================================
# SYSTEM COMPONENTS
# =============================================================================

echo -e "${YELLOW}[4/8] Verifying system components...${NC}"
SYSTEM_NAMESPACES=("kube-system" "kube-public" "kube-node-lease")

for NS in "${SYSTEM_NAMESPACES[@]}"; do
    if kubectl get namespace "$NS" &>/dev/null; then
        FAILED=$(kubectl get pods -n "$NS" --field-selector status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$FAILED" -eq 0 ]; then
            echo -e "${GREEN}✓ $NS: All pods running${NC}"
        else
            echo -e "${YELLOW}⚠️  $NS: $FAILED pods not running${NC}"
        fi
    fi
done
echo ""

# =============================================================================
# APPLICATION PODS
# =============================================================================

echo -e "${YELLOW}[5/8] Verifying application pods...${NC}"
APP_NAMESPACES=("vendure-production" "monitoring" "kubecost")

for NS in "${APP_NAMESPACES[@]}"; do
    if kubectl get namespace "$NS" &>/dev/null 2>/dev/null; then
        PODS=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null || echo "")
        if [ -n "$PODS" ]; then
            RUNNING=$(echo "$PODS" | grep -c "Running" || echo "0")
            TOTAL=$(echo "$PODS" | wc -l || echo "0")
            echo "   $NS: $RUNNING/$TOTAL pods running"
            
            FAILED=$(echo "$PODS" | grep -E "Error|CrashLoopBackOff" | wc -l || echo "0")
            if [ "$FAILED" -gt 0 ]; then
                echo -e "${RED}     Failed pods:${NC}"
                echo "$PODS" | grep -E "Error|CrashLoopBackOff" | head -3
            fi
        fi
    fi
done
echo ""

# =============================================================================
# INGRESS & SERVICES
# =============================================================================

echo -e "${YELLOW}[6/8] Verifying ingress and services...${NC}"
INGRESS_COUNT=$(kubectl get ingress -A --no-headers 2>/dev/null | wc -l || echo "0")
SERVICE_COUNT=$(kubectl get svc -A --no-headers 2>/dev/null | wc -l || echo "0")

echo "   Ingress: $INGRESS_COUNT"
echo "   Services: $SERVICE_COUNT"

# Check if ALB is healthy
ALB_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$ALB_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓ ALB Controller: $ALB_PODS pods running${NC}"
else
    echo -e "${YELLOW}⚠️  ALB Controller: Not running${NC}"
fi
echo ""

# =============================================================================
# RESOURCE USAGE
# =============================================================================

echo -e "${YELLOW}[7/8] Checking resource usage...${NC}"
if kubectl top nodes &>/dev/null 2>&1; then
    echo "   Node resource usage:"
    kubectl top nodes --no-headers | head -5
    echo ""
    echo "   Top resource consumers:"
    kubectl top pods -A --sort-by=memory --no-headers | head -5
else
    echo -e "${YELLOW}⚠️  Metrics server not available${NC}"
fi
echo ""

# =============================================================================
# VELERO BACKUPS
# =============================================================================

echo -e "${YELLOW}[8/8] Verifying Velero backups...${NC}"
if kubectl get deployment velero -n velero &>/dev/null 2>&1; then
    VELERO_POD=$(kubectl get pods -n velero -l component=velero --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$VELERO_POD" -gt 0 ]; then
        echo -e "${GREEN}✓ Velero: Running${NC}"
        
        if command -v velero &>/dev/null; then
            RECENT_BACKUP=$(velero backup get --output json 2>/dev/null | jq -r '.items[0].metadata.name' 2>/dev/null || echo "")
            if [ -n "$RECENT_BACKUP" ]; then
                echo "   Recent backup: $RECENT_BACKUP"
            fi
        fi
    else
        echo -e "${YELLOW}⚠️  Velero: Not running${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Velero: Not installed${NC}"
fi
echo ""

# =============================================================================
# SUMMARY
# =============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📊 VERIFICATION SUMMARY${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Version: $CLUSTER_VERSION"
echo "Status: $CLUSTER_STATUS"
echo ""
echo "Nodes: $READY_NODES/$NODE_COUNT ready"
echo "Pods: $RUNNING_PODS/$POD_COUNT running"

if [ "$FAILED_PODS" -gt 0 ] || [ "$NOT_READY_NODES" -gt 0 ]; then
    echo ""
    echo -e "${RED}⚠️  ISSUES DETECTED${NC}"
    echo "   Review the output above for details"
    echo ""
    echo "Next steps:"
    echo "  1. Check pod logs: kubectl logs <pod-name> -n <namespace>"
    echo "  2. Check events: kubectl get events -A --sort-by='.lastTimestamp'"
    echo "  3. Review upgrade guide for troubleshooting"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ ALL CHECKS PASSED${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Monitor applications for 24-48 hours"
    echo "  2. Test application functionality"
    echo "  3. Check application logs for errors"
    echo "  4. Verify metrics and monitoring"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

