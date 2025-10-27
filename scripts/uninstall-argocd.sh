#!/bin/bash

set -e  # Exit on any error

echo "🧹 Uninstalling ArgoCD from Kubernetes..."

# -----------------------------------------------------------------------------
# 🎨 Colors for output
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# 🧭 Define directories (same as install script)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$PROJECT_ROOT/tmp"
VALUES_FILE="$TMP_DIR/argocd-values.yaml"

# -----------------------------------------------------------------------------
# Step 1: Check if ArgoCD namespace exists
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔍 Step 1: Checking if ArgoCD is installed...${NC}"
if ! kubectl get namespace argocd &>/dev/null; then
    echo -e "${YELLOW}⚠️  ArgoCD namespace not found. Nothing to uninstall.${NC}"
    exit 0
fi

echo -e "${GREEN}✅ ArgoCD installation found.${NC}\n"

# -----------------------------------------------------------------------------
# Step 2: Check for existing ArgoCD applications
# -----------------------------------------------------------------------------
echo -e "${BLUE}📋 Step 2: Checking for managed applications...${NC}"
APPS_COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l | xargs)

if [ "$APPS_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found ${APPS_COUNT} application(s) managed by ArgoCD:${NC}"
    kubectl get applications -n argocd --no-headers 2>/dev/null | awk '{print "   - " $1}'
    echo ""
    echo -e "${YELLOW}Note: Deleting applications will NOT delete your actual workloads.${NC}"
    echo -e "${YELLOW}Your pods, services, etc. will continue running in their namespaces.${NC}\n"
    
    read -p "Do you want to delete ArgoCD applications? (recommended) (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "Deleting ArgoCD applications..."
        kubectl delete applications --all -n argocd --timeout=60s 2>/dev/null || true
        echo -e "${GREEN}✅ Applications deleted.${NC}\n"
    else
        echo -e "${YELLOW}⚠️  Skipping application deletion. They may become orphaned resources.${NC}\n"
    fi
else
    echo -e "${GREEN}✅ No applications found.${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 3: Confirm uninstall
# -----------------------------------------------------------------------------
echo -e "${RED}⚠️  WARNING: This will permanently delete ArgoCD and all its configuration.${NC}"
read -p "Are you sure you want to uninstall ArgoCD? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🚫 Uninstall cancelled.${NC}"
    exit 0
fi

# -----------------------------------------------------------------------------
# Step 4: Uninstall Helm release
# -----------------------------------------------------------------------------
echo -e "${BLUE}🧩 Step 4: Uninstalling Helm release 'argocd'...${NC}"
if helm status argocd -n argocd &>/dev/null; then
    helm uninstall argocd -n argocd
    echo -e "${GREEN}✅ Helm release removed.${NC}\n"
else
    echo -e "${YELLOW}⚠️  Helm release not found. Skipping.${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 5: Clean up Custom Resource Definitions (CRDs)
# -----------------------------------------------------------------------------
echo -e "${BLUE}🧹 Step 5: Cleaning up ArgoCD CRDs...${NC}"
echo "Removing ArgoCD Custom Resource Definitions..."

CRDS=$(kubectl get crd 2>/dev/null | grep argoproj.io | awk '{print $1}')
if [ -z "$CRDS" ]; then
    echo -e "${YELLOW}⚠️  No ArgoCD CRDs found.${NC}\n"
else
    echo "$CRDS" | xargs kubectl delete crd 2>/dev/null || true
    echo -e "${GREEN}✅ CRDs cleaned up.${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 6: Clean up cluster-wide resources
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔧 Step 6: Cleaning up cluster-wide resources...${NC}"

# Clean up ClusterRoles
echo "Checking for ArgoCD ClusterRoles..."
CLUSTER_ROLES=$(kubectl get clusterrole 2>/dev/null | grep argocd | awk '{print $1}')
if [ -n "$CLUSTER_ROLES" ]; then
    echo "$CLUSTER_ROLES" | xargs kubectl delete clusterrole 2>/dev/null || true
    echo -e "${GREEN}✅ ClusterRoles removed.${NC}"
else
    echo -e "${YELLOW}⚠️  No ArgoCD ClusterRoles found.${NC}"
fi

# Clean up ClusterRoleBindings
echo "Checking for ArgoCD ClusterRoleBindings..."
CLUSTER_ROLE_BINDINGS=$(kubectl get clusterrolebinding 2>/dev/null | grep argocd | awk '{print $1}')
if [ -n "$CLUSTER_ROLE_BINDINGS" ]; then
    echo "$CLUSTER_ROLE_BINDINGS" | xargs kubectl delete clusterrolebinding 2>/dev/null || true
    echo -e "${GREEN}✅ ClusterRoleBindings removed.${NC}\n"
else
    echo -e "${YELLOW}⚠️  No ArgoCD ClusterRoleBindings found.${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 7: Delete ArgoCD namespace
# -----------------------------------------------------------------------------
echo -e "${BLUE}🗑️  Step 7: Deleting ArgoCD namespace...${NC}"
echo "This may take 30-60 seconds..."

# Delete namespace with timeout
kubectl delete namespace argocd --timeout=120s 2>/dev/null || {
    echo -e "${YELLOW}⚠️  Namespace deletion taking longer than expected...${NC}"
    echo "Checking for stuck resources..."
    
    # Force remove finalizers (try both methods)
    if command -v jq &> /dev/null; then
        echo "Using jq to remove finalizers..."
        kubectl get namespace argocd -o json | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/argocd/finalize" -f - 2>/dev/null || true
    else
        echo "Using kubectl patch to remove finalizers..."
        kubectl patch namespace argocd -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    fi
    
    echo "Waiting for namespace deletion..."
    kubectl wait --for=delete namespace/argocd --timeout=60s || {
        echo -e "${RED}❌ Namespace deletion failed.${NC}"
        echo ""
        echo "Manual cleanup commands:"
        echo "  # Check stuck resources:"
        echo "  kubectl get all -n argocd"
        echo ""
        echo "  # Force remove finalizers:"
        echo "  kubectl patch namespace argocd -p '{\"spec\":{\"finalizers\":[]}}' --type=merge"
        echo ""
        echo "  # Delete namespace:"
        echo "  kubectl delete namespace argocd --grace-period=0 --force"
        exit 1
    }
}

echo -e "${GREEN}✅ Namespace deleted.${NC}\n"

# -----------------------------------------------------------------------------
# Step 8: Clean up temporary files
# -----------------------------------------------------------------------------
echo -e "${BLUE}🧽 Step 8: Cleaning up temporary files...${NC}"
if [[ -f "$VALUES_FILE" ]]; then
    rm -f "$VALUES_FILE"
    echo -e "${GREEN}✅ Removed temporary ArgoCD values file.${NC}"
else
    echo -e "${YELLOW}⚠️  No temporary file found. Skipping.${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# Step 9: Optional Helm repo cleanup
# -----------------------------------------------------------------------------
echo -e "${BLUE}🧹 Step 9: Optional Helm repo cleanup...${NC}"
read -p "Do you also want to remove the Argo Helm repo? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    helm repo remove argo 2>/dev/null || true
    echo -e "${GREEN}✅ Argo Helm repo removed.${NC}"
else
    echo -e "${YELLOW}ℹ️  Keeping Argo Helm repo for future use.${NC}"
fi

# -----------------------------------------------------------------------------
# Step 10: Verification
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}🔍 Step 10: Verifying uninstall...${NC}"

# Check namespace
if kubectl get namespace argocd &>/dev/null; then
    echo -e "${RED}❌ ArgoCD namespace still exists!${NC}"
    exit 1
else
    echo -e "${GREEN}✅ ArgoCD namespace successfully removed.${NC}"
fi

# Check Helm release
if helm status argocd -n argocd &>/dev/null; then
    echo -e "${RED}❌ Helm release still exists!${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Helm release successfully removed.${NC}"
fi

# Check CRDs
REMAINING_CRDS=$(kubectl get crd 2>/dev/null | grep argoproj.io | wc -l)
if [ "$REMAINING_CRDS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: ${REMAINING_CRDS} ArgoCD CRD(s) still present${NC}"
else
    echo -e "${GREEN}✅ All ArgoCD CRDs removed.${NC}"
fi

# Check cluster-wide resources
REMAINING_CLUSTER_RESOURCES=$(kubectl get clusterrole,clusterrolebinding 2>/dev/null | grep argocd | wc -l)
if [ "$REMAINING_CLUSTER_RESOURCES" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: ${REMAINING_CLUSTER_RESOURCES} cluster-wide resource(s) still present${NC}"
else
    echo -e "${GREEN}✅ All cluster-wide resources removed.${NC}"
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}✅ ArgoCD has been fully uninstalled from your cluster.${NC}"
echo ""
echo "=========================================="
echo "📝 What was removed:"
echo "=========================================="
echo "  ✅ ArgoCD server, controller, and repo server"
echo "  ✅ ArgoCD namespace and all resources"
echo "  ✅ Helm release 'argocd'"
echo "  ✅ ArgoCD Custom Resource Definitions (CRDs)"
echo "  ✅ ArgoCD ClusterRoles and ClusterRoleBindings"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  ✅ Argo Helm repository"
fi
echo ""
echo "=========================================="
echo "📝 What was NOT affected:"
echo "=========================================="
echo "  ✅ Your applications (still running in their namespaces)"
echo "  ✅ Your Git repository"
echo "  ✅ Your Kubernetes cluster"
echo ""
echo "=========================================="
echo "📝 To reinstall ArgoCD:"
echo "=========================================="
echo "  ./install-argocd.sh"
echo ""
echo "To restore application management:"
echo "  kubectl apply -f $PROJECT_ROOT/argocd-apps/"
echo ""