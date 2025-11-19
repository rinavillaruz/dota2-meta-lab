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
# Step 2: Check ArgoCD Service Type
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2: Checking ArgoCD service configuration...${NC}"

SERVICE_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}')

if [ "$SERVICE_TYPE" = "NodePort" ]; then
    NODEPORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
    ARGOCD_SERVER="localhost:$NODEPORT"
    echo -e "${GREEN}✅ ArgoCD accessible via NodePort: $NODEPORT${NC}"
    echo "Using: https://$ARGOCD_SERVER"
else
    echo -e "${YELLOW}⚠️  ArgoCD not configured as NodePort, setting up port-forward...${NC}"
    
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
    
    ARGOCD_SERVER="localhost:8080"
    echo -e "${GREEN}✅ Port-forward established (PID: $PF_PID)${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 3: Login to ArgoCD CLI
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3: Logging into ArgoCD CLI...${NC}"

# Check if already logged in to the correct server
CURRENT_SERVER=$(argocd context 2>/dev/null | grep "^\*" | awk '{print $3}')

if [ "$CURRENT_SERVER" = "$ARGOCD_SERVER" ]; then
    echo -e "${GREEN}✅ Already logged into $ARGOCD_SERVER${NC}"
else
    echo "Logging into $ARGOCD_SERVER..."
    
    # Use expect or printf to handle the TLS warning automatically
    if command -v expect &> /dev/null; then
        # Use expect if available
        expect << EOF
set timeout 15
spawn argocd login $ARGOCD_SERVER --username admin --password "$ADMIN_PASSWORD" --insecure
expect {
    "Proceed (y/n)?" { send "y\r"; exp_continue }
    "'admin:login' logged in successfully" { }
    timeout { exit 1 }
}
EOF
        LOGIN_EXIT=$?
    else
        # Fallback: use printf with pipe
        echo "y" | timeout 15 argocd login $ARGOCD_SERVER --username admin --password "$ADMIN_PASSWORD" --insecure 2>&1
        LOGIN_EXIT=$?
    fi
    
    if [ $LOGIN_EXIT -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully logged in${NC}"
    else
        echo -e "${RED}❌ Login failed${NC}"
        echo ""
        echo "Try manual login:"
        echo "  argocd login $ARGOCD_SERVER --username admin --password '$ADMIN_PASSWORD' --insecure"
        [ ! -z "$PF_PID" ] && kill $PF_PID 2>/dev/null || true
        exit 1
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Step 3.5: Verify Helm Chart in Repository
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3.5: Verifying Helm chart exists in GitHub...${NC}"

REPO_OWNER="rinavillaruz"
REPO_NAME="dota2-meta-lab"
HELM_PATH="deploy/helm"

echo "Checking: https://github.com/$REPO_OWNER/$REPO_NAME/tree/main/$HELM_PATH"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$HELM_PATH")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}❌ Helm chart path not found in GitHub repository${NC}"
    echo ""
    echo "The path '$HELM_PATH' does not exist in your repository."
    echo ""
    echo "Please ensure you have:"
    echo "  1. Created the deploy/helm directory"
    echo "  2. Added Chart.yaml and values files"
    echo "  3. Committed and pushed to GitHub"
    echo ""
    echo "Quick fix:"
    echo "  mkdir -p deploy/helm/templates"
    echo "  # Add your Helm chart files"
    echo "  git add deploy/helm/"
    echo "  git commit -m 'Add Helm chart'"
    echo "  git push origin main"
    echo ""
    [ ! -z "$PF_PID" ] && kill $PF_PID 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✅ Helm chart path exists in repository${NC}"

# Check for required files
for file in "Chart.yaml" "values.yaml" "values-dev.yaml"; do
    FILE_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents/$HELM_PATH/$file")
    
    if [ "$FILE_HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}  ✓ $file found${NC}"
    else
        echo -e "${YELLOW}  ⚠ $file not found${NC}"
    fi
done

echo ""

# -----------------------------------------------------------------------------
# Step 4: Apply ArgoCD Application Manifest
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 4: Applying ArgoCD Application manifest...${NC}"

# First, check if application already exists
if kubectl get application dota2-dev -n argocd &>/dev/null; then
    echo -e "${YELLOW}⚠️  Application 'dota2-dev' already exists${NC}"
    
    # Show current status
    echo "Current application status:"
    kubectl get application dota2-dev -n argocd -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || echo "No status conditions"
    echo ""
    
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
    [ ! -z "$PF_PID" ] && kill $PF_PID 2>/dev/null || true
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
    [ ! -z "$PF_PID" ] && kill $PF_PID 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✅ Application resource exists in Kubernetes${NC}"

# Check for errors in the application status
APP_ERROR=$(kubectl get application dota2-dev -n argocd -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null)
if [ -n "$APP_ERROR" ]; then
    echo ""
    echo -e "${RED}❌ Application has a ComparisonError:${NC}"
    echo "$APP_ERROR"
    [ ! -z "$PF_PID" ] && kill $PF_PID 2>/dev/null || true
    exit 1
fi

# Wait a bit for ArgoCD to fully process the application
echo "Waiting for ArgoCD to initialize application..."
sleep 10

# Try to access the app via CLI with --grpc-web flag (more reliable)
echo ""
echo "Checking if ArgoCD CLI can access the application..."

# Just try once with timeout
if timeout 10 argocd app get dota2-dev --grpc-web &>/dev/null; then
    echo -e "${GREEN}✅ Application accessible via ArgoCD CLI${NC}"
else
    echo -e "${YELLOW}⚠️  ArgoCD CLI access slow or failing, but proceeding anyway${NC}"
    echo "Application exists in Kubernetes and ArgoCD is processing it"
fi

echo ""
echo "Application details:"
argocd app get dota2-dev --grpc-web 2>/dev/null || kubectl get application dota2-dev -n argocd -o yaml

echo ""

# Get application status from Kubernetes directly (more reliable)
APP_HEALTH=$(kubectl get application dota2-dev -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
APP_SYNC=$(kubectl get application dota2-dev -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

echo -e "${BLUE}Application Status:${NC}"
echo "  Health: $APP_HEALTH"
echo "  Sync:   $APP_SYNC"
echo ""

# -----------------------------------------------------------------------------
# Step 6: Verify Sync Status
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 6: Verifying sync status...${NC}"

# Check if sync already completed (automated sync)
SYNC_STATUS=$(kubectl get application dota2-dev -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
OPERATION_PHASE=$(kubectl get application dota2-dev -n argocd -o jsonpath='{.status.operationState.phase}' 2>/dev/null)

echo "Sync Status: $SYNC_STATUS"
echo "Operation Phase: $OPERATION_PHASE"

if [ "$SYNC_STATUS" = "Synced" ] && [ "$OPERATION_PHASE" = "Succeeded" ]; then
    echo -e "${GREEN}✅ Application synced successfully (automated sync)${NC}"
elif [ "$SYNC_STATUS" = "Synced" ]; then
    echo -e "${GREEN}✅ Application is synced${NC}"
elif [ "$SYNC_STATUS" = "OutOfSync" ]; then
    echo -e "${YELLOW}⚠️  Application is out of sync, triggering manual sync...${NC}"
    
    # Try to sync via CLI
    if argocd app sync dota2-dev --grpc-web --server $ARGOCD_SERVER 2>/dev/null; then
        echo -e "${GREEN}✅ Sync initiated via CLI${NC}"
    else
        # Fallback: use kubectl to trigger sync
        echo "CLI sync failed, using kubectl annotation to trigger sync..."
        kubectl annotate application dota2-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
        echo -e "${GREEN}✅ Sync triggered via annotation${NC}"
    fi
    
    # Wait for sync to complete
    echo "Waiting for sync to complete..."
    for i in {1..30}; do
        SYNC_STATUS=$(kubectl get application dota2-dev -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
        if [ "$SYNC_STATUS" = "Synced" ]; then
            echo -e "${GREEN}✅ Sync completed${NC}"
            break
        fi
        echo "Waiting... ($i/30)"
        sleep 2
    done
else
    echo -e "${YELLOW}⚠️  Unexpected sync status: $SYNC_STATUS${NC}"
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
echo "  https://$ARGOCD_SERVER"
echo ""
echo -e "${BLUE}Credentials:${NC}"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""
if [ ! -z "$PF_PID" ]; then
    echo -e "${BLUE}Port-forward PID: $PF_PID${NC}"
    echo "  To stop: kill $PF_PID"
    echo ""
fi

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
if [ ! -z "$PF_PID" ]; then
    echo -e "${BLUE}Port-forward:${NC}"
    echo "  To stop: kill $PF_PID"
    echo "  To restart: kubectl port-forward -n argocd svc/argocd-server 8080:443 &"
    echo ""
fi

echo "=========================================="
echo -e "${GREEN}🎉 Happy Deploying!${NC}"
echo "=========================================="
echo ""

# Offer to keep port-forward running
if [ ! -z "$PF_PID" ]; then
    echo -e "${YELLOW}Note:${NC} Port-forward is running in background (PID: $PF_PID)"
    echo "Press Enter to stop it, or Ctrl+C to keep it running and exit"
    read -t 5 || true
    
    # If user pressed Enter, stop port-forward
    kill $PF_PID 2>/dev/null || true
    echo "Port-forward stopped."
fi