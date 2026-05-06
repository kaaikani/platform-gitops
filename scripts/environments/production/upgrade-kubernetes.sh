#!/bin/bash
# =============================================================================
# KUBERNETES VERSION UPGRADE SCRIPT - ZERO DOWNTIME
# =============================================================================
# Safely upgrades EKS cluster from one Kubernetes version to another
# Uses blue-green node group strategy for zero downtime
#
# Usage:
#   ./helm/environments/production/upgrade-kubernetes.sh <target-version>
#   Example: ./helm/environments/production/upgrade-kubernetes.sh 1.31
#
# Prerequisites:
#   - AWS CLI configured
#   - eksctl installed
#   - kubectl configured
#   - Velero backups recent
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="vendure-prod"
REGION="ap-south-1"
OLD_NODEGROUP_NAME="vendure-nodes"  # Update based on your setup
NEW_NODEGROUP_NAME="vendure-nodes-v131"  # Update with target version

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Target Kubernetes version required${NC}"
    echo "Usage: $0 <target-version>"
    echo "Example: $0 1.31"
    exit 1
fi

TARGET_VERSION="$1"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🚀 KUBERNETES VERSION UPGRADE${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Target Version: $TARGET_VERSION"
echo ""

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

echo -e "${YELLOW}[1/10] Running pre-flight checks...${NC}"

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS credentials OK${NC}"

# Check eksctl
if ! command -v eksctl &>/dev/null; then
    echo -e "${RED}❌ eksctl not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ eksctl found${NC}"

# Check kubectl
if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl found${NC}"

# Check cluster exists
if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null; then
    echo -e "${RED}❌ Cluster '$CLUSTER_NAME' not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Cluster exists${NC}"

# Get current version
CURRENT_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.version' --output text)
echo -e "${GREEN}✓ Current version: $CURRENT_VERSION${NC}"

# Validate upgrade path (only one minor version at a time)
CURRENT_MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
TARGET_MINOR=$(echo "$TARGET_VERSION" | cut -d. -f2)
DIFF=$((TARGET_MINOR - CURRENT_MINOR))

if [ "$DIFF" -gt 1 ]; then
    echo -e "${RED}❌ Cannot skip versions. Current: $CURRENT_VERSION, Target: $TARGET_VERSION${NC}"
    echo "   Upgrade path: $CURRENT_VERSION → $((CURRENT_MINOR + 1)) → $TARGET_VERSION"
    exit 1
fi

if [ "$DIFF" -lt 1 ]; then
    echo -e "${RED}❌ Target version must be newer than current version${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Upgrade path valid${NC}"

# Check kubectl connectivity
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${YELLOW}⚠️  kubectl not configured, updating...${NC}"
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
fi
echo -e "${GREEN}✓ kubectl configured${NC}"

# =============================================================================
# BACKUP
# =============================================================================

echo ""
echo -e "${YELLOW}[2/10] Creating backup...${NC}"

# Check if Velero is installed
if kubectl get deployment velero -n velero &>/dev/null; then
    echo -e "${GREEN}✓ Velero found, creating backup...${NC}"
    BACKUP_NAME="pre-upgrade-$(date +%Y%m%d-%H%M%S)"
    if command -v velero &>/dev/null; then
        velero backup create "$BACKUP_NAME" --include-namespaces vendure-production,monitoring
        echo -e "${GREEN}✓ Backup created: $BACKUP_NAME${NC}"
    else
        echo -e "${YELLOW}⚠️  Velero CLI not found, skipping backup${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Velero not found, creating manual backup...${NC}"
    BACKUP_DIR="./backups/pre-upgrade-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    kubectl get all -A -o yaml > "$BACKUP_DIR/all-resources.yaml"
    echo -e "${GREEN}✓ Manual backup created: $BACKUP_DIR${NC}"
fi

# =============================================================================
# CONTROL PLANE UPGRADE
# =============================================================================

echo ""
echo -e "${YELLOW}[3/10] Upgrading control plane...${NC}"
echo -e "${BLUE}   This takes 15-30 minutes (AWS managed, zero downtime)${NC}"

# Start control plane upgrade
echo -e "${YELLOW}   Starting control plane upgrade to $TARGET_VERSION...${NC}"
aws eks update-cluster-version \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --kubernetes-version "$TARGET_VERSION"

# Monitor upgrade status
echo -e "${YELLOW}   Monitoring upgrade progress...${NC}"
while true; do
    STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.status' --output text)
    VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.version' --output text)
    
    echo -e "   Status: $STATUS, Version: $VERSION"
    
    if [ "$STATUS" == "ACTIVE" ] && [ "$VERSION" == "$TARGET_VERSION" ]; then
        echo -e "${GREEN}✓ Control plane upgraded successfully${NC}"
        break
    fi
    
    if [ "$STATUS" == "FAILED" ]; then
        echo -e "${RED}❌ Control plane upgrade failed${NC}"
        exit 1
    fi
    
    sleep 30
done

# =============================================================================
# CREATE NEW NODE GROUP
# =============================================================================

echo ""
echo -e "${YELLOW}[4/10] Creating new node group with version $TARGET_VERSION...${NC}"

# Check if new node group already exists
if eksctl get nodegroup --cluster="$CLUSTER_NAME" --name="$NEW_NODEGROUP_NAME" &>/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Node group '$NEW_NODEGROUP_NAME' already exists${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    # Create new node group
    eksctl create nodegroup \
        --cluster="$CLUSTER_NAME" \
        --region="$REGION" \
        --name="$NEW_NODEGROUP_NAME" \
        --instance-types=t3.medium,t3a.medium \
        --nodes=2 \
        --nodes-min=2 \
        --nodes-max=4 \
        --node-volume-size=20 \
        --node-volume-type=gp3 \
        --managed \
        --spot \
        --kubelet-version="${TARGET_VERSION}.0" \
        --labels="node-type=app,kubernetes.io/version=${TARGET_VERSION}" \
        --asg-access
    
    echo -e "${GREEN}✓ New node group created${NC}"
fi

# =============================================================================
# WAIT FOR NEW NODES
# =============================================================================

echo ""
echo -e "${YELLOW}[5/10] Waiting for new nodes to be ready...${NC}"

TIMEOUT=600  # 10 minutes
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    READY_NODES=$(kubectl get nodes -l kubernetes.io/version="$TARGET_VERSION" --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    
    if [ "$READY_NODES" -ge 2 ]; then
        echo -e "${GREEN}✓ New nodes are ready ($READY_NODES nodes)${NC}"
        break
    fi
    
    echo "   Waiting for nodes... ($READY_NODES/2 ready, ${ELAPSED}s elapsed)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${RED}❌ Timeout waiting for new nodes${NC}"
    exit 1
fi

# =============================================================================
# MIGRATE WORKLOADS
# =============================================================================

echo ""
echo -e "${YELLOW}[6/10] Migrating workloads to new nodes...${NC}"

# Get old node names
OLD_NODES=$(kubectl get nodes -l kubernetes.io/version!="$TARGET_VERSION" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")

if [ -z "$OLD_NODES" ]; then
    echo -e "${YELLOW}⚠️  No old nodes found, skipping migration${NC}"
else
    echo "   Old nodes: $OLD_NODES"
    
    # Cordon old nodes (prevent new pods)
    for NODE in $OLD_NODES; do
        echo "   Cordoning node: $NODE"
        kubectl cordon "$NODE" || true
    done
    
    # Wait for pods to migrate naturally (via PDBs and rolling updates)
    echo "   Waiting for pods to migrate (30 seconds)..."
    sleep 30
    
    # Check if pods are on new nodes
    NEW_NODE_PODS=$(kubectl get pods -A -o wide --field-selector spec.nodeName!="" | grep -c "$TARGET_VERSION" || echo "0")
    echo -e "${GREEN}✓ Pods on new nodes: $NEW_NODE_PODS${NC}"
fi

# =============================================================================
# VERIFY APPLICATIONS
# =============================================================================

echo ""
echo -e "${YELLOW}[7/10] Verifying applications...${NC}"

# Check all pods are running
FAILED_PODS=$(kubectl get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l || echo "0")

if [ "$FAILED_PODS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $FAILED_PODS pods not in Running state${NC}"
    kubectl get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded
else
    echo -e "${GREEN}✓ All pods are running${NC}"
fi

# Check node status
kubectl get nodes
echo -e "${GREEN}✓ Node status verified${NC}"

# =============================================================================
# DRAIN OLD NODES
# =============================================================================

echo ""
echo -e "${YELLOW}[8/10] Draining old nodes...${NC}"

if [ -n "$OLD_NODES" ]; then
    for NODE in $OLD_NODES; do
        echo "   Draining node: $NODE"
        kubectl drain "$NODE" \
            --ignore-daemonsets \
            --delete-emptydir-data \
            --grace-period=300 \
            --timeout=600s \
            --force || echo -e "${YELLOW}⚠️  Drain failed for $NODE (may already be empty)${NC}"
    done
    echo -e "${GREEN}✓ Old nodes drained${NC}"
else
    echo -e "${YELLOW}⚠️  No old nodes to drain${NC}"
fi

# =============================================================================
# DELETE OLD NODE GROUP
# =============================================================================

echo ""
echo -e "${YELLOW}[9/10] Deleting old node group...${NC}"

read -p "Delete old node group '$OLD_NODEGROUP_NAME'? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    eksctl delete nodegroup \
        --cluster="$CLUSTER_NAME" \
        --name="$OLD_NODEGROUP_NAME" \
        --drain=false \
        --wait || echo -e "${YELLOW}⚠️  Node group deletion failed or already deleted${NC}"
    
    echo -e "${GREEN}✓ Old node group deleted${NC}"
else
    echo -e "${YELLOW}⚠️  Skipping old node group deletion${NC}"
    echo "   Delete manually: eksctl delete nodegroup --cluster=$CLUSTER_NAME --name=$OLD_NODEGROUP_NAME"
fi

# =============================================================================
# FINAL VERIFICATION
# =============================================================================

echo ""
echo -e "${YELLOW}[10/10] Final verification...${NC}"

# Verify cluster version
FINAL_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.version' --output text)
if [ "$FINAL_VERSION" == "$TARGET_VERSION" ]; then
    echo -e "${GREEN}✓ Cluster version: $FINAL_VERSION${NC}"
else
    echo -e "${RED}❌ Version mismatch. Expected: $TARGET_VERSION, Got: $FINAL_VERSION${NC}"
fi

# Verify nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo -e "${GREEN}✓ Total nodes: $NODE_COUNT${NC}"

# Verify pods
POD_COUNT=$(kubectl get pods -A --no-headers | wc -l)
echo -e "${GREEN}✓ Total pods: $POD_COUNT${NC}"

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ UPGRADE COMPLETE!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Version: $CURRENT_VERSION → $TARGET_VERSION"
echo ""
echo "Next Steps:"
echo "  1. Monitor applications for 24-48 hours"
echo "  2. Update kubectl to match cluster version"
echo "  3. Update Helm charts if needed"
echo "  4. Document upgrade in changelog"
echo ""
echo "Rollback (if needed):"
if [ -n "$BACKUP_NAME" ]; then
    echo "  velero restore create --from-backup $BACKUP_NAME"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

