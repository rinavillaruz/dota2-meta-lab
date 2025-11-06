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

if ! kubectl get namespace argocd &>/dev/null; then
    echo -e "${RED}❌ ArgoCD namespace not found${NC}"
    exit 1
fi

if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
    echo -e "${RED}❌ ArgoCD server is not running${NC}"
    exit 1
fi

echo -e "${GREEN}✅ ArgoCD is running${NC}"

if [ ! -f "$ARGOCD_APP_FILE" ]; then
    echo -e "${RED}❌ dota2-dev.yaml not found at: $ARGOCD_APP_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites validated${NC}\n"

# -----------------------------------------------------------------------------
# Step 0.5: Verify ArgoCD Application CRD
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 0.5: Verifying ArgoCD CRDs...${NC}"

if ! kubectl get crd applications.argoproj.io &>/dev/null; then
    echo -e "${RED}❌ ArgoCD Application CRD not found${NC}"
    echo "ArgoCD may not be properly installed"
    echo ""
    echo "Try reinstalling ArgoCD:"
    echo "  kubectl delete namespace argocd"
    echo "  ./scripts/install-argocd.sh"
    exit 1
fi

echo -e "${GREEN}✅ ArgoCD CRDs present${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Get Admin Credentials
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1: Retrieving admin credentials...${NC}"

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

if [ -z "$ADMIN_PASSWORD" ]; then
    echo -e "${RED}❌ Could not retrieve admin password${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Credentials retrieved${NC}"
echo "Username: admin"
echo "Password: $ADMIN_PASSWORD"
echo ""

# -----------------------------------------------------------------------------
# Step 2: Setup Port-Forward
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2: Setting up port-forward...${NC}"

# Kill any existing port-forwards
pkill -f "port-forward.*argocd-server" 2>/dev/null || true
sleep 2

# Start port-forward in background
echo "Starting port-forward on localhost:8080..."
kubectl port-forward -n argocd svc/argocd-server 8080:443 >/dev/null 2>&1 &
PF_PID=$!

# Wait for port-forward to establish
sleep 5

# Check if port-forward is working
if ! lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}❌ Port-forward failed to start${NC}"
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✅ Port-forward established (PID: $PF_PID)${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 3: Login to ArgoCD CLI
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3: Logging into ArgoCD CLI...${NC}"

# Use expect or printf to handle the TLS warning automatically
if command -v expect &> /dev/null; then
    # Use expect if available
    expect << EOF
set timeout 15
spawn argocd login localhost:8080 --username admin --password "$ADMIN_PASSWORD" --insecure
expect {
    "Proceed (y/n)?" { send "y\r"; exp_continue }
    "'admin:login' logged in successfully" { }
    timeout { exit 1 }
}
EOF
    LOGIN_EXIT=$?
else
    # Fallback: use printf with pipe
    echo "y" | timeout 15 argocd login localhost:8080 --username admin --password "$ADMIN_PASSWORD" --insecure 2>&1
    LOGIN_EXIT=$?
fi

if [ $LOGIN_EXIT -eq 0 ]; then
    echo -e "${GREEN}✅ Successfully logged in${NC}"
else
    echo -e "${RED}❌ Login failed${NC}"
    echo ""
    echo "Try manual login:"
    echo "  argocd login localhost:8080 --username admin --password '$ADMIN_PASSWORD' --insecure"
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

echo ""

# -----------------------------------------------------------------------------
# Step 4: Apply ArgoCD Application Manifest
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 4: Applying ArgoCD Application manifest...${NC}"

# First, check if application already exists
if kubectl get application dota2-dev -n argocd &>/dev/null; then
    echo -e "${YELLOW}⚠️  Application 'dota2-dev' already exists${NC}"
    read -p "Delete and recreate? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "Deleting existing application..."
        kubectl delete application dota2-dev -n argocd
        echo "Waiting for deletion..."
        sleep 5
    else
        echo "Using existing application"
    fi
fi

# Apply the manifest
if kubectl apply -f "$ARGOCD_APP_FILE"; then
    echo -e "${GREEN}✅ Application manifest applied${NC}"
else
    echo -e "${RED}❌ Failed to apply manifest${NC}"
    echo ""
    echo "Debug: Checking manifest syntax..."
    kubectl apply -f "$ARGOCD_APP_FILE" --dry-run=client -o yaml
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

echo ""
echo "Waiting for ArgoCD to process application..."
sleep 5

# -----------------------------------------------------------------------------
# Step 5: Check Application Status
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 5: Checking application status...${NC}"

# First check if the Application CRD resource exists in Kubernetes
echo "Checking if Application resource exists in Kubernetes..."
if ! kubectl get application dota2-dev -n argocd &>/dev/null; then
    echo -e "${RED}❌ Application resource not found in Kubernetes${NC}"
    echo ""
    echo "Debug information:"
    echo "Checking all applications in argocd namespace:"
    kubectl get applications -n argocd
    echo ""
    echo "Checking if Application CRD is installed:"
    kubectl get crd applications.argoproj.io
    echo ""
    echo "Checking ArgoCD controller logs:"
    kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✅ Application resource exists in Kubernetes${NC}"

# Now check if ArgoCD CLI can see it
echo "Checking if ArgoCD CLI can access the application..."
RETRIES=0
MAX_RETRIES=12

while [ $RETRIES -lt $MAX_RETRIES ]; do
    if argocd app get dota2-dev &>/dev/null; then
        echo -e "${GREEN}✅ Application accessible via ArgoCD CLI${NC}"
        break
    fi
    
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -lt $MAX_RETRIES ]; then
        echo "Waiting for ArgoCD to sync application... ($RETRIES/$MAX_RETRIES)"
        sleep 5
    else
        echo -e "${RED}❌ Application not accessible via CLI after waiting${NC}"
        echo ""
        echo "Debug information:"
        echo ""
        echo "Kubernetes Application status:"
        kubectl get application dota2-dev -n argocd -o yaml
        echo ""
        echo "ArgoCD application list:"
        argocd app list
        echo ""
        echo "ArgoCD server logs:"
        kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50
        kill $PF_PID 2>/dev/null || true
        exit 1
    fi
done

echo ""
echo "Application details:"
argocd app get dota2-dev
echo ""

# Check application health
APP_HEALTH=$(argocd app get dota2-dev -o json 2>/dev/null | grep -o '"health":{"status":"[^"]*"' | cut -d'"' -f6 || echo "Unknown")
APP_SYNC=$(argocd app get dota2-dev -o json 2>/dev/null | grep -o '"sync":{"status":"[^"]*"' | cut -d'"' -f6 || echo "Unknown")

echo -e "${BLUE}Application Status:${NC}"
echo "  Health: $APP_HEALTH"
echo "  Sync:   $APP_SYNC"
echo ""

if [ "$APP_SYNC" != "Synced" ] && [ "$APP_SYNC" != "OutOfSync" ]; then
    echo -e "${YELLOW}⚠️  Unexpected sync status: $APP_SYNC${NC}"
    echo "Application might have configuration errors"
    echo ""
fi

# -----------------------------------------------------------------------------
# Step 6: Sync Application
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 6: Syncing application...${NC}"

if argocd app sync dota2-dev --timeout 300; then
    echo ""
    echo -e "${GREEN}✅ Sync initiated${NC}"
    echo ""
    echo "Waiting for sync to complete..."
    argocd app wait dota2-dev --health --timeout 300 || echo -e "${YELLOW}⚠️  Still syncing...${NC}"
else
    echo -e "${RED}❌ Sync failed${NC}"
    argocd app get dota2-dev
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

echo ""

# -----------------------------------------------------------------------------
# Step 7: Verify Deployment
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 7: Verifying deployment...${NC}"
echo "=========================================="
echo ""

echo -e "${BLUE}ArgoCD Application Status:${NC}"
argocd app get dota2-dev --refresh

echo ""
echo -e "${BLUE}Kubernetes Resources in 'data' namespace:${NC}"
kubectl get all -n data 2>/dev/null || echo -e "${YELLOW}No resources in 'data' namespace yet${NC}"

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
echo "  https://localhost:8080 (via port-forward)"
echo "  Direct access: https://localhost:30443 (NodePort - may not work on Mac)"
echo ""
echo -e "${BLUE}Credentials:${NC}"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo -e "${BLUE}Port-forward PID: $PF_PID${NC}"
echo "  To stop: kill $PF_PID"
echo ""

# -----------------------------------------------------------------------------
# Display Useful Commands
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${YELLOW}📝 Useful Commands${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}ArgoCD CLI:${NC}"
echo "  argocd app list"
echo "  argocd app get dota2-dev"
echo "  argocd app sync dota2-dev"
echo "  argocd app logs dota2-dev"
echo ""
echo -e "${BLUE}Kubernetes:${NC}"
echo "  kubectl get all -n data"
echo "  kubectl logs -n data <pod-name>"
echo "  kubectl get events -n data"
echo ""
echo -e "${BLUE}Port-forward:${NC}"
echo "  To stop: kill $PF_PID"
echo "  To restart: kubectl port-forward -n argocd svc/argocd-server 8080:443 &"
echo ""

echo "=========================================="
echo -e "${GREEN}🎉 Happy Deploying!${NC}"
echo "=========================================="
echo ""

# Offer to keep port-forward running
echo -e "${YELLOW}Note:${NC} Port-forward is running in background (PID: $PF_PID)"
echo "Press Enter to stop it, or Ctrl+C to keep it running and exit"
read -t 5 || true

# If user pressed Enter, stop port-forward
kill $PF_PID 2>/dev/null || true
echo "Port-forward stopped."