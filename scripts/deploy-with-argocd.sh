#!/bin/bash

set -e

echo "🚀 Deploying Dota2 Meta Lab via ArgoCD"
echo "======================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# 🧭 Define directories (so script works from anywhere)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARGOCD_DIR="$PROJECT_ROOT/argocd-apps"
ARGOCD_APP_FILE="$ARGOCD_DIR/dota2-dev.yaml"

# Check if argocd-apps directory exists
if [ ! -d "$ARGOCD_DIR" ]; then
    echo -e "${RED}❌ argocd-apps directory not found at: $ARGOCD_DIR${NC}"
    echo "Expected project structure:"
    echo "  $PROJECT_ROOT/"
    echo "  └── argocd-apps/"
    echo "      └── dota2-dev.yaml"
    exit 1
fi

# Check if dota2-dev.yaml exists
if [ ! -f "$ARGOCD_APP_FILE" ]; then
    echo -e "${RED}❌ dota2-dev.yaml not found at: $ARGOCD_APP_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}Step 1: Applying ArgoCD Application manifest...${NC}"
kubectl apply -f "$ARGOCD_APP_FILE"

echo -e "${GREEN}✅ Application manifest applied${NC}\n"

# Wait a moment for ArgoCD to process
sleep 3

echo -e "${BLUE}Step 2: Checking application status...${NC}"
argocd app list

echo ""
echo -e "${BLUE}Step 3: Getting detailed application info...${NC}"
argocd app get dota2-dev

echo ""
echo "=========================================="
echo -e "${YELLOW}📝 Next Steps${NC}"
echo "=========================================="
echo ""

# Check if app is synced
SYNC_STATUS=$(argocd app get dota2-dev -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ "$SYNC_STATUS" != "Synced" ]; then
    echo -e "${YELLOW}⚠️  Application is not synced yet${NC}"
    echo ""
    echo "Sync the application:"
    echo "  argocd app sync dota2-dev"
    echo ""
    echo "Or enable auto-sync (if not already):"
    echo "  The manifest already has automated sync enabled"
    echo "  ArgoCD will sync automatically in a moment"
    echo ""
    echo "Watch sync progress:"
    echo "  argocd app sync dota2-dev --watch"
else
    echo -e "${GREEN}✅ Application is synced!${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Useful Commands${NC}"
echo "=========================================="
echo ""
echo "View in Web UI:"
echo "  http://localhost:30080/applications/dota2-dev"
echo ""
echo "CLI Commands:"
echo "  argocd app list                    # List all apps"
echo "  argocd app get dota2-dev           # Get app details"
echo "  argocd app sync dota2-dev          # Manually sync"
echo "  argocd app history dota2-dev       # View sync history"
echo "  argocd app logs dota2-dev          # View app logs"
echo "  argocd app delete dota2-dev        # Delete app"
echo ""
echo "Check deployed resources:"
echo "  kubectl get all -n data"
echo ""
echo "=========================================="
echo -e "${BLUE}Step 4: Syncing application...${NC}"
echo "=========================================="
echo ""
echo "Starting sync..."
echo ""

# Trigger sync
argocd app sync dota2-dev

echo ""
echo "Waiting for sync to complete..."
argocd app wait dota2-dev --health --timeout 300

echo ""
echo -e "${GREEN}✅ Sync completed${NC}\n"

echo "=========================================="
echo -e "${BLUE}Step 5: Verifying deployment...${NC}"
echo "=========================================="
echo ""

echo -e "${BLUE}ArgoCD Application Details:${NC}"
argocd app get dota2-dev

echo ""
echo -e "${BLUE}Kubernetes Resources in 'data' namespace:${NC}"
kubectl get all -n data

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Deployment Verification Complete${NC}"
echo "=========================================="
echo ""

echo "=========================================="
echo -e "${BLUE}ℹ️  Important Notes${NC}"
echo "=========================================="
echo ""
echo "1. Make sure your code is pushed to GitHub:"
echo "   https://github.com/rinavillaruz/dota2-meta-lab"
echo ""
echo "2. ArgoCD will pull from the 'main' branch"
echo ""
echo "3. Your Helm chart must be in the 'helm/' directory"
echo ""
echo "4. The app will be deployed to the 'data' namespace"
echo ""
echo "5. Auto-sync is enabled - changes to Git will auto-deploy!"
echo ""