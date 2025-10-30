#!/bin/bash

set -e

echo "🧹 Cleaning up Dota2 Meta Lab deployment (preserving ArgoCD)..."

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Define directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Determine environment (default to all)
ENVIRONMENT=${1:-all}

echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}\n"

# -----------------------------------------------------------------------------
# Step 1: Remove ArgoCD Applications (but keep ArgoCD itself)
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔍 Step 1: Checking for ArgoCD applications...${NC}"
if kubectl get namespace argocd &>/dev/null; then
    echo -e "${YELLOW}⚠️  ArgoCD is installed. Removing managed applications...${NC}"
    
    # Delete ArgoCD applications only (not ArgoCD itself)
    if kubectl get crd applications.argoproj.io &>/dev/null 2>&1; then
        APP_COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
        if [ "$APP_COUNT" -gt 0 ]; then
            echo "Found $APP_COUNT ArgoCD application(s). Removing..."
            kubectl delete applications --all -n argocd --timeout=60s 2>/dev/null || true
            echo -e "${GREEN}✅ ArgoCD applications removed${NC}"
        else
            echo -e "${GREEN}✅ No ArgoCD applications to remove${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  ArgoCD CRD not found, skipping application cleanup${NC}"
    fi
    
    echo -e "${GREEN}✅ ArgoCD preserved${NC}\n"
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

NAMESPACES_TO_DELETE=("data" "ml-pipeline" "jenkins")
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
# Step 4: Clean up metrics server (optional)
# -----------------------------------------------------------------------------
echo -e "${BLUE}📊 Step 4: Checking for metrics server...${NC}"
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
# Step 5: Summary
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
echo "=========================================="
echo "📝 What was PRESERVED:"
echo "=========================================="
echo "  ✅ ArgoCD (namespace and installation)"
echo "  ⚠️  Kind cluster 'ml-cluster'"
echo "  ⚠️  Data directories: $PROJECT_ROOT/data/, $PROJECT_ROOT/models/"
echo ""

# -----------------------------------------------------------------------------
# Step 6: Delete Kind cluster (optional)
# -----------------------------------------------------------------------------
echo "=========================================="
echo "🔥 Delete Kind Cluster?"
echo "=========================================="
read -p "Do you want to delete the Kind cluster 'ml-cluster'? (y/N): " -n 1 -r
echo

DELETE_DATA=false

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if kind get clusters 2>/dev/null | grep -q "ml-cluster"; then
        echo "Deleting Kind cluster 'ml-cluster'..."
        kind delete cluster --name ml-cluster
        echo -e "${GREEN}✅ Kind cluster deleted!${NC}\n"
        
        # -----------------------------------------------------------------------------
        # Step 7: Delete data directories (optional)
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
        echo -e "${YELLOW}⚠️  Kind cluster 'ml-cluster' not found${NC}\n"
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

if kind get clusters 2>/dev/null | grep -q "ml-cluster"; then
    echo "📋 Current state:"
    echo "  ✅ Kind cluster 'ml-cluster' is running"
    echo "  ✅ ArgoCD is still installed and ready to use"
    echo ""
    echo "To recreate the application:"
    echo "  cd scripts"
    echo "  ./deploy-dota2-argocd.sh"
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
    echo "  1. Recreate Kind cluster:"
    echo "     ./deploy-with-helm dev"
    echo "  2. Deploy argo:"
    echo "     ./deploy-with-argocd.sh"
fi

echo ""