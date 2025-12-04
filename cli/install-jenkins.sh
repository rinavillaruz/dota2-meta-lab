#!/bin/bash

set -e

echo "🚀 Installing Jenkins in Kubernetes"
echo "===================================="
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
JENKINS_DIR="$PROJECT_ROOT/jenkins-k8s/base"

# Check if manifests directory exists
if [ ! -d "$JENKINS_DIR" ]; then
    echo -e "${RED}❌ Jenkins manifests not found at: $JENKINS_DIR${NC}"
    echo ""
    echo "Expected structure:"
    echo "  $PROJECT_ROOT/"
    echo "  └── jenkins-k8s/"
    echo "      └── base/"
    echo "          ├── 00-namespace.yaml"
    echo "          ├── 01-serviceaccount.yaml"
    echo "          ├── 02-clusterrole.yaml"
    echo "          ├── 03-clusterrolebinding.yaml"
    echo "          ├── 04-pvc.yaml"
    echo "          ├── 05-configmap.yaml"
    echo "          ├── 06-deployment.yaml"
    echo "          └── 07-service.yaml"
    echo ""
    echo "Please create the jenkins-k8s directory structure first."
    exit 1
fi

echo -e "${BLUE}Using manifests from: $JENKINS_DIR${NC}\n"

# -----------------------------------------------------------------------------
# Step 0: Load environment variables and create secrets
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 0: Load Configuration & Create Secrets${NC}"
echo "=========================================="
echo ""

# Load .env file if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "Loading environment variables from .env..."
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    echo -e "${GREEN}✅ Environment variables loaded${NC}"
else
    echo -e "${YELLOW}⚠️  .env file not found at $PROJECT_ROOT/.env${NC}"
    echo "Will use default credentials"
fi

# Create Jenkins namespace first
echo "Creating Jenkins namespace..."
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Namespace created/verified${NC}"

# Create Jenkins admin credentials secret from .env or use default
if [ -n "$JENKINS_ADMIN_PASSWORD" ]; then
    echo "Creating Jenkins admin credentials from .env..."
    kubectl create secret generic jenkins-admin-credentials \
        --from-literal=password="$JENKINS_ADMIN_PASSWORD" \
        -n jenkins \
        --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✅ Jenkins credentials created from .env${NC}"
    echo -e "${BLUE}Password set from JENKINS_ADMIN_PASSWORD${NC}"
else
    echo -e "${YELLOW}⚠️  JENKINS_ADMIN_PASSWORD not found in .env${NC}"
    echo "Using default password: changeme"
    kubectl create secret generic jenkins-admin-credentials \
        --from-literal=password="changeme" \
        -n jenkins \
        --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✅ Jenkins credentials created with default password${NC}"
fi

# Create GitHub credentials secret
if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_TOKEN" ]; then
    kubectl create secret generic github-credentials \
        --from-literal=username="$GITHUB_USERNAME" \
        --from-literal=token="$GITHUB_TOKEN" \
        -n jenkins \
        --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✅ GitHub credentials secret created${NC}"
else
    echo -e "${YELLOW}⚠️  GitHub credentials not found in .env${NC}"
fi

# Create Docker Hub credentials secret
if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
    kubectl create secret generic dockerhub-credentials \
        --from-literal=username="$DOCKERHUB_USERNAME" \
        --from-literal=token="$DOCKERHUB_TOKEN" \
        -n jenkins \
        --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✅ Docker Hub credentials secret created${NC}"
else
    echo -e "${YELLOW}⚠️  Docker Hub credentials not found in .env${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 1: Create ServiceAccount
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1: Creating ServiceAccount...${NC}"
kubectl apply -f "$JENKINS_DIR/01-serviceaccount.yaml"
echo -e "${GREEN}✅ ServiceAccount created${NC}\n"

# -----------------------------------------------------------------------------
# Step 2: Set up RBAC
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2: Setting up RBAC (ClusterRole & Binding)...${NC}"
kubectl apply -f "$JENKINS_DIR/02-clusterrole.yaml"
kubectl apply -f "$JENKINS_DIR/03-clusterrolebinding.yaml"
echo -e "${GREEN}✅ RBAC configured${NC}\n"

# -----------------------------------------------------------------------------
# Step 3: Create PersistentVolumeClaim
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3: Creating PersistentVolumeClaim...${NC}"
kubectl apply -f "$JENKINS_DIR/04-pvc.yaml"

# Wait for PVC to be bound
echo "Waiting for PVC to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/jenkins-pvc -n jenkins --timeout=60s || {
    echo -e "${YELLOW}⚠️  PVC not bound yet, continuing anyway...${NC}"
}
echo -e "${GREEN}✅ PVC created${NC}\n"

# -----------------------------------------------------------------------------
# Step 4: Create Jenkins Init Scripts ConfigMap
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 4: Creating Jenkins init scripts...${NC}"
if [ -f "$JENKINS_DIR/08-init-configmap.yaml" ]; then
    kubectl apply -f "$JENKINS_DIR/08-init-configmap.yaml"
    echo -e "${GREEN}✅ Init scripts ConfigMap created${NC}\n"
else
    echo -e "${YELLOW}⚠️  08-init-configmap.yaml not found, skipping${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 5: Create ConfigMap (JCasC & plugins.txt)
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 5: Creating Jenkins Configuration...${NC}"
kubectl apply -f "$JENKINS_DIR/05-configmap.yaml"
echo -e "${GREEN}✅ ConfigMap created${NC}\n"

# -----------------------------------------------------------------------------
# Step 6: Deploy Jenkins
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 6: Deploying Jenkins...${NC}"
kubectl apply -f "$JENKINS_DIR/06-deployment.yaml"
echo -e "${GREEN}✅ Deployment created${NC}\n"

# -----------------------------------------------------------------------------
# Step 7: Create Service
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 7: Creating Jenkins Service...${NC}"
kubectl apply -f "$JENKINS_DIR/07-service.yaml"
echo -e "${GREEN}✅ Service created${NC}\n"

# -----------------------------------------------------------------------------
# Step 8: Wait for Jenkins to be ready
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 8: Waiting for Jenkins pod to be ready...${NC}"
echo "This may take 2-3 minutes (downloading image and installing plugins)..."
echo ""

# Show init container logs while waiting
echo "Watching plugin installation..."
sleep 5

JENKINS_POD=""
for i in {1..30}; do
    JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$JENKINS_POD" ]; then
        break
    fi
    echo "Waiting for pod to be created... ($i/30)"
    sleep 2
done

if [ -n "$JENKINS_POD" ]; then
    echo "Pod found: $JENKINS_POD"
    echo "Checking init container status..."
    
    # Check if init container is running
    INIT_STATUS=$(kubectl get pod -n jenkins $JENKINS_POD -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null || echo "")
    
    if echo "$INIT_STATUS" | grep -q "running"; then
        echo "Init container is installing plugins..."
        echo "You can watch logs with: kubectl logs -n jenkins $JENKINS_POD -c install-plugins -f"
    fi
fi

kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=300s || {
    echo -e "${RED}❌ Jenkins pod did not become ready in time${NC}"
    echo ""
    echo "Check pod status:"
    echo "  kubectl get pods -n jenkins"
    echo ""
    echo "Check init container logs:"
    echo "  kubectl logs -n jenkins $JENKINS_POD -c install-plugins"
    echo ""
    echo "Check main container logs:"
    echo "  kubectl logs -n jenkins $JENKINS_POD -c jenkins"
    echo ""
    echo "Check events:"
    echo "  kubectl get events -n jenkins --sort-by='.lastTimestamp'"
    exit 1
}

echo -e "${GREEN}✅ Jenkins is ready!${NC}\n"

# -----------------------------------------------------------------------------
# Step 9: Get Jenkins info and verify plugins
# -----------------------------------------------------------------------------
JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')

echo -e "${BLUE}Step 9: Retrieving Jenkins information...${NC}"
echo "Jenkins Pod: $JENKINS_POD"
echo ""

# Check plugin installation
echo "Verifying plugin installation..."
PLUGIN_COUNT=$(kubectl exec -n jenkins $JENKINS_POD -- find /var/jenkins_home/plugins -name "*.jpi" -o -name "*.hpi" 2>/dev/null | wc -l || echo "0")

if [ "$PLUGIN_COUNT" -gt 20 ]; then
    echo -e "${GREEN}✅ $PLUGIN_COUNT plugins installed successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Only $PLUGIN_COUNT plugins found${NC}"
    echo "Check init container logs for errors:"
    echo "  kubectl logs -n jenkins $JENKINS_POD -c install-plugins"
fi

echo ""

# -----------------------------------------------------------------------------
# Display access information
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${GREEN}✅ Jenkins Installation Complete!${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}Access Information:${NC}"
echo "  URL: http://localhost:30808"
echo "  Username: admin"

if [ -n "$JENKINS_ADMIN_PASSWORD" ]; then
    echo "  Password: [From .env JENKINS_ADMIN_PASSWORD]"
else
    echo "  Password: changeme"
fi

echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Change the admin password after first login!${NC}"
echo ""
echo "=========================================="
echo -e "${BLUE}Resources Created:${NC}"
echo "=========================================="
echo ""

# Show all resources
kubectl get all,pvc,configmap,secret -n jenkins

echo ""
echo "=========================================="
echo -e "${YELLOW}📝 Next Steps${NC}"
echo "=========================================="
echo ""
echo "1. Open Jenkins UI:"
echo "   http://localhost:30808"
echo ""
echo "2. Login with credentials shown above"
echo ""
echo "3. Verify plugins are installed:"
echo "   Manage Jenkins → Plugins → Installed plugins"
echo ""
echo "4. Configure credentials (if not using JCasC):"
echo "   Manage Jenkins → Credentials → System → Global credentials"
echo "   Add:"
echo "   - GitHub Personal Access Token (ID: github-credentials)"
echo "   - Docker Hub credentials (ID: docker-hub-credentials)"
echo ""
echo "5. Create your first pipeline:"
echo "   New Item → Pipeline → OK"
echo "   - Pipeline definition: Pipeline script from SCM"
echo "   - SCM: Git"
echo "   - Repository URL: https://github.com/rinavillaruz/dota2-meta-lab.git"
echo "   - Script Path: ci/Jenkinsfile"
echo ""
echo "=========================================="
echo -e "${BLUE}ℹ️  Useful Commands${NC}"
echo "=========================================="
echo ""
echo "View Jenkins logs:"
echo "  kubectl logs -n jenkins $JENKINS_POD -c jenkins -f"
echo ""
echo "View plugin installation logs:"
echo "  kubectl logs -n jenkins $JENKINS_POD -c install-plugins"
echo ""
echo "Check installed plugins:"
echo "  kubectl exec -n jenkins $JENKINS_POD -- ls /var/jenkins_home/plugins/*.jpi"
echo ""
echo "Restart Jenkins:"
echo "  kubectl rollout restart deployment/jenkins -n jenkins"
echo ""
echo "Check Jenkins status:"
echo "  kubectl get pods -n jenkins"
echo "  kubectl get svc -n jenkins"
echo ""
echo "Access Jenkins pod:"
echo "  kubectl exec -it -n jenkins $JENKINS_POD -- /bin/bash"
echo ""
echo "Uninstall Jenkins:"
echo "  kubectl delete namespace jenkins"
echo ""
echo "=========================================="
echo -e "${GREEN}🎉 Happy CI/CD-ing!${NC}"
echo "=========================================="
echo ""