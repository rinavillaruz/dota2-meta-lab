#!/bin/bash

set -e

echo "🚀 Dota 2 Meta Lab - Complete CI/CD Setup"
echo "=========================================="
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

# Configuration (with defaults)
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
ARGOCD_HOST="${ARGOCD_HOST:-localhost}"
ARGOCD_PORT="${ARGOCD_PORT:-30080}"
JENKINS_HOST="${JENKINS_HOST:-localhost}"
JENKINS_PORT="${JENKINS_PORT:-30808}"

# Debug mode
if [ "${DEBUG:-false}" = "true" ]; then
    echo "🐛 Debug - Configuration:"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  ARGOCD_NAMESPACE: $ARGOCD_NAMESPACE"
    echo "  JENKINS_NAMESPACE: $JENKINS_NAMESPACE"
    echo ""
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Project Root: ${PROJECT_ROOT}${NC}\n"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Function to check if ArgoCD is fully functional
check_argocd_functional() {
    local retries=0
    local max_retries=30
    
    echo "Checking ArgoCD status..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
        return 1
    fi
    
    # Check if ArgoCD server pod is running
    while [ $retries -lt $max_retries ]; do
        if kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
            echo -e "${GREEN}✅ ArgoCD server is running${NC}"
            return 0
        fi
        retries=$((retries + 1))
        if [ $retries -lt $max_retries ]; then
            echo "Waiting for ArgoCD server to be ready... ($retries/$max_retries)"
            sleep 2
        fi
    done
    
    return 1
}

# Function to check if Jenkins is functional
check_jenkins_functional() {
    echo "Checking Jenkins status..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$JENKINS_NAMESPACE" &>/dev/null; then
        return 1
    fi
    
    # Check if Jenkins pod is running - try Helm label first
    if kubectl get pods -n "$JENKINS_NAMESPACE" -l app.kubernetes.io/name=jenkins --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}✅ Jenkins is running (Helm installation)${NC}"
        return 0
    fi
    
    # Try simple install label
    if kubectl get pods -n "$JENKINS_NAMESPACE" -l app=jenkins --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}✅ Jenkins is running (Simple installation)${NC}"
        return 0
    fi
    
    return 1
}

# -----------------------------------------------------------------------------
# Step 1: Install Jenkins
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 1: Install Jenkins${NC}"
echo "=========================================="
echo ""

# Check if Jenkins is already installed and functional
if check_jenkins_functional; then
    echo -e "${GREEN}✅ Jenkins is already installed and running${NC}"
    read -p "Reinstall Jenkins? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstalling existing Jenkins..."
        kubectl delete namespace "$JENKINS_NAMESPACE" --ignore-not-found=true
        kubectl wait --for=delete namespace/"$JENKINS_NAMESPACE" --timeout=60s 2>/dev/null || true
        
        if [ -f "$SCRIPT_DIR/install-jenkins.sh" ]; then
            chmod +x "$SCRIPT_DIR/install-jenkins.sh"
            "$SCRIPT_DIR/install-jenkins.sh"
        else
            echo -e "${RED}❌ install-jenkins.sh not found${NC}"
            exit 1
        fi
    else
        echo "Using existing Jenkins installation"
    fi
else
    read -p "Install Jenkins in Kubernetes? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if [ -f "$SCRIPT_DIR/install-jenkins.sh" ]; then
            chmod +x "$SCRIPT_DIR/install-jenkins.sh"
            "$SCRIPT_DIR/install-jenkins.sh"
            
            # Verify installation
            echo "Waiting for Jenkins to be ready..."
            sleep 10
            
            if check_jenkins_functional; then
                echo -e "${GREEN}✅ Jenkins installation successful${NC}"
            else
                echo -e "${YELLOW}⚠️  Jenkins pod may still be starting${NC}"
                echo "Check status with: kubectl get pods -n $JENKINS_NAMESPACE"
            fi
        else
            echo -e "${YELLOW}⚠️  install-jenkins.sh not found, skipping${NC}"
        fi
    else
        echo "Skipping Jenkins installation"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Step 2: Verify/Install ArgoCD
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 2: Verify/Install ArgoCD${NC}"
echo "=========================================="
echo ""

# Check if ArgoCD is functional
if check_argocd_functional; then
    echo -e "${GREEN}✅ ArgoCD is installed and running${NC}"
    
    # Check if logged in
    if argocd context &>/dev/null 2>&1; then
        echo -e "${GREEN}✅ ArgoCD CLI is logged in${NC}"
    else
        echo -e "${YELLOW}⚠️  Not logged in to ArgoCD${NC}"
        read -p "Login to ArgoCD now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if [ -f "$SCRIPT_DIR/argocd-login.sh" ]; then
                chmod +x "$SCRIPT_DIR/argocd-login.sh"
                "$SCRIPT_DIR/argocd-login.sh"
            else
                echo -e "${YELLOW}⚠️  argocd-login.sh not found${NC}"
                echo "You can login manually with: argocd login <server>"
            fi
        fi
    fi
else
    # ArgoCD namespace exists but not functional, or doesn't exist at all
    if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
        echo -e "${YELLOW}⚠️  ArgoCD namespace exists but is not functional${NC}"
        read -p "Reinstall ArgoCD? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "Cleaning up existing ArgoCD installation..."
            kubectl delete namespace "$ARGOCD_NAMESPACE" --ignore-not-found=true
            
            # Clean up CRDs
            kubectl delete crd applications.argoproj.io --ignore-not-found=true
            kubectl delete crd applicationsets.argoproj.io --ignore-not-found=true
            kubectl delete crd appprojects.argoproj.io --ignore-not-found=true
            
            # Wait for namespace deletion
            echo "Waiting for namespace deletion..."
            kubectl wait --for=delete namespace/"$ARGOCD_NAMESPACE" --timeout=120s 2>/dev/null || true
            sleep 5
            
            # Install ArgoCD
            if [ -f "$SCRIPT_DIR/install-argocd.sh" ]; then
                chmod +x "$SCRIPT_DIR/install-argocd.sh"
                "$SCRIPT_DIR/install-argocd.sh"
            else
                echo -e "${YELLOW}⚠️  install-argocd.sh not found, installing directly...${NC}"
                
                # Create namespace
                kubectl create namespace "$ARGOCD_NAMESPACE"
                
                # Install ArgoCD
                echo "Installing ArgoCD from official manifest..."
                kubectl apply -n "$ARGOCD_NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
                
                echo "Waiting for ArgoCD to be ready..."
                sleep 30
            fi
            
            # Verify installation
            if check_argocd_functional; then
                echo -e "${GREEN}✅ ArgoCD reinstallation successful${NC}"
            else
                echo -e "${RED}❌ ArgoCD installation failed${NC}"
                exit 1
            fi
        else
            echo -e "${RED}❌ ArgoCD is not functional, cannot continue${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ ArgoCD not found${NC}"
        read -p "Install ArgoCD now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if [ -f "$SCRIPT_DIR/install-argocd.sh" ]; then
                chmod +x "$SCRIPT_DIR/install-argocd.sh"
                "$SCRIPT_DIR/install-argocd.sh"
                
                # Verify installation
                if check_argocd_functional; then
                    echo -e "${GREEN}✅ ArgoCD installation successful${NC}"
                    
                    # Login
                    if [ -f "$SCRIPT_DIR/argocd-login.sh" ]; then
                        echo ""
                        read -p "Login to ArgoCD now? (Y/n): " -n 1 -r
                        echo
                        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                            chmod +x "$SCRIPT_DIR/argocd-login.sh"
                            "$SCRIPT_DIR/argocd-login.sh"
                        fi
                    fi
                else
                    echo -e "${RED}❌ ArgoCD installation failed${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}❌ install-argocd.sh not found${NC}"
                echo "Please create install-argocd.sh or install ArgoCD manually"
                exit 1
            fi
        else
            echo -e "${RED}❌ Cannot continue without ArgoCD${NC}"
            exit 1
        fi
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Step 3: Verify Docker Setup
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 3: Verify Docker Environment${NC}"
echo "=========================================="
echo ""

if command -v docker &> /dev/null; then
    echo -e "${GREEN}✅ Docker is installed${NC}"
    
    if command -v docker-compose &> /dev/null; then
        echo -e "${GREEN}✅ Docker Compose is installed${NC}"
    else
        echo -e "${YELLOW}⚠️  Docker Compose not found${NC}"
        echo "Install with: brew install docker-compose"
    fi
else
    echo -e "${RED}❌ Docker not found${NC}"
    echo "Install Docker Desktop from: https://www.docker.com/products/docker-desktop"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 4: Setup Application Environment
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 4: Setup Application Environment${NC}"
echo "=========================================="
echo ""

read -p "Setup local Docker development environment? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    cd "$PROJECT_ROOT"
    
    # Create necessary directories
    echo "Creating project directories..."
    mkdir -p data/mongodb data/redis logs models notebooks
    echo -e "${GREEN}✅ Directories created${NC}"
    
    # Check for docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        echo ""
        echo -e "${BLUE}Starting Docker services...${NC}"
        docker-compose up -d
        
        echo ""
        echo "Waiting for services to be healthy..."
        sleep 10
        
        # Check if services are running
        if docker-compose ps | grep -q "Up"; then
            echo -e "${GREEN}✅ Docker services started${NC}"
            echo ""
            echo "Running services:"
            docker-compose ps
        else
            echo -e "${YELLOW}⚠️  Some services may not be running${NC}"
            echo "Check with: docker-compose ps"
        fi
    else
        echo -e "${YELLOW}⚠️  docker-compose.yml not found${NC}"
        echo "Create docker-compose.yml to define your services"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Local environment setup complete${NC}"
    echo ""
    echo "Services available:"
    echo "  📊 Jupyter:  http://localhost:8888"
    echo "  🌐 API:      http://localhost:8080"
    echo "  🗄️  MongoDB:  localhost:27017"
    echo "  🔴 Redis:    localhost:6379"
    echo ""
    echo "Useful commands:"
    echo "  docker-compose ps              # Check service status"
    echo "  docker-compose logs -f         # View all logs"
    echo "  docker-compose logs -f api     # View API logs"
    echo "  docker-compose down            # Stop all services"
    echo ""
else
    echo "Skipping local environment setup"
fi

echo ""

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo -e "${GREEN}✅ CI/CD Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "🎉 Your Dota 2 Meta Lab CI/CD environment is ready!"
echo ""
echo "What's been set up:"
echo "  ✅ Jenkins (CI/CD) - http://${JENKINS_HOST}:${JENKINS_PORT}"
echo "  ✅ ArgoCD (GitOps) - http://${ARGOCD_HOST}:${ARGOCD_PORT}"
echo "  ✅ Docker environment (if selected)"
echo "  ✅ Project directories"
echo ""
echo "=========================================="
echo -e "${YELLOW}📝 Next Steps${NC}"
echo "=========================================="
echo ""
echo "1. Configure Jenkins:"
echo "   • Access: http://${JENKINS_HOST}:${JENKINS_PORT}"
echo "   • Username: admin"
echo "   • Get password: kubectl get secret jenkins-admin-credentials -n $JENKINS_NAMESPACE -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "2. Add credentials to Jenkins:"
echo "   • GitHub token"
echo "   • Docker Hub credentials"
echo "   • Slack webhook (optional)"
echo ""
echo "3. Start building your application:"
echo "   cd $PROJECT_ROOT"
echo "   docker-compose up -d                 # Start services"
echo "   docker-compose logs -f data-fetcher  # Watch data collection"
echo ""
echo "4. Application will automatically:"
echo "   ✅ Fetch Dota 2 match data (every hour)"
echo "   ✅ Train ML models (daily)"
echo "   ✅ Serve predictions via API"
echo ""
echo "5. Commit and push your code:"
echo "   git add ."
echo "   git commit -m 'feat: setup CI/CD pipeline'"
echo "   git push origin main"
echo ""
echo "=========================================="
echo -e "${BLUE}📚 Service URLs${NC}"
echo "=========================================="
echo ""
echo "Jenkins:     http://${JENKINS_HOST}:${JENKINS_PORT}"
echo "ArgoCD:      http://${ARGOCD_HOST}:${ARGOCD_PORT}"
echo "Jupyter:     http://localhost:8888   (if Docker running)"
echo "API:         http://localhost:8080   (if Docker running)"
echo ""
echo "=========================================="
echo -e "${BLUE}🔧 Troubleshooting${NC}"
echo "=========================================="
echo ""
echo "Check Kubernetes pods:"
echo "  kubectl get pods -A"
echo ""
echo "View Jenkins logs:"
echo "  kubectl logs -n $JENKINS_NAMESPACE -l app=jenkins -f"
echo ""
echo "View ArgoCD logs:"
echo "  kubectl logs -n $ARGOCD_NAMESPACE -l app.kubernetes.io/name=argocd-server -f"
echo ""
echo "Check Docker services:"
echo "  docker-compose ps"
echo "  docker-compose logs"
echo ""
echo "Restart services:"
echo "  docker-compose restart"
echo ""
echo "=========================================="
echo -e "${GREEN}🚀 Happy Building!${NC}"
echo "=========================================="
echo ""