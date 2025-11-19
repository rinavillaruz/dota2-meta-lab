#!/bin/bash

set -e

echo "🔐 ArgoCD Login Script (NodePort)"
echo "=================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

NAMESPACE="argocd"

# -----------------------------------------------------------------------------
# Step 1: Verify ArgoCD is installed
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1: Checking ArgoCD installation...${NC}"

if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}❌ ArgoCD namespace not found${NC}"
    echo "Please install ArgoCD first"
    exit 1
fi

echo -e "${GREEN}✅ ArgoCD namespace found${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 2: Wait for ArgoCD server to be ready
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2: Waiting for ArgoCD server to be ready...${NC}"

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server \
    -n $NAMESPACE \
    --timeout=300s

echo -e "${GREEN}✅ ArgoCD server is ready${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 3: Get admin password
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3: Retrieving admin password...${NC}"

# Wait for initial admin secret
RETRY_COUNT=0
while [ $RETRY_COUNT -lt 30 ]; do
    if kubectl get secret argocd-initial-admin-secret -n $NAMESPACE &>/dev/null; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt 30 ]; then
        echo "Waiting for admin secret... ($RETRY_COUNT/30)"
        sleep 2
    else
        echo -e "${RED}❌ Admin secret not found${NC}"
        exit 1
    fi
done

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n $NAMESPACE -o jsonpath="{.data.password}" | base64 -d)

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo -e "${RED}❌ Failed to retrieve password${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Password retrieved${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 4: Verify service is NodePort
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 4: Verifying ArgoCD service configuration...${NC}"

# Check current service type
CURRENT_TYPE=$(kubectl get svc argocd-server -n $NAMESPACE -o jsonpath='{.spec.type}')

if [ "$CURRENT_TYPE" = "NodePort" ]; then
    echo -e "${GREEN}✅ Service already configured as NodePort${NC}"
else
    echo -e "${YELLOW}⚠️  Service is $CURRENT_TYPE, but should be NodePort${NC}"
    echo "The install-argocd.sh script should have configured this."
    echo "Service will still be accessible via NodePort."
fi

echo ""

# -----------------------------------------------------------------------------
# Step 5: Wait for service to be accessible
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 5: Waiting for service to be accessible...${NC}"

# Give the service a moment to stabilize after pod is ready
sleep 5

MAX_RETRIES=30
RETRY_COUNT=0
SERVICE_URL="http://localhost:30080"

echo "Testing connection to: $SERVICE_URL"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Check HTTP endpoint (insecure mode)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$SERVICE_URL" 2>/dev/null || echo "000")
    
    if [[ "$HTTP_CODE" =~ ^(200|301|302|307|401)$ ]]; then
        echo -e "${GREEN}✅ Service is accessible (HTTP $HTTP_CODE)${NC}"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Waiting for service... ($RETRY_COUNT/$MAX_RETRIES) [HTTP $HTTP_CODE]"
        sleep 2
    else
        echo -e "${YELLOW}⚠️  Service check timed out, but may still be initializing${NC}"
        echo ""
        echo "Debug information:"
        kubectl get svc argocd-server -n $NAMESPACE
        echo ""
        kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server -o wide
        echo ""
        echo "Attempting login anyway..."
        break
    fi
done

echo ""

# -----------------------------------------------------------------------------
# Step 6: Login to ArgoCD
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 6: Logging in to ArgoCD...${NC}"

# Check if argocd CLI is installed
if ! command -v argocd &> /dev/null; then
    echo -e "${YELLOW}⚠️  ArgoCD CLI not found${NC}"
    echo ""
    echo "Install with: brew install argocd"
    echo ""
    echo "You can still access the UI at: http://localhost:30080"
    echo "Username: admin"
    echo "Password: $ARGOCD_PASSWORD"
    echo ""
    exit 0
fi

# Additional wait to ensure stability
sleep 3

# Login with retry logic (use HTTP port 30080 for insecure mode)
MAX_LOGIN_RETRIES=3
LOGIN_RETRY=0

while [ $LOGIN_RETRY -lt $MAX_LOGIN_RETRIES ]; do
    if argocd login localhost:30080 --username admin --password "$ARGOCD_PASSWORD" --insecure --plaintext; then
        echo -e "${GREEN}✅ Successfully logged in to ArgoCD${NC}"
        break
    else
        LOGIN_RETRY=$((LOGIN_RETRY + 1))
        if [ $LOGIN_RETRY -lt $MAX_LOGIN_RETRIES ]; then
            echo -e "${YELLOW}Login attempt failed, retrying... ($LOGIN_RETRY/$MAX_LOGIN_RETRIES)${NC}"
            sleep 5
        else
            echo -e "${YELLOW}⚠️  CLI login failed after $MAX_LOGIN_RETRIES attempts${NC}"
            echo ""
            echo "You can still access the UI manually:"
            echo "  URL:      http://localhost:30080"
            echo "  Username: admin"
            echo "  Password: $ARGOCD_PASSWORD"
            echo ""
            break
        fi
    fi
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo -e "${GREEN}✅ ArgoCD Access Information${NC}"
echo "=========================================="
echo ""
echo "📋 Connection Details:"
echo "  UI URL:    http://localhost:30080"
echo "  Username:  admin"
echo "  Password:  $ARGOCD_PASSWORD"
echo ""
echo "=========================================="
echo -e "${YELLOW}Important Notes${NC}"
echo "=========================================="
echo ""
echo "1. ArgoCD is accessible via NodePort (persistent)"
echo "   No port-forwarding needed!"
echo ""
echo "2. Open in browser:"
echo "   http://localhost:30080"
echo ""
echo "3. ArgoCD CLI commands:"
echo "   argocd app list"
echo "   argocd app get <app-name>"
echo "   argocd app sync <app-name>"
echo ""

# Save connection info
mkdir -p ../tmp
cat > ../tmp/argocd-connection-info.txt << EOF
ArgoCD Connection Information
=============================
Generated: $(date)

UI URL:    http://localhost:30080
Username:  admin
Password:  $ARGOCD_PASSWORD

Service Type: NodePort (persistent)

Quick Commands:
- List apps:  argocd app list
- Sync app:   argocd app sync <app-name>
- Get status: argocd app get <app-name>
EOF

echo "Connection info saved to: ../tmp/argocd-connection-info.txt"
echo ""
echo -e "${GREEN}Setup complete! 🚀${NC}"
echo ""
echo "Open ArgoCD UI: http://localhost:30080"