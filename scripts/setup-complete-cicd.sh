#!/bin/bash

set -e

echo "🚀 Dota 2 Meta Lab - Complete Setup"
echo "===================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Setup directories
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
    if ! kubectl get namespace argocd &>/dev/null; then
        return 1
    fi
    
    # Check if ArgoCD server pod is running
    while [ $retries -lt $max_retries ]; do
        if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
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
# Supports both Helm (app.kubernetes.io/name=jenkins) and Simple (app=jenkins) labels
check_jenkins_functional() {
    echo "Checking Jenkins status..."
    
    # Check if namespace exists
    if ! kubectl get namespace jenkins &>/dev/null; then
        return 1
    fi
    
    # Check if Jenkins pod is running - try Helm label first
    if kubectl get pods -n jenkins -l app.kubernetes.io/name=jenkins --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}✅ Jenkins is running (Helm installation)${NC}"
        return 0
    fi
    
    # Try simple install label
    if kubectl get pods -n jenkins -l app=jenkins --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
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
        kubectl delete namespace jenkins --ignore-not-found=true
        kubectl wait --for=delete namespace/jenkins --timeout=60s 2>/dev/null || true
        
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
            
            # Verify installation (give it time to start)
            echo "Waiting for Jenkins to be ready..."
            sleep 10
            
            if check_jenkins_functional; then
                echo -e "${GREEN}✅ Jenkins installation successful${NC}"
            else
                echo -e "${YELLOW}⚠️  Jenkins pod may still be starting${NC}"
                echo "Check status with: kubectl get pods -n jenkins"
                echo "Check logs with: kubectl logs -n jenkins -l app=jenkins"
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
    if kubectl get namespace argocd &>/dev/null; then
        echo -e "${YELLOW}⚠️  ArgoCD namespace exists but is not functional${NC}"
        read -p "Reinstall ArgoCD? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "Cleaning up existing ArgoCD installation..."
            kubectl delete namespace argocd --ignore-not-found=true
            
            # Clean up CRDs
            kubectl delete crd applications.argoproj.io --ignore-not-found=true
            kubectl delete crd applicationsets.argoproj.io --ignore-not-found=true
            kubectl delete crd appprojects.argoproj.io --ignore-not-found=true
            
            # Wait for namespace deletion
            echo "Waiting for namespace deletion..."
            kubectl wait --for=delete namespace/argocd --timeout=120s 2>/dev/null || true
            sleep 5
            
            # Install ArgoCD
            if [ -f "$SCRIPT_DIR/install-argocd.sh" ]; then
                chmod +x "$SCRIPT_DIR/install-argocd.sh"
                "$SCRIPT_DIR/install-argocd.sh"
            else
                echo -e "${RED}❌ install-argocd.sh not found${NC}"
                exit 1
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
# Step 3: Copy Project Files
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 3: Setup Project Files${NC}"
echo "=========================================="
echo ""

read -p "Copy project files to repository? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    # Create directories
    mkdir -p "$PROJECT_ROOT/src/data"
    mkdir -p "$PROJECT_ROOT/src/models"
    mkdir -p "$PROJECT_ROOT/src/api"
    mkdir -p "$PROJECT_ROOT/api"
    mkdir -p "$PROJECT_ROOT/tests"
    mkdir -p "$PROJECT_ROOT/data"
    mkdir -p "$PROJECT_ROOT/models"
    
    # Copy files if they exist in script directory
    files_copied=0
    [ -f "$SCRIPT_DIR/ci/Jenkinsfile" ] && cp "$SCRIPT_DIR/ci/Jenkinsfile" "$PROJECT_ROOT/" && ((files_copied++))
    [ -f "$SCRIPT_DIR/build/Dockerfile" ] && cp "$SCRIPT_DIR/build/Dockerfile" "$PROJECT_ROOT/" && ((files_copied++))
    [ -f "$SCRIPT_DIR/build/requirements.txt" ] && cp "$SCRIPT_DIR/build/requirements.txt" "$PROJECT_ROOT/" && ((files_copied++))
    [ -f "$SCRIPT_DIR/fetch_opendota_data.py" ] && cp "$SCRIPT_DIR/fetch_opendota_data.py" "$PROJECT_ROOT/" && ((files_copied++))
    [ -f "$SCRIPT_DIR/train_model.py" ] && cp "$SCRIPT_DIR/train_model.py" "$PROJECT_ROOT/" && ((files_copied++))
    [ -f "$SCRIPT_DIR/SETUP_GUIDE.md" ] && cp "$SCRIPT_DIR/SETUP_GUIDE.md" "$PROJECT_ROOT/" && ((files_copied++))
    
    if [ $files_copied -gt 0 ]; then
        echo -e "${GREEN}✅ $files_copied project file(s) copied${NC}"
    else
        echo -e "${YELLOW}⚠️  No project files found to copy${NC}"
    fi
    
    # Create __init__.py files
    touch "$PROJECT_ROOT/src/__init__.py"
    touch "$PROJECT_ROOT/src/data/__init__.py"
    touch "$PROJECT_ROOT/src/models/__init__.py"
    touch "$PROJECT_ROOT/src/api/__init__.py"
    touch "$PROJECT_ROOT/api/__init__.py"
    touch "$PROJECT_ROOT/tests/__init__.py"
    
    echo -e "${GREEN}✅ Python package structure created${NC}"
else
    echo "Skipping file copy"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 4: Create .gitignore
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 4: Create .gitignore${NC}"
echo "=========================================="
echo ""

if [ ! -f "$PROJECT_ROOT/.gitignore" ]; then
    cat > "$PROJECT_ROOT/.gitignore" << 'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
ENV/
.venv
pip-log.txt
pip-delete-this-directory.txt

# IDEs
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Data
data/opendota_*/
*.csv
*.json
!deploy/helm/**/*.json

# Models
models/*.h5
models/*.pkl
*.ckpt

# Logs
logs/
*.log

# Testing
.pytest_cache/
.coverage
htmlcov/

# Kubernetes
*.kubeconfig

# Secrets
.env
secrets/
EOF
    echo -e "${GREEN}✅ .gitignore created${NC}"
else
    echo -e "${YELLOW}ℹ️  .gitignore already exists${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 5: Test Data Fetching (Optional)
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 5: Test Data Fetching${NC}"
echo "=========================================="
echo ""

read -p "Test OpenDota data fetching? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -f "$PROJECT_ROOT/fetch_opendota_data.py" ]; then
        cd "$PROJECT_ROOT"
        echo "Installing dependencies..."
        pip install requests --break-system-packages 2>/dev/null || pip install requests || true
        
        echo "Fetching sample data..."
        python3 fetch_opendota_data.py || python fetch_opendota_data.py
        
        echo -e "${GREEN}✅ Data fetching test complete${NC}"
    else
        echo -e "${RED}❌ fetch_opendota_data.py not found${NC}"
    fi
else
    echo "Skipping data fetch test"
fi

echo ""

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "🎉 Your Dota 2 Meta Lab is ready!"
echo ""
echo "What's been set up:"
echo "  ✅ Jenkins (CI/CD)"
echo "  ✅ ArgoCD (GitOps)"
echo "  ✅ Project structure"
echo "  ✅ Python scripts (data fetching & training)"
echo "  ✅ Docker configuration"
echo "  ✅ Jenkins pipeline"
echo ""
echo "=========================================="
echo -e "${YELLOW}📝 Next Steps${NC}"
echo "=========================================="
echo ""
echo "1. Review the setup guide:"
echo "   cat $PROJECT_ROOT/SETUP_GUIDE.md"
echo ""
echo "2. Commit and push your code:"
echo "   cd $PROJECT_ROOT"
echo "   git add ."
echo "   git commit -m 'ci: add Jenkins pipeline and ML scripts'"
echo "   git push"
echo ""
echo "3. Access Jenkins:"
echo "   http://localhost:30808"
echo "   Username: admin"
echo "   Password: admin (or check initial password)"
echo ""
echo "4. Access ArgoCD:"
echo "   http://localhost:30080"
echo ""
echo "5. Configure Jenkins credentials:"
echo "   - GitHub token"
echo "   - Docker Hub credentials"
echo ""
echo "6. Create Jenkins pipeline job"
echo ""
echo "7. Start building! 🚀"
echo ""
echo "=========================================="
echo -e "${BLUE}📚 Resources${NC}"
echo "=========================================="
echo ""
echo "Setup Guide: $PROJECT_ROOT/SETUP_GUIDE.md"
echo "OpenDota API: https://docs.opendota.com/"
echo "Jenkins: http://localhost:30808"
echo "ArgoCD: http://localhost:30080"
echo ""
echo "=========================================="
echo -e "${BLUE}🔧 Troubleshooting${NC}"
echo "=========================================="
echo ""
echo "View Jenkins pods:"
echo "  kubectl get pods -n jenkins"
echo ""
echo "View Jenkins logs:"
echo "  kubectl logs -n jenkins -l app=jenkins -f"
echo ""
echo "View ArgoCD logs:"
echo "  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server"
echo ""
echo "Check all pods:"
echo "  kubectl get pods -A"
echo ""