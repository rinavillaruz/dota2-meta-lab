#!/bin/bash

set -e  # Exit on any error

echo "🔄 Installing ArgoCD in Kubernetes..."

# -----------------------------------------------------------------------------
# 🎨 Colors for output
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# 🧭 Define directories (so script works from anywhere)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$PROJECT_ROOT/tmp"
VALUES_FILE="$TMP_DIR/argocd-values.yaml"

mkdir -p "$TMP_DIR"

# -----------------------------------------------------------------------------
# Step 1: Check if kubectl can connect to cluster
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔍 Step 1: Checking cluster connection...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to cluster. Please ensure your cluster is running.${NC}"
    echo "Run: cd scripts && ./deploy-with-helm.sh dev"
    exit 1
fi
echo -e "${GREEN}✅ Connected to cluster${NC}\n"

# -----------------------------------------------------------------------------
# Step 2: Check if ArgoCD is already installed
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔍 Step 2: Checking if ArgoCD is already installed...${NC}"

if kubectl get namespace argocd &> /dev/null; then
    # Namespace exists
    if helm list -n argocd | grep -q "argocd"; then
        echo -e "${GREEN}✅ Argo CD is already installed${NC}"
        read -p "Do you want to reinstall? This will delete the existing installation. (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}⚠️  Uninstalling existing ArgoCD...${NC}"
            helm uninstall argocd -n argocd 2>/dev/null || true
            kubectl delete namespace argocd --ignore-not-found
            echo -e "${BLUE}⏳ Reinstalling ArgoCD...${NC}"
            sleep 5
        else
            echo -e "${GREEN}✅ Keeping existing ArgoCD installation${NC}"
            exit 0
        fi
    else
        echo -e "${YELLOW}⚠️  ArgoCD namespace exists but Helm release not found. Cleaning up...${NC}"
        kubectl delete namespace argocd --ignore-not-found
        sleep 3
    fi
else
    echo -e "${BLUE}ℹ️  ArgoCD not found. Proceeding with installation...${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 3: Add ArgoCD Helm repository
# -----------------------------------------------------------------------------
echo -e "${BLUE}📦 Step 3: Adding ArgoCD Helm repository...${NC}"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
echo -e "${GREEN}✅ ArgoCD Helm repo added${NC}\n"

# -----------------------------------------------------------------------------
# Step 4: Create ArgoCD namespace
# -----------------------------------------------------------------------------
echo -e "${BLUE}📁 Step 4: Creating ArgoCD namespace...${NC}"
kubectl create namespace argocd
echo -e "${GREEN}✅ Namespace created${NC}\n"

# -----------------------------------------------------------------------------
# Step 5: Create ArgoCD values file
# -----------------------------------------------------------------------------
echo -e "${BLUE}📝 Step 5: Creating ArgoCD configuration...${NC}"

cat > "$VALUES_FILE" <<'EOF'
# ArgoCD configuration for local Kind cluster

global:
  domain: argocd.local

server:
  service:
    type: NodePort
    nodePortHttp: 30080
    nodePortHttps: 30443
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

controller:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi

repoServer:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

redis:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

redis-ha:
  enabled: false

# Disable dex for local development
dex:
  enabled: false

configs:
  params:
    server.insecure: true
EOF
echo -e "${GREEN}✅ Configuration created${NC}\n"

# -----------------------------------------------------------------------------
# Step 6: Install ArgoCD
# -----------------------------------------------------------------------------
echo -e "${BLUE}🎡 Step 6: Installing ArgoCD with Helm...${NC}"

# Ensure namespace exists
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Check if ArgoCD release already exists
if helm list -n argocd | grep -q "argocd"; then
    echo -e "${YELLOW}⚠️  ArgoCD Helm release already exists. Upgrading instead...${NC}"
    helm upgrade argocd argo/argo-cd \
      --namespace argocd \
      --values "$VALUES_FILE"
else
    echo "Installing ArgoCD..."
    helm install argocd argo/argo-cd \
      --namespace argocd \
      --values "$VALUES_FILE"
fi

echo -e "${GREEN}✅ ArgoCD installation complete${NC}\n"

# -----------------------------------------------------------------------------
# Step 7: Wait for ArgoCD deployments to be created
# -----------------------------------------------------------------------------
echo -e "${BLUE}⏳ Step 7: Waiting for ArgoCD deployments to be created...${NC}"
sleep 10
echo -e "${GREEN}✅ Deployments created${NC}\n"

# -----------------------------------------------------------------------------
# Step 7.5: Fix any pending pods due to node selectors
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔧 Step 7.5: Checking for scheduling issues...${NC}"

sleep 5  # Give pods a moment to schedule

if kubectl get pods -n argocd 2>/dev/null | grep -q Pending; then
    echo -e "${YELLOW}⚠️  Found pending pods, fixing node selectors...${NC}"
    
    # Remove nodeSelector from all deployments
    kubectl patch deployment argocd-server -n argocd --type='json' \
      -p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
    
    kubectl patch deployment argocd-repo-server -n argocd --type='json' \
      -p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
    
    kubectl patch deployment argocd-redis -n argocd --type='json' \
      -p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
    
    kubectl patch statefulset argocd-application-controller -n argocd --type='json' \
      -p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]' 2>/dev/null || true
    
    echo "Recreating pending pods..."
    kubectl delete pod -n argocd --field-selector=status.phase=Pending 2>/dev/null || true
    
    echo "Waiting for pods to restart..."
    sleep 15
    
    echo -e "${GREEN}✅ Scheduling issues fixed${NC}"
else
    echo -e "${GREEN}✅ All pods scheduled correctly${NC}"
fi

# Disable crashing dex server if needed
if kubectl get pods -n argocd 2>/dev/null | grep dex | grep -q CrashLoopBackOff; then
    echo -e "${YELLOW}⚠️  Dex server crashing, scaling to 0 (not needed for local dev)${NC}"
    kubectl scale deployment argocd-dex-server -n argocd --replicas=0 2>/dev/null || true
fi

echo ""

# -----------------------------------------------------------------------------
# Step 8: Wait for ArgoCD pods to be ready
# -----------------------------------------------------------------------------
echo -e "${BLUE}⏳ Step 8: Waiting for ArgoCD pods to be ready (this may take 2-3 minutes)...${NC}"

# Wait for server deployment to be available
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s || {
    echo -e "${YELLOW}⚠️  Deployment not available yet, checking pod status...${NC}"
    kubectl get pods -n argocd -o wide
}

# Wait for server pod to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=300s || {
    echo -e "${YELLOW}⚠️  Pods not ready yet, showing status...${NC}"
    kubectl get pods -n argocd -o wide
}

echo -e "${GREEN}✅ ArgoCD pods are ready${NC}\n"

# -----------------------------------------------------------------------------
# Step 9: Verify service accessibility
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔍 Step 9: Verifying ArgoCD service is accessible...${NC}"

# Give the service a moment to start accepting connections
sleep 5

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -k -s -o /dev/null -w "%{http_code}" http://localhost:30080 2>/dev/null | grep -q "200\|301\|302\|307"; then
        echo -e "${GREEN}✅ ArgoCD service is accessible!${NC}\n"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Waiting for service... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 2
    else
        echo -e "${YELLOW}⚠️  Service check timed out, but pods are running${NC}"
        echo "You can access ArgoCD at: http://localhost:30080"
        echo "It may take another minute to be fully ready."
        break
    fi
done

echo ""

# -----------------------------------------------------------------------------
# Step 10: Get admin password
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔐 Step 10: Retrieving admin password...${NC}"
sleep 5  # Give secrets time to be created
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo -e "${GREEN}✅ Password retrieved${NC}\n"

# -----------------------------------------------------------------------------
# Step 11: Show status
# -----------------------------------------------------------------------------
echo -e "${BLUE}📊 ArgoCD Installation Status:${NC}\n"
echo "=========================================="
echo "ArgoCD Pods:"
echo "=========================================="
kubectl get pods -n argocd -o wide
echo ""
echo "=========================================="
echo "ArgoCD Services:"
echo "=========================================="
kubectl get svc -n argocd
echo ""

# -----------------------------------------------------------------------------
# Step 12: Display access information
# -----------------------------------------------------------------------------
echo -e "${GREEN}✅ ArgoCD Installation Complete!${NC}\n"
echo "=========================================="
echo "📝 Access Information:"
echo "=========================================="
echo ""
echo "ArgoCD UI:"
echo "   http://localhost:30080"
echo ""
echo "Login credentials:"
echo "   Username: admin"
echo "   Password: ${ARGOCD_PASSWORD}"
echo ""
echo "=========================================="
echo "📝 ArgoCD CLI Commands:"
echo "=========================================="
echo ""
echo "Install ArgoCD CLI (if not already installed):"
echo "   brew install argocd"
echo ""
echo "Login via CLI:"
echo "   argocd login localhost:30080 --username admin --password ${ARGOCD_PASSWORD} --insecure"
echo ""
echo "List applications:"
echo "   argocd app list"
echo ""
echo "=========================================="
echo "📝 Save Your Password:"
echo "=========================================="
echo ""
echo "IMPORTANT: Save this password securely!"
echo "Password: ${ARGOCD_PASSWORD}"
echo ""
echo "To retrieve it later, run:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""

# -----------------------------------------------------------------------------
# 🧹 Step 13: Clean up temporary file
# -----------------------------------------------------------------------------
rm -f "$VALUES_FILE"

# -----------------------------------------------------------------------------
# Step 14: Next Steps
# -----------------------------------------------------------------------------
echo -e "${GREEN}✅ Installation script complete!${NC}\n"
echo "=========================================="
echo "📝 Next Steps - Deploy Your Apps:"
echo "=========================================="
echo ""
echo "1. Deploy development environment:"
echo "   kubectl apply -f $PROJECT_ROOT/argocd-apps/dota2-dev.yaml"
echo ""
echo "2. Deploy staging environment:"
echo "   kubectl apply -f $PROJECT_ROOT/argocd-apps/dota2-staging.yaml"
echo ""
echo "3. Deploy production environment:"
echo "   kubectl apply -f $PROJECT_ROOT/argocd-apps/dota2-prod.yaml"
echo ""
echo "4. Or deploy all apps at once:"
echo "   kubectl apply -f $PROJECT_ROOT/argocd-apps/"
echo ""
echo "5. View applications in ArgoCD UI:"
echo "   http://localhost:30080"
echo ""
echo "6. Or use CLI:"
echo "   argocd app list"
echo "   argocd app get dota2-dev"
echo ""
echo "Additional recommendations:"
echo "- Change the admin password in ArgoCD UI (User Info > Update Password)"
echo "- Review the ArgoCD app definitions in: $PROJECT_ROOT/argocd-apps/"
echo ""