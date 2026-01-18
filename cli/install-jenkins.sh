#!/bin/bash

set -e

echo "🚀 Installing Jenkins in Kubernetes"
echo "===================================="
echo ""

# -----------------------------------------------------------------------------
# Configuration - Load from .env file
# -----------------------------------------------------------------------------

# Determine directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env file - check in order: custom location, project root, home directory
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
elif [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
elif [ -f "$HOME/.env" ]; then
    source "$HOME/.env"
fi

# Jenkins Configuration (with defaults)
JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-changeme}"

# GitHub Configuration
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Docker Hub Configuration
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"
DOCKERHUB_EMAIL="${DOCKERHUB_EMAIL:-admin@example.com}"

# Debug mode
if [ "${DEBUG:-false}" = "true" ]; then
    echo "🐛 Debug - Configuration:"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  JENKINS_NAMESPACE: $JENKINS_NAMESPACE"
    echo "  DOCKERHUB_USERNAME: $DOCKERHUB_USERNAME"
    echo "  GITHUB_USERNAME: $GITHUB_USERNAME"
    echo ""
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# 🧭 Define directories
# -----------------------------------------------------------------------------
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
    echo "          ├── 07-rbac.yaml"
    echo "          └── 08-service.yaml"
    echo ""
    echo "Please create the jenkins-k8s directory structure first."
    exit 1
fi

echo -e "${BLUE}Using manifests from: $JENKINS_DIR${NC}\n"

# -----------------------------------------------------------------------------
# Step -1: Build Jenkins Docker Image with Docker CLI (AUTOMATED!)
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step -1: Preparing Jenkins with Docker CLI${NC}"
echo "=========================================="
echo ""

# Check if image exists on Docker Hub (not just locally)
if ! docker pull rinavillaruz/jenkins-docker:latest > /dev/null 2>&1; then
    echo "Image not found on Docker Hub. Building..."
    docker rmi rinavillaruz/jenkins-docker:latest 2>/dev/null || true
    
    # Create Dockerfile if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/jenkins-k8s/docker/Dockerfile" ]; then
        echo "Creating Dockerfile..."
        mkdir -p "$PROJECT_ROOT/jenkins-k8s/docker"
        cat > "$PROJECT_ROOT/jenkins-k8s/docker/Dockerfile" <<'EOF'
FROM jenkins/jenkins:lts-jdk21

USER root

# Install Docker CLI (latest version), kubectl, Helm, Buildx, and jq
RUN apt-get update && \
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        jq && \
    # =================================================================
    # Docker Installation
    # =================================================================
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    # Install Docker CLI and Buildx
    apt-get update && \
    apt-get install -y \
        docker-ce-cli \
        docker-buildx-plugin && \
    # =================================================================
    # kubectl Installation
    # =================================================================
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl && \
    # =================================================================
    # Helm Installation
    # =================================================================
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
    # =================================================================
    # User Setup
    # =================================================================
    # Add jenkins to docker group
    groupadd -f docker && \
    usermod -aG docker jenkins && \
    # =================================================================
    # Cleanup
    # =================================================================
    rm -rf /var/lib/apt/lists/*

# Verify all installations
RUN echo "========================================" && \
    echo "✅ Installed versions:" && \
    docker --version && \
    kubectl version --client && \
    helm version && \
    jq --version && \
    echo "========================================"

USER jenkins
EOF
        echo -e "${GREEN}✅ Dockerfile created${NC}"
    fi
    
    echo ""
    echo "🐳 Building Jenkins image with Docker, kubectl, and Helm..."
    cd "$PROJECT_ROOT/jenkins-k8s/docker"
    docker build -t rinavillaruz/jenkins-docker:latest . || {
        echo -e "${RED}❌ Docker build failed${NC}"
        exit 1
    }
    echo -e "${GREEN}✅ Jenkins image built successfully${NC}"
    
    echo ""
    # Automated Docker login
    if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
        echo "🔑 Logging into Docker Hub..."
        echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || {
            echo -e "${RED}❌ Docker login failed${NC}"
            exit 1
        }
        echo -e "${GREEN}✅ Logged into Docker Hub${NC}"
    else
        echo -e "${YELLOW}⚠️  Docker Hub credentials not found in .env${NC}"
        read -p "Login manually now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            docker login || exit 1
        else
            echo -e "${YELLOW}⚠️  Image not pushed to Docker Hub${NC}"
            echo "You can push later with: docker push rinavillaruz/jenkins-docker:latest"
            cd "$PROJECT_ROOT"
        fi
    fi
    
    # Push if logged in
    if docker info 2>&1 | grep -q "Username:"; then
        echo ""
        echo "📤 Pushing image to Docker Hub..."
        docker push rinavillaruz/jenkins-docker:latest || {
            echo -e "${RED}❌ Push failed${NC}"
        }
        echo -e "${GREEN}✅ Image pushed to Docker Hub${NC}"
    fi
    
    echo -e "${GREEN}✅ Image ready${NC}"
    cd "$PROJECT_ROOT"
    echo ""
else
    echo -e "${GREEN}✅ Jenkins Docker image already exists on Docker Hub${NC}"
    echo "To rebuild: docker rmi rinavillaruz/jenkins-docker:latest"
    echo ""
fi

echo ""

# -----------------------------------------------------------------------------
# Step 0: Create secrets
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 0: Load Configuration & Create Secrets${NC}"
echo "=========================================="
echo ""

# Create Jenkins namespace first
echo "Creating Jenkins namespace..."
kubectl create namespace "$JENKINS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Namespace created/verified${NC}"

# Create Jenkins admin credentials secret from .env or use default
echo "Creating Jenkins admin credentials..."
kubectl create secret generic jenkins-admin-credentials \
    --from-literal=password="$JENKINS_ADMIN_PASSWORD" \
    -n "$JENKINS_NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Jenkins credentials created${NC}"

# Create GitHub credentials secret
if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_TOKEN" ]; then
    kubectl create secret generic github-credentials \
        --from-literal=username="$GITHUB_USERNAME" \
        --from-literal=token="$GITHUB_TOKEN" \
        -n "$JENKINS_NAMESPACE" \
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
        -n "$JENKINS_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✅ Docker Hub credentials secret created${NC}"
else
    echo -e "${YELLOW}⚠️  Docker Hub credentials not found in .env${NC}"
fi

# Create ImagePullSecret for private Docker Hub repository
if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
    echo "Creating ImagePullSecret for private Docker Hub repository..."
    kubectl create secret docker-registry dockerhub-pull-secret \
        --docker-server=https://index.docker.io/v1/ \
        --docker-username="$DOCKERHUB_USERNAME" \
        --docker-password="$DOCKERHUB_TOKEN" \
        --docker-email="$DOCKERHUB_EMAIL" \
        -n "$JENKINS_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✅ ImagePullSecret created for private repository${NC}"
else
    echo -e "${YELLOW}⚠️  Cannot create ImagePullSecret - Docker Hub credentials missing${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 1: Create ServiceAccount
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1: Creating ServiceAccount...${NC}"
kubectl apply -f "$JENKINS_DIR/01-serviceaccount.yaml"
echo -e "${GREEN}✅ ServiceAccount created${NC}\n"

# -----------------------------------------------------------------------------
# Step 2: Set up RBAC (Jenkins namespace access)
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
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/jenkins-pvc -n "$JENKINS_NAMESPACE" --timeout=60s || {
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
# Step 7: Set up Jenkins RBAC for Deployments
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 7: Setting up Jenkins deployment permissions...${NC}"
if [ -f "$JENKINS_DIR/07-rbac.yaml" ]; then
    kubectl apply -f "$JENKINS_DIR/07-rbac.yaml"
    echo -e "${GREEN}✅ Deployment RBAC configured${NC}"
    echo -e "${GREEN}   Jenkins can now deploy to Kubernetes!${NC}\n"
else
    echo -e "${YELLOW}⚠️  07-rbac.yaml not found${NC}"
    echo -e "${YELLOW}⚠️  Jenkins may not have permissions to deploy applications${NC}"
    echo -e "${YELLOW}   Create 07-rbac.yaml to grant deployment permissions${NC}\n"
fi

# -----------------------------------------------------------------------------
# Step 8: Create Service
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 8: Creating Jenkins Service...${NC}"
if [ -f "$JENKINS_DIR/08-service.yaml" ]; then
    kubectl apply -f "$JENKINS_DIR/08-service.yaml"
    echo -e "${GREEN}✅ Service created${NC}\n"
elif [ -f "$JENKINS_DIR/07-service.yaml" ]; then
    # Fallback for old naming
    echo -e "${YELLOW}⚠️  Using old filename: 07-service.yaml${NC}"
    echo -e "${YELLOW}   Consider renaming to 08-service.yaml${NC}"
    kubectl apply -f "$JENKINS_DIR/07-service.yaml"
    echo -e "${GREEN}✅ Service created${NC}\n"
else
    echo -e "${RED}❌ Service file not found${NC}"
    echo -e "${RED}   Expected: $JENKINS_DIR/08-service.yaml${NC}\n"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 9: Wait for Jenkins to be ready
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 9: Waiting for Jenkins pod to be ready...${NC}"
echo "This may take 2-3 minutes (downloading image and installing plugins)..."
echo ""

# Show init container logs while waiting
echo "Watching plugin installation..."
sleep 5

JENKINS_POD=""
for i in {1..30}; do
    JENKINS_POD=$(kubectl get pods -n "$JENKINS_NAMESPACE" -l app=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
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
    INIT_STATUS=$(kubectl get pod -n "$JENKINS_NAMESPACE" $JENKINS_POD -o jsonpath='{.status.initContainerStatuses[0].state}' 2>/dev/null || echo "")
    
    if echo "$INIT_STATUS" | grep -q "running"; then
        echo "Init container is installing plugins..."
        echo "You can watch logs with: kubectl logs -n $JENKINS_NAMESPACE $JENKINS_POD -c install-plugins -f"
    fi
fi

kubectl wait --for=condition=ready pod -l app=jenkins -n "$JENKINS_NAMESPACE" --timeout=300s || {
    echo -e "${RED}❌ Jenkins pod did not become ready in time${NC}"
    echo ""
    echo "Check pod status:"
    echo "  kubectl get pods -n $JENKINS_NAMESPACE"
    echo ""
    echo "Check init container logs:"
    echo "  kubectl logs -n $JENKINS_NAMESPACE $JENKINS_POD -c install-plugins"
    echo ""
    echo "Check main container logs:"
    echo "  kubectl logs -n $JENKINS_NAMESPACE $JENKINS_POD -c jenkins"
    echo ""
    echo "Check events:"
    echo "  kubectl get events -n $JENKINS_NAMESPACE --sort-by='.lastTimestamp'"
    exit 1
}

echo -e "${GREEN}✅ Jenkins is ready!${NC}\n"

# -----------------------------------------------------------------------------
# Step 10: Get Jenkins info and verify plugins
# -----------------------------------------------------------------------------
JENKINS_POD=$(kubectl get pods -n "$JENKINS_NAMESPACE" -l app=jenkins -o jsonpath='{.items[0].metadata.name}')

echo -e "${BLUE}Step 10: Retrieving Jenkins information...${NC}"
echo "Jenkins Pod: $JENKINS_POD"
echo ""

# Check plugin installation
echo "Verifying plugin installation..."
PLUGIN_COUNT=$(kubectl exec -n "$JENKINS_NAMESPACE" $JENKINS_POD -- find /var/jenkins_home/plugins -name "*.jpi" -o -name "*.hpi" 2>/dev/null | wc -l || echo "0")

if [ "$PLUGIN_COUNT" -gt 20 ]; then
    echo -e "${GREEN}✅ $PLUGIN_COUNT plugins installed successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Only $PLUGIN_COUNT plugins found${NC}"
    echo "Check init container logs for errors:"
    echo "  kubectl logs -n $JENKINS_NAMESPACE $JENKINS_POD -c install-plugins"
fi

echo ""

# Verify kubectl, helm, and docker are installed
echo "Verifying tools in Jenkins container..."
kubectl exec -n "$JENKINS_NAMESPACE" $JENKINS_POD -- docker --version
kubectl exec -n "$JENKINS_NAMESPACE" $JENKINS_POD -- kubectl version --client
kubectl exec -n "$JENKINS_NAMESPACE" $JENKINS_POD -- helm version

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
echo "  Password: $JENKINS_ADMIN_PASSWORD"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Change the admin password after first login!${NC}"
echo ""
echo "=========================================="
echo -e "${BLUE}Resources Created:${NC}"
echo "=========================================="
echo ""

# Show all resources
kubectl get all,pvc,configmap,secret -n "$JENKINS_NAMESPACE"

echo ""
echo "=========================================="
echo -e "${BLUE}RBAC Permissions:${NC}"
echo "=========================================="
echo ""
kubectl get clusterrole jenkins-deployer 2>/dev/null && echo "  ✅ ClusterRole: jenkins-deployer" || echo "  ❌ ClusterRole: Not found"
kubectl get clusterrolebinding jenkins-deployer-binding 2>/dev/null && echo "  ✅ ClusterRoleBinding: jenkins-deployer-binding" || echo "  ❌ ClusterRoleBinding: Not found"

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
echo "4. Create your first pipeline:"
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
echo "  kubectl logs -n $JENKINS_NAMESPACE $JENKINS_POD -c jenkins -f"
echo ""
echo "Test kubectl access:"
echo "  kubectl exec -n $JENKINS_NAMESPACE $JENKINS_POD -- kubectl get namespaces"
echo ""
echo "Test helm:"
echo "  kubectl exec -n $JENKINS_NAMESPACE $JENKINS_POD -- helm list -A"
echo ""
echo "Test docker:"
echo "  kubectl exec -n $JENKINS_NAMESPACE $JENKINS_POD -- docker ps"
echo ""
echo "Restart Jenkins:"
echo "  kubectl rollout restart deployment/jenkins -n $JENKINS_NAMESPACE"
echo ""
echo "Uninstall Jenkins:"
echo "  kubectl delete namespace $JENKINS_NAMESPACE"
echo "  kubectl delete clusterrole jenkins-deployer"
echo "  kubectl delete clusterrolebinding jenkins-deployer-binding"
echo ""
echo "=========================================="
echo -e "${GREEN}🎉 Happy CI/CD-ing!${NC}"
echo "=========================================="
echo ""