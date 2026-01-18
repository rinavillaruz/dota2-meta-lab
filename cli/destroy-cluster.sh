#!/bin/bash

set -e

echo "🧹 Cleaning up Dota2 Meta Lab deployment..."

# -----------------------------------------------------------------------------
# Configuration - Load from .env file
# -----------------------------------------------------------------------------

# Determine directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env file - check in order: custom location, project root, home directory
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
elif [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
elif [ -f "$HOME/.env" ]; then
    source "$HOME/.env"
fi

# Configuration (with defaults)
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
CLUSTER_NAME="${CLUSTER_NAME:-dota2-dev}"

# Debug mode
if [ "${DEBUG:-false}" = "true" ]; then
    echo "🐛 Debug - Configuration:"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  ARGOCD_NAMESPACE: $ARGOCD_NAMESPACE"
    echo "  JENKINS_NAMESPACE: $JENKINS_NAMESPACE"
    echo "  CLUSTER_NAME: $CLUSTER_NAME"
    echo ""
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Determine environment (default to all)
ENVIRONMENT=${1:-all}

echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}\n"

# -----------------------------------------------------------------------------
# Step 1: Remove ArgoCD Applications
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔍 Step 1: Checking for ArgoCD applications...${NC}"
if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
    echo -e "${YELLOW}⚠️  ArgoCD is installed. Checking for managed applications...${NC}"
    
    # Delete ArgoCD applications
    if kubectl get crd applications.argoproj.io &>/dev/null 2>&1; then
        APP_COUNT=$(kubectl get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l)
        if [ "$APP_COUNT" -gt 0 ]; then
            echo "Found $APP_COUNT ArgoCD application(s). Removing..."
            kubectl delete applications --all -n "$ARGOCD_NAMESPACE" --timeout=60s 2>/dev/null || true
            echo -e "${GREEN}✅ ArgoCD applications removed${NC}"
        else
            echo -e "${GREEN}✅ No ArgoCD applications to remove${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  ArgoCD CRD not found, skipping application cleanup${NC}"
    fi
    echo ""
else
    echo -e "${YELLOW}⚠️  ArgoCD not installed${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 2: Uninstall Helm releases
# -----------------------------------------------------------------------------
if [ "$ENVIRONMENT" = "all" ]; then
    echo -e "${BLUE}📦 Step 2: Uninstalling all Helm releases...${NC}"
    
    # Uninstall all dota2-meta-lab releases
    RELEASES=$(helm list -A 2>/dev/null | grep dota2-meta-lab | awk '{print $1":"$2}' || true)
    
    if [ -z "$RELEASES" ]; then
        echo -e "${YELLOW}⚠️  No Helm releases found${NC}\n"
    else
        for release in $RELEASES; do
            name=$(echo $release | cut -d: -f1)
            namespace=$(echo $release | cut -d: -f2)
            echo "Uninstalling $name from namespace $namespace..."
            helm uninstall "$name" -n "$namespace" --timeout 60s
        done
        echo -e "${GREEN}✅ Helm releases removed${NC}\n"
    fi
else
    echo -e "${BLUE}📦 Step 2: Uninstalling Helm release for environment: ${ENVIRONMENT}${NC}"
    if helm list -n data 2>/dev/null | grep -q "dota2-meta-lab-${ENVIRONMENT}"; then
        helm uninstall dota2-meta-lab-${ENVIRONMENT} -n data --timeout 60s
        echo -e "${GREEN}✅ Helm release removed${NC}\n"
    else
        echo -e "${YELLOW}⚠️  Helm release not found${NC}\n"
    fi
fi

# -----------------------------------------------------------------------------
# Step 3: Delete application namespaces
# -----------------------------------------------------------------------------
echo -e "${BLUE}🗑️  Step 3: Deleting application namespaces...${NC}"

NAMESPACES_TO_DELETE=("data" "ml-pipeline")
DELETED_NAMESPACES=()

for ns in "${NAMESPACES_TO_DELETE[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo "Deleting namespace: $ns..."
        kubectl delete namespace "$ns" --timeout=60s &
        DELETED_NAMESPACES+=("$ns")
    fi
done

# Wait for all namespace deletions to complete
if [ ${#DELETED_NAMESPACES[@]} -gt 0 ]; then
    wait
    echo -e "${GREEN}✅ Application namespaces deleted: ${DELETED_NAMESPACES[*]}${NC}\n"
else
    echo -e "${YELLOW}⚠️  No application namespaces to delete${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 4: Remove Jenkins (Optional)
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔧 Step 4: Jenkins cleanup...${NC}"
if kubectl get namespace "$JENKINS_NAMESPACE" &>/dev/null; then
    echo "Jenkins is installed"
    read -p "Remove Jenkins? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "Removing Jenkins..."
        kubectl delete namespace "$JENKINS_NAMESPACE" --timeout=120s
        echo -e "${GREEN}✅ Jenkins removed${NC}\n"
    else
        echo -e "${YELLOW}ℹ️  Keeping Jenkins${NC}\n"
    fi
else
    echo -e "${GREEN}✅ Jenkins not installed${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 5: Remove ArgoCD (Optional)
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔧 Step 5: ArgoCD cleanup...${NC}"
if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
    echo "ArgoCD is installed"
    read -p "Remove ArgoCD? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "Removing ArgoCD..."
        
        # Step 1: Delete all ArgoCD applications (prevents finalizer issues)
        echo "Deleting ArgoCD applications..."
        if kubectl get crd applications.argoproj.io &>/dev/null; then
            for app in $(kubectl get applications -n "$ARGOCD_NAMESPACE" -o name 2>/dev/null); do
                echo "  Removing finalizers from $app..."
                kubectl patch $app -n "$ARGOCD_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
            done
            kubectl delete applications --all -n "$ARGOCD_NAMESPACE" --timeout=10s 2>/dev/null || true
        fi
        
        # Step 2: Delete CRDs (so their finalizers don't block namespace deletion)
        echo "Deleting ArgoCD CRDs..."
        kubectl delete crd applications.argoproj.io --timeout=10s 2>/dev/null || true
        kubectl delete crd applicationsets.argoproj.io --timeout=10s 2>/dev/null || true
        kubectl delete crd appprojects.argoproj.io --timeout=10s 2>/dev/null || true
        
        # Step 3: Force delete all resources in namespace
        echo "Force deleting all resources in $ARGOCD_NAMESPACE namespace..."
        kubectl delete all --all -n "$ARGOCD_NAMESPACE" --force --grace-period=0 --timeout=10s 2>/dev/null || true
        
        # Step 4: Remove namespace finalizers (this is the key!)
        echo "Removing namespace finalizers..."
        kubectl patch namespace "$ARGOCD_NAMESPACE" -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || {
            # Fallback: try with metadata finalizers
            kubectl patch namespace "$ARGOCD_NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        }
        
        # Step 5: Delete the namespace (should be instant now)
        echo "Deleting namespace..."
        kubectl delete namespace "$ARGOCD_NAMESPACE" --timeout=5s 2>/dev/null || true
        
        # Step 6: Verify deletion
        sleep 2
        if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
            echo -e "${YELLOW}⚠️  Namespace still exists, trying API finalization...${NC}"
            
            # Last resort: Direct API call to remove finalizers
            if command -v jq &>/dev/null; then
                kubectl get namespace "$ARGOCD_NAMESPACE" -o json 2>/dev/null | \
                  jq '.spec.finalizers = []' | \
                  kubectl replace --raw /api/v1/namespaces/"$ARGOCD_NAMESPACE"/finalize -f - 2>/dev/null || true
            else
                echo -e "${RED}❌ jq not installed, cannot force finalization${NC}"
                echo "Install with: brew install jq"
                echo "Then run: kubectl get namespace $ARGOCD_NAMESPACE -o json | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/$ARGOCD_NAMESPACE/finalize -f -"
            fi
            
            sleep 2
        fi
        
        # Final check
        if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
            echo -e "${RED}❌ ArgoCD namespace still exists (stuck in Terminating)${NC}"
            echo ""
            echo "Manual cleanup required:"
            echo "  1. Install jq: brew install jq"
            echo "  2. Run: kubectl get namespace $ARGOCD_NAMESPACE -o json | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/$ARGOCD_NAMESPACE/finalize -f -"
            echo "  3. Or edit manually: kubectl edit namespace $ARGOCD_NAMESPACE (remove finalizers section)"
        else
            echo -e "${GREEN}✅ ArgoCD removed${NC}"
        fi
        echo ""
    else
        echo -e "${YELLOW}ℹ️  Keeping ArgoCD${NC}\n"
    fi
else
    echo -e "${GREEN}✅ ArgoCD not installed${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 6: Clean up metrics server (optional)
# -----------------------------------------------------------------------------
echo -e "${BLUE}📊 Step 6: Checking for metrics server...${NC}"
METRICS_REMOVED=false

if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    read -p "Remove metrics server? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing metrics server..."
        kubectl delete deployment metrics-server -n kube-system --timeout=60s 2>/dev/null || true
        kubectl delete service metrics-server -n kube-system --timeout=60s 2>/dev/null || true
        kubectl delete apiservice v1beta1.metrics.k8s.io --timeout=60s 2>/dev/null || true
        METRICS_REMOVED=true
        echo -e "${GREEN}✅ Metrics server removed${NC}\n"
    else
        echo -e "${YELLOW}ℹ️  Keeping metrics server${NC}\n"
    fi
else
    echo -e "${GREEN}✅ Metrics server not installed${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 7: Summary
# -----------------------------------------------------------------------------
echo -e "${GREEN}✅ Cleanup complete!${NC}\n"
echo "=========================================="
echo "📝 What was removed:"
echo "=========================================="
echo "  ✅ ArgoCD applications"
echo "  ✅ Helm releases (dota2-meta-lab-*)"
if [ ${#DELETED_NAMESPACES[@]} -gt 0 ]; then
    echo "  ✅ Namespaces: ${DELETED_NAMESPACES[*]}"
fi
if [ "$METRICS_REMOVED" = true ]; then
    echo "  ✅ Metrics server"
fi
echo ""

# Check what's still installed
PRESERVED=()
kubectl get namespace "$JENKINS_NAMESPACE" &>/dev/null && PRESERVED+=("Jenkins")
kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null && PRESERVED+=("ArgoCD")

if [ ${#PRESERVED[@]} -gt 0 ]; then
    echo "=========================================="
    echo "📝 What was PRESERVED:"
    echo "=========================================="
    for item in "${PRESERVED[@]}"; do
        echo "  ✅ $item"
    done
    echo "  ⚠️  Kind cluster '$CLUSTER_NAME'"
    echo "  ⚠️  Data directories: $PROJECT_ROOT/data/, $PROJECT_ROOT/models/"
    echo ""
fi

# -----------------------------------------------------------------------------
# Step 8: Delete Kind cluster (optional)
# -----------------------------------------------------------------------------
echo "=========================================="
echo "🔥 Delete Kind Cluster?"
echo "=========================================="
read -p "Do you want to delete the Kind cluster '$CLUSTER_NAME'? (y/N): " -n 1 -r
echo

DELETE_DATA=false

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        echo "Deleting Kind cluster '$CLUSTER_NAME'..."
        kind delete cluster --name "$CLUSTER_NAME"
        echo -e "${GREEN}✅ Kind cluster deleted!${NC}\n"
        
        # -----------------------------------------------------------------------------
        # Step 9: Delete data directories (optional)
        # -----------------------------------------------------------------------------
        echo "=========================================="
        echo "🗑️  Delete Data Directories?"
        echo "=========================================="
        echo "This will permanently delete:"
        echo "  - $PROJECT_ROOT/data/ (MongoDB, Redis data)"
        echo "  - $PROJECT_ROOT/models/ (ML models)"
        echo "  - $PROJECT_ROOT/tmp/ (Temporary files)"
        echo ""
        read -p "Delete data directories? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Deleting data directories..."
            [ -d "$PROJECT_ROOT/data" ] && rm -rf "$PROJECT_ROOT/data" && echo "  ✅ Deleted data/"
            [ -d "$PROJECT_ROOT/models" ] && rm -rf "$PROJECT_ROOT/models" && echo "  ✅ Deleted models/"
            [ -d "$PROJECT_ROOT/tmp" ] && rm -rf "$PROJECT_ROOT/tmp" && echo "  ✅ Deleted tmp/"
            DELETE_DATA=true
            echo -e "${GREEN}✅ Data directories deleted!${NC}\n"
        else
            echo -e "${YELLOW}ℹ️  Keeping data directories${NC}\n"
        fi
    else
        echo -e "${YELLOW}⚠️  Kind cluster '$CLUSTER_NAME' not found${NC}\n"
    fi
else
    echo -e "${YELLOW}ℹ️  Keeping Kind cluster${NC}\n"
fi

# -----------------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------------
echo "=========================================="
echo "✅ Destroy Script Complete"
echo "=========================================="
echo ""

if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    echo "📋 Current state:"
    echo "  ✅ Kind cluster '$CLUSTER_NAME' is running"
    
    # Check what's still running
    kubectl get namespace "$JENKINS_NAMESPACE" &>/dev/null && echo "  ✅ Jenkins is still installed"
    kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null && echo "  ✅ ArgoCD is still installed"
    
    echo ""
    echo "To recreate the application:"
    echo "  cd cli"
    
    # Suggest appropriate command based on what's installed
    if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
        echo "  ./deploy-with-argocd.sh"
    else
        echo "  ./setup-complete-cicd.sh  # (to reinstall Jenkins + ArgoCD)"
        echo "  ./deploy-with-argocd.sh   # (then deploy your app)"
    fi
    echo "  or"
    echo "  ./deploy-with-helm.sh dev"
else
    echo "📋 Current state:"
    echo "  ❌ Kind cluster deleted"
    if [ "$DELETE_DATA" = true ]; then
        echo "  ❌ Data directories deleted"
    else
        echo "  ✅ Data directories preserved"
    fi
    echo ""
    echo "To recreate everything:"
    echo "  1. Deploy with helm:"
    echo "     ./cli/deploy-with-helm.sh"
    echo "  2. Create cluster and setup CI/CD:"
    echo "     ./cli/setup-complete-cicd.sh"
    echo "  3. Deploy your app:"
    echo "     ./cli/deploy-with-argocd.sh"
fi

echo ""