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
# Step 1: Create Namespace
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1: Creating Jenkins namespace...${NC}"
kubectl apply -f "$JENKINS_DIR/00-namespace.yaml"
echo -e "${GREEN}✅ Namespace created${NC}\n"

# -----------------------------------------------------------------------------
# Step 2: Create ServiceAccount
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2: Creating ServiceAccount...${NC}"
kubectl apply -f "$JENKINS_DIR/01-serviceaccount.yaml"
echo -e "${GREEN}✅ ServiceAccount created${NC}\n"

# -----------------------------------------------------------------------------
# Step 3: Set up RBAC
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3: Setting up RBAC (ClusterRole & Binding)...${NC}"
kubectl apply -f "$JENKINS_DIR/02-clusterrole.yaml"
kubectl apply -f "$JENKINS_DIR/03-clusterrolebinding.yaml"
echo -e "${GREEN}✅ RBAC configured${NC}\n"

# -----------------------------------------------------------------------------
# Step 4: Create PersistentVolumeClaim
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 4: Creating PersistentVolumeClaim...${NC}"
kubectl apply -f "$JENKINS_DIR/04-pvc.yaml"

# Wait for PVC to be bound
echo "Waiting for PVC to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/jenkins-pvc -n jenkins --timeout=60s || {
    echo -e "${YELLOW}⚠️  PVC not bound yet, continuing anyway...${NC}"
}
echo -e "${GREEN}✅ PVC created${NC}\n"

# -----------------------------------------------------------------------------
# Step 5: Create ConfigMap (JCasC)
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
echo "This may take 2-3 minutes (downloading image and starting up)..."
echo ""

kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=300s || {
    echo -e "${RED}❌ Jenkins pod did not become ready in time${NC}"
    echo ""
    echo "Check pod status:"
    echo "  kubectl get pods -n jenkins"
    echo ""
    echo "Check pod logs:"
    echo "  kubectl logs -n jenkins -l app=jenkins"
    echo ""
    echo "Check events:"
    echo "  kubectl get events -n jenkins --sort-by='.lastTimestamp'"
    exit 1
}

echo -e "${GREEN}✅ Jenkins is ready!${NC}\n"

# -----------------------------------------------------------------------------
# Step 9: Get Jenkins info
# -----------------------------------------------------------------------------
JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')

echo -e "${BLUE}Step 9: Retrieving Jenkins information...${NC}"
echo "Jenkins Pod: $JENKINS_POD"
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
echo "  Password: admin"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Change the admin password after first login!${NC}"
echo ""
echo "=========================================="
echo -e "${BLUE}Resources Created:${NC}"
echo "=========================================="
echo ""

# Show all resources
kubectl get all,pvc,configmap -n jenkins

echo ""
echo "=========================================="
echo -e "${YELLOW}📝 Next Steps${NC}"
echo "=========================================="
echo ""
echo "1. Open Jenkins UI:"
echo "   http://localhost:30808"
echo ""
echo "2. Login with admin/admin"
echo ""
echo "3. Change admin password:"
echo "   Click 'admin' → Configure → Password"
echo ""
echo "4. Configure credentials:"
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
echo "  kubectl logs -n jenkins $JENKINS_POD -f"
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