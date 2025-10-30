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
# 🧭 Define directories
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARGOCD_DIR="$PROJECT_ROOT/argocd-apps"
ARGOCD_APP_FILE="$ARGOCD_DIR/dota2-dev.yaml"

# -----------------------------------------------------------------------------
# Step 0: Validate Prerequisites
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 0: Validating prerequisites...${NC}"

# Check if ArgoCD is installed
if ! kubectl get namespace argocd &>/dev/null; then
    echo -e "${RED}❌ ArgoCD namespace not found${NC}"
    echo "Please install ArgoCD first:"
    echo "  kubectl create namespace argocd"
    echo "  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    exit 1
fi

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

echo -e "${GREEN}✅ Prerequisites validated${NC}\n"

# -----------------------------------------------------------------------------
# Step 1: Configure ArgoCD Access (NodePort for Kind on Mac)
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1: Configuring ArgoCD access...${NC}"

# Get current service type
CURRENT_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}')
echo "Current service type: ${CURRENT_TYPE}"

# Patch service to NodePort if not already
if [ "$CURRENT_TYPE" != "NodePort" ]; then
    echo "Converting to NodePort for Kind compatibility..."
    
    kubectl patch svc argocd-server -n argocd -p '{
      "spec": {
        "type": "NodePort",
        "ports": [
          {
            "name": "http",
            "port": 80,
            "protocol": "TCP",
            "targetPort": 8080,
            "nodePort": 30080
          },
          {
            "name": "https",
            "port": 443,
            "protocol": "TCP",
            "targetPort": 8080,
            "nodePort": 30443
          }
        ]
      }
    }' > /dev/null 2>&1
    
    echo -e "${GREEN}✅ Service converted to NodePort${NC}"
else
    echo -e "${GREEN}✅ Service is already NodePort${NC}"
fi

# Get NodePorts
HTTP_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
HTTPS_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo "ArgoCD accessible at:"
echo "  - HTTP:  http://localhost:${HTTP_PORT}"
echo "  - HTTPS: https://localhost:${HTTPS_PORT}"
echo ""

# -----------------------------------------------------------------------------
# Step 2: Get Admin Credentials
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2: Retrieving admin credentials...${NC}"

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

if [ -z "$ADMIN_PASSWORD" ]; then
    echo -e "${RED}❌ Could not retrieve admin password${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Credentials retrieved${NC}\n"

# -----------------------------------------------------------------------------
# Step 3: Login to ArgoCD CLI
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3: Logging into ArgoCD CLI...${NC}"

# Try HTTPS/gRPC first (recommended)
if argocd login localhost:${HTTPS_PORT} --username admin --password "${ADMIN_PASSWORD}" --insecure > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Logged in via HTTPS (port ${HTTPS_PORT})${NC}\n"
elif argocd login localhost:${HTTP_PORT} --username admin --password "${ADMIN_PASSWORD}" --insecure --grpc-web > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Logged in via HTTP with gRPC-web (port ${HTTP_PORT})${NC}\n"
else
    echo -e "${RED}❌ Failed to login to ArgoCD${NC}"
    echo ""
    echo "Try manually:"
    echo "  argocd login localhost:${HTTPS_PORT} --username admin --password ${ADMIN_PASSWORD} --insecure"
    echo "  or"
    echo "  argocd login localhost:${HTTP_PORT} --username admin --password ${ADMIN_PASSWORD} --insecure --grpc-web"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 4: Apply ArgoCD Application Manifest
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 4: Applying ArgoCD Application manifest...${NC}"
kubectl apply -f "$ARGOCD_APP_FILE"
echo -e "${GREEN}✅ Application manifest applied${NC}\n"

# Wait for ArgoCD to process
sleep 3

# -----------------------------------------------------------------------------
# Step 5: Check Application Status
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 5: Checking application status...${NC}"
argocd app get dota2-dev
echo ""

# -----------------------------------------------------------------------------
# Step 6: Sync Application
# -----------------------------------------------------------------------------
SYNC_STATUS=$(argocd app get dota2-dev -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ "$SYNC_STATUS" != "Synced" ]; then
    echo -e "${YELLOW}⚠️  Application is not synced yet${NC}"
    echo -e "${BLUE}Step 6: Syncing application...${NC}\n"
    
    argocd app sync dota2-dev
    
    echo ""
    echo "Waiting for sync to complete..."
    argocd app wait dota2-dev --health --timeout 300
    
    echo ""
    echo -e "${GREEN}✅ Sync completed${NC}\n"
else
    echo -e "${GREEN}✅ Application is already synced${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 7: Verify Deployment
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 7: Verifying deployment...${NC}"
echo "=========================================="
echo ""

echo -e "${BLUE}ArgoCD Application Details:${NC}"
argocd app get dota2-dev

echo ""
echo -e "${BLUE}Kubernetes Resources in 'data' namespace:${NC}"
kubectl get all -n data

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo "=========================================="
echo ""

# -----------------------------------------------------------------------------
# Display Access Information
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${YELLOW}📋 Access Information${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}ArgoCD Web UI:${NC}"
echo "  http://localhost:${HTTP_PORT}"
echo "  https://localhost:${HTTPS_PORT} (accept self-signed cert)"
echo ""
echo -e "${BLUE}Credentials:${NC}"
echo "  Username: admin"
echo "  Password: ${ADMIN_PASSWORD}"
echo ""
echo -e "${BLUE}Application URL:${NC}"
echo "  http://localhost:${HTTP_PORT}/applications/dota2-dev"
echo ""

# -----------------------------------------------------------------------------
# Display Useful Commands
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${YELLOW}📝 Useful Commands${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}ArgoCD CLI:${NC}"
echo "  argocd app list                    # List all apps"
echo "  argocd app get dota2-dev           # Get app details"
echo "  argocd app sync dota2-dev          # Manually sync"
echo "  argocd app history dota2-dev       # View sync history"
echo "  argocd app logs dota2-dev          # View app logs"
echo "  argocd app delete dota2-dev        # Delete app"
echo ""
echo -e "${BLUE}Kubernetes:${NC}"
echo "  kubectl get all -n data            # Check deployed resources"
echo "  kubectl logs -n data <pod-name>    # View pod logs"
echo "  kubectl describe pod -n data <pod> # Debug pod issues"
echo ""

# -----------------------------------------------------------------------------
# Display Important Notes
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}ℹ️  Important Notes${NC}"
echo "=========================================="
echo ""
echo "1. 🔄 Auto-sync is enabled - changes to Git will auto-deploy!"
echo ""
echo "2. 📦 Make sure your code is pushed to GitHub:"
echo "   https://github.com/rinavillaruz/dota2-meta-lab"
echo ""
echo "3. 🌿 ArgoCD pulls from the 'main' branch"
echo ""
echo "4. 📁 Helm chart must be in the 'helm/' directory"
echo ""
echo "5. 🎯 App deployed to the 'data' namespace"
echo ""
echo "6. 🔧 NodePort configured for Kind on Mac"
echo "   (HTTP: ${HTTP_PORT}, HTTPS: ${HTTPS_PORT})"
echo ""

echo "=========================================="
echo -e "${GREEN}🎉 Happy Deploying!${NC}"
echo "=========================================="
echo ""