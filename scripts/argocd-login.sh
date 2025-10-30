#!/bin/bash

set -e

echo "🔐 ArgoCD CLI Login"
echo "==================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
ARGOCD_NAMESPACE="argocd"
ARGOCD_SERVER="localhost:30080"  # Adjust if using different NodePort
ARGOCD_USERNAME="admin"

# -----------------------------------------------------------------------------
# Check if ArgoCD is installed
# -----------------------------------------------------------------------------
echo -e "${BLUE}Checking ArgoCD installation...${NC}"

if ! kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
    echo -e "${RED}❌ ArgoCD namespace not found${NC}"
    echo "Please install ArgoCD first"
    exit 1
fi

echo -e "${GREEN}✅ ArgoCD is installed${NC}"
echo ""

# -----------------------------------------------------------------------------
# Get ArgoCD initial admin password
# -----------------------------------------------------------------------------
echo -e "${BLUE}Retrieving ArgoCD admin password...${NC}"

# Try to get the initial admin password from the secret
ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo -e "${YELLOW}⚠️  Initial admin secret not found${NC}"
    echo ""
    echo "This might mean:"
    echo "  1. You've already changed the password"
    echo "  2. The secret was deleted after first login"
    echo ""
    read -sp "Please enter ArgoCD admin password: " ARGOCD_PASSWORD
    echo ""
else
    echo -e "${GREEN}✅ Retrieved initial admin password${NC}"
    echo -e "${YELLOW}Password: ${ARGOCD_PASSWORD}${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Check if ArgoCD server is accessible
# -----------------------------------------------------------------------------
echo -e "${BLUE}Checking ArgoCD server accessibility...${NC}"

# Port forward in the background if not already accessible
if ! curl -k -s "https://${ARGOCD_SERVER}" &>/dev/null; then
    echo -e "${YELLOW}⚠️  ArgoCD not accessible on ${ARGOCD_SERVER}${NC}"
    echo "Starting port-forward..."
    
    # Kill any existing port-forwards
    pkill -f "port-forward.*argocd-server" || true
    
    # Start port-forward in background
    kubectl port-forward -n "$ARGOCD_NAMESPACE" svc/argocd-server 30080:443 &>/dev/null &
    PORT_FORWARD_PID=$!
    
    echo "Waiting for port-forward to establish..."
    sleep 5
    
    if curl -k -s "https://${ARGOCD_SERVER}" &>/dev/null; then
        echo -e "${GREEN}✅ Port-forward established (PID: ${PORT_FORWARD_PID})${NC}"
    else
        echo -e "${RED}❌ Failed to establish connection${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ ArgoCD server is accessible${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Login to ArgoCD
# -----------------------------------------------------------------------------
echo -e "${BLUE}Logging in to ArgoCD...${NC}"

if argocd login "$ARGOCD_SERVER" \
    --username "$ARGOCD_USERNAME" \
    --password "$ARGOCD_PASSWORD" \
    --insecure; then
    
    echo ""
    echo -e "${GREEN}✅ Successfully logged in to ArgoCD!${NC}"
    echo ""
    
    # Display current context
    echo -e "${BLUE}Current ArgoCD context:${NC}"
    argocd context
    
    echo ""
    echo -e "${GREEN}✅ Setup complete!${NC}"
    echo ""
    echo "You can now use ArgoCD CLI commands, such as:"
    echo "  argocd app list"
    echo "  argocd app get <app-name>"
    echo "  argocd app sync <app-name>"
    echo ""
    
else
    echo ""
    echo -e "${RED}❌ Login failed${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify ArgoCD is running:"
    echo "     kubectl get pods -n argocd"
    echo ""
    echo "  2. Get the admin password manually:"
    echo "     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""
    echo "  3. Access ArgoCD UI:"
    echo "     kubectl port-forward -n argocd svc/argocd-server 8080:443"
    echo "     Then visit: https://localhost:8080"
    echo ""
    exit 1
fi

# -----------------------------------------------------------------------------
# Optional: Change password reminder
# -----------------------------------------------------------------------------
echo -e "${YELLOW}⚠️  Security Reminder${NC}"
echo "The initial admin password is stored in a Kubernetes secret."
echo "For production use, you should:"
echo "  1. Change the admin password:"
echo "     argocd account update-password"
echo ""
echo "  2. Delete the initial secret:"
echo "     kubectl -n argocd delete secret argocd-initial-admin-secret"
echo ""
echo "  3. Consider setting up SSO/OIDC for authentication"
echo ""