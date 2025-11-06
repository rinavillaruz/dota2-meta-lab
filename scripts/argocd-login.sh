#!/bin/bash

set -e

echo "🔐 ArgoCD Login Script"
echo "======================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

NAMESPACE="argocd"
PORT=8080

# -----------------------------------------------------------------------------
# Step 1: Verify ArgoCD is installed
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1: Checking ArgoCD installation...${NC}"

if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}❌ ArgoCD namespace not found${NC}"
    echo "Please install ArgoCD first: ./install-argocd.sh"
    exit 1
fi

echo -e "${GREEN}✅ ArgoCD namespace found${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 2: Wait for ArgoCD server to be ready
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2: Waiting for ArgoCD server to be ready...${NC}"

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    POD_STATUS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    
    if [ "$POD_STATUS" = "Running" ]; then
        # Check if container is actually ready
        READY=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        
        if [ "$READY" = "true" ]; then
            echo -e "${GREEN}✅ ArgoCD server is ready${NC}"
            break
        fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Waiting for ArgoCD server pod... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 2
    else
        echo -e "${RED}❌ ArgoCD server is not ready${NC}"
        echo ""
        echo "Debug information:"
        kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server
        echo ""
        kubectl describe pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server
        exit 1
    fi
done

echo ""

# -----------------------------------------------------------------------------
# Step 3: Get admin password
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3: Retrieving admin password...${NC}"

# Wait for initial admin secret to be created
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
# Step 4: Kill any existing port-forwards
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 4: Cleaning up existing port-forwards...${NC}"

# Kill any existing port-forward processes
pkill -f "port-forward.*argocd-server" 2>/dev/null || true
sleep 2

echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 5: Setup port-forward
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 5: Setting up port-forward...${NC}"

# Check if port is available
if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Port $PORT is in use${NC}"
    read -p "Try alternative port 8081? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        PORT=8081
    else
        echo -e "${RED}❌ Cannot proceed with port $PORT in use${NC}"
        echo "Free up the port or choose a different one"
        exit 1
    fi
fi

echo "Starting port-forward on localhost:$PORT..."

# Start port-forward in background with logging for debugging
kubectl port-forward -n $NAMESPACE svc/argocd-server $PORT:443 > /tmp/argocd-pf.log 2>&1 &
PF_PID=$!

# Give it a moment to start
sleep 2

# Check if the process is still running
if ! ps -p $PF_PID > /dev/null 2>&1; then
    echo -e "${RED}❌ Port-forward process died${NC}"
    echo "Check logs at: /tmp/argocd-pf.log"
    cat /tmp/argocd-pf.log
    exit 1
fi

# Wait for port-forward to be ready with retries
echo "Waiting for port-forward to establish..."
MAX_PF_RETRIES=15
PF_RETRY=0

while [ $PF_RETRY -lt $MAX_PF_RETRIES ]; do
    if curl -k -s --connect-timeout 1 https://localhost:$PORT > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Port-forward is responsive${NC}"
        break
    fi
    
    # Check if port-forward process is still alive
    if ! ps -p $PF_PID > /dev/null 2>&1; then
        echo -e "${RED}❌ Port-forward process died${NC}"
        echo "Check logs at: /tmp/argocd-pf.log"
        cat /tmp/argocd-pf.log
        exit 1
    fi
    
    PF_RETRY=$((PF_RETRY + 1))
    if [ $PF_RETRY -lt $MAX_PF_RETRIES ]; then
        echo "Waiting for connection... ($PF_RETRY/$MAX_PF_RETRIES)"
        sleep 2
    else
        echo -e "${RED}❌ Port-forward not responding${NC}"
        echo "Port-forward logs:"
        cat /tmp/argocd-pf.log
        kill $PF_PID 2>/dev/null || true
        exit 1
    fi
done

echo -e "${GREEN}✅ Port-forward established on localhost:$PORT${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 6: Login to ArgoCD
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 6: Logging in to ArgoCD...${NC}"

# Additional wait to ensure stability
sleep 3

# Login with retry logic
MAX_LOGIN_RETRIES=3
LOGIN_RETRY=0

while [ $LOGIN_RETRY -lt $MAX_LOGIN_RETRIES ]; do
    if argocd login localhost:$PORT --username admin --password "$ARGOCD_PASSWORD" --insecure; then
        echo -e "${GREEN}✅ Successfully logged in to ArgoCD${NC}"
        break
    else
        LOGIN_RETRY=$((LOGIN_RETRY + 1))
        if [ $LOGIN_RETRY -lt $MAX_LOGIN_RETRIES ]; then
            echo -e "${YELLOW}Login attempt failed, retrying... ($LOGIN_RETRY/$MAX_LOGIN_RETRIES)${NC}"
            sleep 3
        else
            echo -e "${RED}❌ Login failed after $MAX_LOGIN_RETRIES attempts${NC}"
            echo ""
            echo "Debug information:"
            echo "Port-forward process status:"
            ps -p $PF_PID || echo "Process not running"
            echo ""
            echo "Port-forward logs:"
            cat /tmp/argocd-pf.log
            echo ""
            echo "Testing connection:"
            curl -k -v https://localhost:$PORT 2>&1 | head -20
            kill $PF_PID 2>/dev/null || true
            exit 1
        fi
    fi
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${GREEN}✅ ArgoCD Login Complete!${NC}"
echo "=========================================="
echo ""
echo "📋 Connection Details:"
echo "  URL:      https://localhost:$PORT"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""
echo "🔧 Port-forward PID: $PF_PID"
echo ""
echo "=========================================="
echo -e "${YELLOW}Important Notes${NC}"
echo "=========================================="
echo ""
echo "1. Port-forward is running in background (PID: $PF_PID)"
echo ""
echo "2. To stop port-forward:"
echo "   kill $PF_PID"
echo "   or"
echo "   pkill -f 'port-forward.*argocd-server'"
echo ""
echo "3. Access ArgoCD UI:"
echo "   https://localhost:$PORT"
echo "   (Accept the self-signed certificate warning)"
echo ""
echo "4. The port-forward will stop when you close this terminal"
echo "   To keep it running, use screen or tmux"
echo ""
echo "5. Alternative: Use NodePort service"
echo "   kubectl patch svc argocd-server -n argocd -p '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"port\":443,\"nodePort\":30080}]}}'"
echo ""

# Save connection info to file
cat > /tmp/argocd-connection-info.txt << EOF
ArgoCD Connection Information
=============================
Generated: $(date)

URL:      https://localhost:$PORT
Username: admin
Password: $ARGOCD_PASSWORD

Port-forward PID: $PF_PID

To stop port-forward:
  kill $PF_PID

To restart port-forward:
  kubectl port-forward -n argocd svc/argocd-server $PORT:443
EOF

echo "Connection info saved to: /tmp/argocd-connection-info.txt"
echo ""

# Option to change service type to NodePort
echo "=========================================="
echo -e "${YELLOW}Optional: Switch to NodePort${NC}"
echo "=========================================="
echo ""
read -p "Convert ArgoCD service to NodePort for persistent access? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Converting to NodePort..."
    
    kubectl patch svc argocd-server -n $NAMESPACE -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"protocol":"TCP","targetPort":8080,"nodePort":30080},{"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30081}]}}'
    
    echo ""
    echo -e "${GREEN}✅ Service converted to NodePort${NC}"
    echo ""
    echo "You can now access ArgoCD at:"
    echo "  HTTPS: https://localhost:30080"
    echo "  HTTP:  http://localhost:30081"
    echo ""
    echo "The port-forward is no longer needed. Stopping it..."
    kill $PF_PID 2>/dev/null || true
    echo ""
    echo "Re-login with new endpoint:"
    argocd login localhost:30080 --username admin --password "$ARGOCD_PASSWORD" --insecure
fi

echo ""
echo -e "${GREEN}Setup complete! 🚀${NC}"