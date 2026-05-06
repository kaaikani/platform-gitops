#!/bin/bash
# =============================================================================
# ARGOCD GITOPS SETUP SCRIPT
# =============================================================================
# Installs and configures ArgoCD for GitOps-based continuous deployment
#
# Usage:
#   ./helm/environments/production/setup-argocd.sh [options]
#
# Options:
#   --git-repo-url <url>     Git repository URL (required)
#   --git-username <user>    Git username (for HTTPS)
#   --git-token <token>      Git personal access token (for HTTPS)
#   --ssh-key <path>         Path to SSH private key (for SSH)
#   --skip-install           Skip ArgoCD installation (already installed)
#   --skip-repo-config       Skip repository configuration
#
# Example:
#   ./helm/environments/production/setup-argocd.sh \
#     --git-repo-url https://github.com/your-org/vendure-k8s.git \
#     --git-username your-username \
#     --git-token ghp_xxxxxxxxxxxx
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
GIT_REPO_URL=""
GIT_USERNAME=""
GIT_TOKEN=""
SSH_KEY_PATH=""
SKIP_INSTALL=false
SKIP_REPO_CONFIG=false
ARGOCD_NAMESPACE="argocd"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🚀 ARGOCD GITOPS SETUP${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --git-repo-url)
            GIT_REPO_URL="$2"
            shift 2
            ;;
        --git-username)
            GIT_USERNAME="$2"
            shift 2
            ;;
        --git-token)
            GIT_TOKEN="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        --skip-repo-config)
            SKIP_REPO_CONFIG=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

echo -e "${YELLOW}[1/6] Running pre-flight checks...${NC}"

# Check kubectl
if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl found${NC}"

# Check cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Cannot connect to cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Cluster connected${NC}"

# Check if ArgoCD already installed
if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
    if kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        echo -e "${YELLOW}⚠️  ArgoCD already installed${NC}"
        if [ "$SKIP_INSTALL" = false ]; then
            read -p "Reinstall ArgoCD? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                SKIP_INSTALL=true
            fi
        fi
    fi
fi

# =============================================================================
# INSTALL ARGOCD
# =============================================================================

if [ "$SKIP_INSTALL" = false ]; then
    echo ""
    echo -e "${YELLOW}[2/6] Installing ArgoCD...${NC}"
    
    # Create namespace
    if ! kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
        kubectl create namespace "$ARGOCD_NAMESPACE"
        echo -e "${GREEN}✓ Namespace created${NC}"
    else
        echo -e "${GREEN}✓ Namespace exists${NC}"
    fi
    
    # Install ArgoCD
    echo "   Installing ArgoCD manifests..."
    kubectl apply -n "$ARGOCD_NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    echo "   Waiting for ArgoCD to be ready (this may take 2-3 minutes)..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE" || true
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" || true
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n "$ARGOCD_NAMESPACE" || true
    
    # Verify installation
    READY_PODS=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --no-headers | grep -c "Running" || echo "0")
    if [ "$READY_PODS" -gt 0 ]; then
        echo -e "${GREEN}✓ ArgoCD installed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Some pods may still be starting. Check with: kubectl get pods -n $ARGOCD_NAMESPACE${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}[2/6] Skipping ArgoCD installation${NC}"
fi

# =============================================================================
# GET ADMIN PASSWORD
# =============================================================================

echo ""
echo -e "${YELLOW}[3/6] Getting ArgoCD admin password...${NC}"

# Wait for secret to be created
sleep 5
for i in {1..30}; do
    if kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        break
    fi
    echo "   Waiting for admin secret... ($i/30)"
    sleep 2
done

if kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" &>/dev/null; then
    ADMIN_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d)
    echo -e "${GREEN}✓ Admin password retrieved${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠️  SAVE THIS PASSWORD SECURELY!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Username: ${GREEN}admin${NC}"
    echo -e "Password: ${GREEN}$ADMIN_PASSWORD${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠️  Admin secret not found. You may need to wait longer.${NC}"
    echo "   Get it later with: kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
fi

# =============================================================================
# CONFIGURE GIT REPOSITORY
# =============================================================================

if [ "$SKIP_REPO_CONFIG" = false ]; then
    echo ""
    echo -e "${YELLOW}[4/6] Configuring Git repository...${NC}"
    
    if [ -z "$GIT_REPO_URL" ]; then
        echo -e "${YELLOW}⚠️  No Git repository URL provided${NC}"
        echo "   Skipping repository configuration"
        echo "   Configure manually later or run with --git-repo-url"
    else
        # Determine authentication method
        if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
            echo "   Configuring SSH authentication..."
            
            # Create SSH secret
            kubectl create secret generic git-repo-ssh \
                --from-file=sshPrivateKey="$SSH_KEY_PATH" \
                --from-file=type=git \
                --from-file=url="$GIT_REPO_URL" \
                -n "$ARGOCD_NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
            
            # Label secret for ArgoCD
            kubectl label secret git-repo-ssh argocd.argoproj.io/secret-type=repository -n "$ARGOCD_NAMESPACE" --overwrite
            
            echo -e "${GREEN}✓ SSH authentication configured${NC}"
            
        elif [ -n "$GIT_USERNAME" ] && [ -n "$GIT_TOKEN" ]; then
            echo "   Configuring HTTPS authentication..."
            
            # Create HTTPS secret
            kubectl create secret generic git-repo-credentials \
                --from-literal=type=git \
                --from-literal=url="$GIT_REPO_URL" \
                --from-literal=username="$GIT_USERNAME" \
                --from-literal=password="$GIT_TOKEN" \
                -n "$ARGOCD_NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
            
            # Configure ArgoCD to use the secret
            REPO_CONFIG="{\"$GIT_REPO_URL\":{\"type\":\"git\",\"url\":\"$GIT_REPO_URL\",\"password\":\"$GIT_TOKEN\",\"username\":\"$GIT_USERNAME\"}}"
            
            # Get existing repos config
            EXISTING_REPOS=$(kubectl get secret argocd-secret -n "$ARGOCD_NAMESPACE" -o jsonpath='{.data.repositories}' 2>/dev/null | base64 -d || echo "{}")
            
            # Merge with existing (simple merge, may need jq for complex cases)
            kubectl patch secret argocd-secret \
                -n "$ARGOCD_NAMESPACE" \
                --type='json' \
                -p="[{\"op\":\"add\",\"path\":\"/stringData/repositories\",\"value\":\"$REPO_CONFIG\"}]" 2>/dev/null || \
            kubectl patch secret argocd-secret \
                -n "$ARGOCD_NAMESPACE" \
                --type='json' \
                -p="[{\"op\":\"replace\",\"path\":\"/stringData/repositories\",\"value\":\"$REPO_CONFIG\"}]"
            
            echo -e "${GREEN}✓ HTTPS authentication configured${NC}"
        else
            echo -e "${YELLOW}⚠️  No authentication method provided${NC}"
            echo "   Provide either:"
            echo "     --ssh-key <path> (for SSH)"
            echo "     --git-username and --git-token (for HTTPS)"
        fi
    fi
else
    echo ""
    echo -e "${YELLOW}[4/6] Skipping repository configuration${NC}"
fi

# =============================================================================
# UPDATE APPLICATION FILES
# =============================================================================

echo ""
echo -e "${YELLOW}[5/6] Updating application files...${NC}"

if [ -n "$GIT_REPO_URL" ]; then
    # Update repository URL in application files
    APP_FILES=(
        "helm/argocd/app-of-apps.yaml"
        "helm/argocd/applications/vendure-production.yaml"
        "helm/argocd/applications/vendure-test.yaml"
        "helm/argocd/applications/vendure-local.yaml"
        "helm/argocd/applications/monitoring-stack.yaml"
        "helm/argocd/applications/karpenter.yaml"
    )
    
    UPDATED=0
    for FILE in "${APP_FILES[@]}"; do
        if [ -f "$FILE" ]; then
            # Check if file contains placeholder
            if grep -q "your-org/vendure-k8s.git" "$FILE" 2>/dev/null; then
                sed -i.bak "s|https://github.com/your-org/vendure-k8s.git|$GIT_REPO_URL|g" "$FILE"
                rm -f "${FILE}.bak"
                UPDATED=$((UPDATED + 1))
            fi
        fi
    done
    
    if [ "$UPDATED" -gt 0 ]; then
        echo -e "${GREEN}✓ Updated $UPDATED application file(s) with repository URL${NC}"
    else
        echo -e "${YELLOW}⚠️  No application files found or already updated${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  No repository URL provided, skipping file updates${NC}"
    echo "   Update manually: helm/argocd/app-of-apps.yaml and helm/argocd/applications/*.yaml"
fi

# =============================================================================
# DEPLOY ROOT APPLICATION
# =============================================================================

echo ""
echo -e "${YELLOW}[6/6] Deploying root application...${NC}"

if [ -f "helm/argocd/app-of-apps.yaml" ]; then
    echo "   Applying app-of-apps..."
    kubectl apply -f helm/argocd/app-of-apps.yaml
    
    echo "   Waiting for applications to be created..."
    sleep 10
    
    # Check if applications were created
    APP_COUNT=$(kubectl get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$APP_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Root application deployed ($APP_COUNT application(s) found)${NC}"
        echo ""
        echo "   Applications:"
        kubectl get applications -n "$ARGOCD_NAMESPACE" --no-headers | awk '{print "     - " $1}'
    else
        echo -e "${YELLOW}⚠️  No applications found yet. They may be created shortly.${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  app-of-apps.yaml not found${NC}"
    echo "   Deploy manually: kubectl apply -f helm/argocd/app-of-apps.yaml"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ ARGOCD SETUP COMPLETE!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next Steps:"
echo ""
echo "1. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
echo "   Then open: https://localhost:8080"
echo ""
echo "2. Login:"
if [ -n "$ADMIN_PASSWORD" ]; then
    echo "   Username: admin"
    echo "   Password: $ADMIN_PASSWORD"
else
    echo "   Get password: kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
fi
echo ""
echo "3. Verify applications:"
echo "   kubectl get applications -n $ARGOCD_NAMESPACE"
echo ""
echo "4. Check sync status:"
echo "   kubectl get applications -n $ARGOCD_NAMESPACE -o wide"
echo ""
echo "5. Install ArgoCD CLI (optional):"
echo "   brew install argocd  # macOS"
echo "   # or download from: https://github.com/argoproj/argo-cd/releases"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

