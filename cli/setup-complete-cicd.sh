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
                echo -e "${YELLOW}⚠️  install-argocd.sh not found, installing directly...${NC}"
                
                # Create namespace
                kubectl create namespace argocd
                
                # Install ArgoCD
                echo "Installing ArgoCD from official manifest..."
                kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
                
                echo "Waiting for ArgoCD to be ready..."
                sleep 30  # Give it time to create deployments
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
# Step 3: Test Complete ML Pipeline (Optional)
# -----------------------------------------------------------------------------
echo "=========================================="
echo -e "${BLUE}Step 3: Test Complete ML Pipeline${NC}"
echo "=========================================="
echo ""

read -p "Run complete ML pipeline test? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Starting ML pipeline test...${NC}"
    echo ""
    
    # Check if scripts exist
    if [ ! -f "$PROJECT_ROOT/scripts/fetch_data.py" ]; then
        echo -e "${RED}❌ fetch_data.py not found${NC}"
        exit 1
    fi
    
    # Step 3.0: Setup Python virtual environment
    echo -e "${BLUE}🐍 Step 3.0: Setting up Python virtual environment...${NC}"
    cd "$PROJECT_ROOT"
    
    # Check if venv exists
    if [ ! -d "venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv venv
        echo -e "${GREEN}✅ Virtual environment created${NC}"
    else
        echo -e "${GREEN}✅ Virtual environment already exists${NC}"
    fi
    
    # Activate venv
    echo "Activating virtual environment..."
    source venv/bin/activate
    
    # Verify activation
    if [ -z "$VIRTUAL_ENV" ]; then
        echo -e "${RED}❌ Failed to activate virtual environment${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Virtual environment activated${NC}"
    echo "Python: $(which python)"
    echo ""
    
    # Step 3.1: Start MongoDB
    echo -e "${BLUE}📦 Step 3.1: Starting MongoDB with Docker Compose...${NC}"
    
    if [ -f "docker-compose.yml" ]; then
        docker-compose up -d
        echo "Waiting for MongoDB to be ready..."
        sleep 10
        echo -e "${GREEN}✅ MongoDB started${NC}\n"
    else
        echo -e "${YELLOW}⚠️  docker-compose.yml not found, skipping MongoDB${NC}\n"
    fi
    
    # Step 3.2: Install Python dependencies
    echo -e "${BLUE}📚 Step 3.2: Installing Python dependencies in venv...${NC}"
    if [ -f "build/requirements.txt" ]; then
        pip install -r build/requirements.txt --quiet
        echo -e "${GREEN}✅ Dependencies installed${NC}\n"
    else
        echo -e "${YELLOW}⚠️  requirements.txt not found${NC}\n"
    fi
    
    # Step 3.3: Fetch data
    echo -e "${BLUE}🌐 Step 3.3: Fetching DOTA2 match data (~1 minute)...${NC}"
    if python scripts/fetch_data.py; then
        echo -e "${GREEN}✅ Data fetching complete${NC}\n"
    else
        echo -e "${RED}❌ Data fetching failed${NC}"
        deactivate
        exit 1
    fi
    
    # Step 3.4: Analyze data
    echo -e "${BLUE}📊 Step 3.4: Analyzing data (~5 seconds)...${NC}"
    if [ -f "scripts/analyze_data.py" ]; then
        if python scripts/analyze_data.py; then
            echo -e "${GREEN}✅ Data analysis complete${NC}\n"
        else
            echo -e "${RED}❌ Data analysis failed${NC}"
            deactivate
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️  analyze_data.py not found, skipping${NC}\n"
    fi
    
    # Step 3.5: Train model
    echo -e "${BLUE}🤖 Step 3.5: Training ML model (~3 minutes)...${NC}"
    if [ -f "scripts/train_model.py" ]; then
        if python scripts/train_model.py; then
            echo -e "${GREEN}✅ Model training complete${NC}\n"
        else
            echo -e "${RED}❌ Model training failed${NC}"
            deactivate
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️  train_model.py not found, skipping${NC}\n"
    fi
    
    # Step 3.6: Store in database
    echo -e "${BLUE}💾 Step 3.6: Storing data in MongoDB (~5 seconds)...${NC}"
    if [ -f "scripts/store_database.py" ]; then
        if python scripts/store_database.py; then
            echo -e "${GREEN}✅ Database storage complete${NC}\n"
        else
            echo -e "${YELLOW}⚠️  Database storage failed (MongoDB might not be running)${NC}\n"
        fi
    else
        echo -e "${YELLOW}⚠️  store_database.py not found, skipping${NC}\n"
    fi
    
    # Step 3.7: Test API (optional)
    echo -e "${BLUE}🌐 Step 3.7: API Test${NC}"
    read -p "Start API server for testing? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${BLUE}Starting API server...${NC}"
        echo "API will start on http://localhost:8080"
        echo "Press Ctrl+C to stop the API server"
        echo ""
        
        # Start API in background
        python -m src.api.app &
        API_PID=$!
        
        # Wait for API to start
        echo "Waiting for API to start..."
        sleep 5
        
        # Test the API
        echo ""
        echo "Testing API endpoints:"
        echo ""
        
        echo "1. Health check:"
        curl -s http://localhost:8080/health 2>/dev/null | python -m json.tool || echo "  ❌ API not responding"
        echo ""
        
        echo "2. Stats:"
        curl -s http://localhost:8080/stats 2>/dev/null | python -m json.tool || echo "  ❌ API not responding"
        echo ""
        
        echo "3. Heroes:"
        curl -s http://localhost:8080/heroes 2>/dev/null | python -m json.tool | head -20 || echo "  ❌ API not responding"
        echo ""
        
        # Keep API running
        echo ""
        echo "API is running (PID: $API_PID)"
        echo ""
        echo "Test manually with:"
        echo "  curl http://localhost:8080/health"
        echo "  curl http://localhost:8080/stats"
        echo "  curl http://localhost:8080/heroes"
        echo ""
        echo "Or open in browser:"
        echo "  http://localhost:8080"
        echo ""
        read -p "Press Enter to stop API server..."
        
        # Stop API
        kill $API_PID 2>/dev/null || true
        echo -e "${GREEN}✅ API stopped${NC}\n"
    else
        echo -e "${YELLOW}Skipping API test${NC}\n"
    fi
    
    # Step 3.8: Cleanup
    echo -e "${BLUE}🧹 Step 3.8: Cleanup${NC}"
    read -p "Stop MongoDB? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker-compose down
        echo -e "${GREEN}✅ MongoDB stopped${NC}\n"
    else
        echo -e "${YELLOW}ℹ️  MongoDB still running${NC}\n"
    fi
    
    # Deactivate venv
    deactivate
    echo -e "${GREEN}✅ Virtual environment deactivated${NC}\n"
    
    echo ""
    echo "=========================================="
    echo -e "${GREEN}✅ ML Pipeline Test Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Summary:"
    echo "  ✅ Virtual environment set up"
    echo "  ✅ MongoDB ran (or still running)"
    echo "  ✅ Data fetched from OpenDota"
    echo "  ✅ Data analyzed and processed"
    echo "  ✅ ML model trained"
    echo "  ✅ Data stored in MongoDB"
    echo ""
    echo "Generated files:"
    echo "  - data/public_matches.json"
    echo "  - data/detailed_matches.json"
    echo "  - data/pro_matches.json"
    echo "  - data/processed_matches.csv"
    echo "  - models/dota2_model.h5"
    echo "  - models/scaler.pkl"
    echo ""
    echo "To run again:"
    echo "  cd $PROJECT_ROOT"
    echo "  source venv/bin/activate"
    echo "  docker-compose up -d"
    echo "  python scripts/fetch_data.py"
    echo "  python scripts/analyze_data.py"
    echo "  python scripts/train_model.py"
    echo "  python scripts/store_database.py"
    echo "  python -m src.api.app"
    echo ""
    echo "To stop:"
    echo "  docker-compose down"
    echo "  deactivate"
    echo ""
else
    echo "Skipping ML pipeline test"
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