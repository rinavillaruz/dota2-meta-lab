#!/bin/bash

set -e

echo "🔧 ArgoCD Access Fix for Kind on Mac"
echo "====================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Problem: Kind on Mac has port-forward networking issues${NC}"
echo -e "${YELLOW}Solution: Use NodePort instead of port-forward${NC}"
echo ""

# Check if ArgoCD is installed
if ! kubectl get namespace argocd &>/dev/null; then
    echo -e "${RED}❌ ArgoCD namespace not found${NC}"
    exit 1
fi

# Get current service type
CURRENT_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}')
echo -e "${BLUE}Current ArgoCD service type: ${CURRENT_TYPE}${NC}"
echo ""

# Patch service to NodePort if not already
if [ "$CURRENT_TYPE" != "NodePort" ]; then
    echo -e "${BLUE}Converting ArgoCD service to NodePort...${NC}"
    
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
    }'
    
    echo -e "${GREEN}✅ Service converted to NodePort${NC}\n"
else
    echo -e "${GREEN}✅ Service is already NodePort${NC}\n"
fi

# Get NodePorts
echo -e "${BLUE}Getting NodePort assignments...${NC}"
HTTP_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
HTTPS_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo "HTTP Port:  $HTTP_PORT"
echo "HTTPS Port: $HTTPS_PORT"
echo ""

# Get admin password
echo -e "${BLUE}Getting admin password...${NC}"
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
echo "Password: $ADMIN_PASSWORD"
echo ""

# Display connection info
echo "=========================================="
echo -e "${GREEN}✅ ArgoCD is Now Accessible!${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}Web UI:${NC}"
echo "  http://localhost:$HTTP_PORT"
echo "  or"
echo "  https://localhost:$HTTPS_PORT (accept self-signed cert)"
echo ""
echo -e "${YELLOW}CLI Login (try both):${NC}"
echo ""
echo "Option 1 - HTTPS/gRPC port (recommended):"
echo "  argocd login localhost:$HTTPS_PORT --username admin --password $ADMIN_PASSWORD --insecure"
echo ""
echo "Option 2 - HTTP port with grpc-web:"
echo "  argocd login localhost:$HTTP_PORT --username admin --password $ADMIN_PASSWORD --insecure --grpc-web"
echo ""
echo -e "${YELLOW}Credentials:${NC}"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""

echo "=========================================="
echo -e "${BLUE}How NodePort Works${NC}"
echo "=========================================="
echo ""
echo "NodePort exposes services on each node's IP at a static port."
echo "With Kind, 'localhost' maps to the Kind container network."
echo "This bypasses the port-forward networking issues on Mac."
echo ""
echo "To revert back to ClusterIP (if needed later):"
echo "  kubectl patch svc argocd-server -n argocd -p '{\"spec\":{\"type\":\"ClusterIP\"}}'"
echo ""

# Test connection
echo "=========================================="
echo -e "${BLUE}Testing Connection...${NC}"
echo "=========================================="
echo ""

echo "Testing HTTP port..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:$HTTP_PORT | grep -q "200\|302\|301"; then
    echo -e "${GREEN}✅ HTTP port is accessible${NC}"
else
    echo -e "${YELLOW}⚠️  HTTP port test inconclusive (may still work in browser)${NC}"
fi

echo ""
echo "Testing HTTPS port..."
if curl -s -k -o /dev/null -w "%{http_code}" https://localhost:$HTTPS_PORT | grep -q "200\|302\|301"; then
    echo -e "${GREEN}✅ HTTPS port is accessible${NC}"
else
    echo -e "${YELLOW}⚠️  HTTPS port test inconclusive (may still work)${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Try logging in now:"
echo "  argocd login localhost:$HTTPS_PORT --username admin --password $ADMIN_PASSWORD --insecure"
echo ""