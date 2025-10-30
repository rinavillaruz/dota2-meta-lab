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
# Step 1: Install Jenkins
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 1: Install Jenkins${NC}"
echo "=========================================="
echo ""

read -p "Install Jenkins in Kubernetes? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if [ -f "$SCRIPT_DIR/install-jenkins.sh" ]; then
        chmod +x "$SCRIPT_DIR/install-jenkins.sh"
        "$SCRIPT_DIR/install-jenkins.sh"
    else
        echo -e "${YELLOW}⚠️  install-jenkins.sh not found, skipping${NC}"
    fi
else
    echo "Skipping Jenkins installation"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 2: Verify ArgoCD
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 2: Verify ArgoCD${NC}"
echo "=========================================="
echo ""

if kubectl get namespace argocd &>/dev/null; then
    echo -e "${GREEN}✅ ArgoCD is installed${NC}"
    
    # Check if logged in
    if argocd context &>/dev/null; then
        echo -e "${GREEN}✅ ArgoCD CLI is logged in${NC}"
    else
        echo -e "${YELLOW}⚠️  Not logged in to ArgoCD${NC}"
        read -p "Login to ArgoCD now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if [ -f "$SCRIPT_DIR/argocd-login.sh" ]; then
                chmod +x "$SCRIPT_DIR/argocd-login.sh"
                "$SCRIPT_DIR/argocd-login.sh"
            fi
        fi
    fi
else
    echo -e "${RED}❌ ArgoCD not found${NC}"
    echo "Please install ArgoCD first:"
    echo "  ./install-argocd.sh"
    exit 1
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
    [ -f "$SCRIPT_DIR/Jenkinsfile" ] && cp "$SCRIPT_DIR/Jenkinsfile" "$PROJECT_ROOT/"
    [ -f "$SCRIPT_DIR/Dockerfile" ] && cp "$SCRIPT_DIR/Dockerfile" "$PROJECT_ROOT/"
    [ -f "$SCRIPT_DIR/requirements.txt" ] && cp "$SCRIPT_DIR/requirements.txt" "$PROJECT_ROOT/"
    [ -f "$SCRIPT_DIR/fetch_opendota_data.py" ] && cp "$SCRIPT_DIR/fetch_opendota_data.py" "$PROJECT_ROOT/"
    [ -f "$SCRIPT_DIR/train_model.py" ] && cp "$SCRIPT_DIR/train_model.py" "$PROJECT_ROOT/"
    [ -f "$SCRIPT_DIR/SETUP_GUIDE.md" ] && cp "$SCRIPT_DIR/SETUP_GUIDE.md" "$PROJECT_ROOT/"
    
    echo -e "${GREEN}✅ Project files copied${NC}"
    
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
!helm/**/*.json

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
        pip install requests || true
        
        echo "Fetching sample data..."
        python fetch_opendota_data.py
        
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
echo "   Password: admin"
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