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

# Global settings
global:
  domain: argocd.local

# Server settings
server:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Controller settings  
controller:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi

# Repo server settings
repoServer:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Redis settings
redis:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Disable HA for local development
redis-ha:
  enabled: false

# Use insecure mode for local development
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

# Wait for rollout
echo -e "${BLUE}⏳ Waiting for ArgoCD server to be ready...${NC}"
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s || {
    echo -e "${YELLOW}⚠️  ArgoCD server may still be initializing${NC}"
}

echo -e "${GREEN}✅ ArgoCD installation complete${NC}\n"

# -----------------------------------------------------------------------------
# Step 7: Wait for ArgoCD pods to be ready
# -----------------------------------------------------------------------------
echo -e "${BLUE}⏳ Step 7: Waiting for ArgoCD pods to be ready (this may take 2–3 minutes)...${NC}"
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=300s

echo -e "${GREEN}✅ ArgoCD pods are ready${NC}\n"

# -----------------------------------------------------------------------------
# Step 8: Get admin password
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔐 Step 8: Retrieving admin password...${NC}"
sleep 10  # Give secrets time to be created
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo -e "${GREEN}✅ Password retrieved${NC}\n"

# -----------------------------------------------------------------------------
# Step 9: Show status
# -----------------------------------------------------------------------------
echo -e "${BLUE}📊 ArgoCD Installation Status:${NC}\n"
echo "=========================================="
echo "ArgoCD Pods:"
echo "=========================================="
kubectl get pods -n argocd
echo ""
echo "=========================================="
echo "ArgoCD Services:"
echo "=========================================="
kubectl get svc -n argocd
echo ""

# -----------------------------------------------------------------------------
# Step 10: Display access information
# -----------------------------------------------------------------------------
echo -e "${GREEN}✅ ArgoCD Installation Complete!${NC}\n"
echo "=========================================="
echo "📝 Access Information:"
echo "=========================================="
echo ""
echo "1. Start port-forward (in a new terminal):"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo ""
echo "2. Open ArgoCD UI in your browser:"
echo "   http://localhost:8080"
echo ""
echo "3. Login credentials:"
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
echo "   argocd login localhost:8080 --username admin --password ${ARGOCD_PASSWORD} --insecure"
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
# 🧹 Step 11: Clean up temporary file
# -----------------------------------------------------------------------------
rm -f "$VALUES_FILE"

# -----------------------------------------------------------------------------
# Step 12: Next Steps
# -----------------------------------------------------------------------------
echo -e "${GREEN}✅ Installation script complete!${NC}\n"
echo "=========================================="
echo "📝 Next Steps - Deploy Your Apps:"
echo "=========================================="
echo ""
echo "1. Deploy development environment:"
echo "   kubectl apply -f $PROJECT_ROOT/argocd-apps/dota2-dev.yaml"
echo ""
echo "2. Deploy production environment:"
echo "   kubectl apply -f $PROJECT_ROOT/argocd-apps/dota2-prod.yaml"
echo ""
echo "3. Or deploy all apps at once:"
echo "   kubectl apply -f $PROJECT_ROOT/argocd-apps/"
echo ""
echo "4. View applications in ArgoCD UI:"
echo "   http://localhost:8080"
echo ""
echo "5. Or use CLI:"
echo "   argocd app list"
echo "   argocd app get dota2-dev"
echo ""
echo "Additional recommendations:"
echo "- Change the admin password in ArgoCD UI (User Info > Update Password)"
echo "- Review the ArgoCD app definitions in: $PROJECT_ROOT/argocd-apps/"
echo ""