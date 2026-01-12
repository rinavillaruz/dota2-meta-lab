#!/bin/bash

set -e  # Exit on any error

# ========================================
# 🎨 Colors for output
# ========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_red() { echo -e "${RED}$1${NC}"; }
print_green() { echo -e "${GREEN}$1${NC}"; }
print_blue() { echo -e "${BLUE}$1${NC}"; }
print_yellow() { echo -e "${YELLOW}$1${NC}"; }

# ========================================
# 📋 Script header
# ========================================
echo ""
print_green "🚀 Deploying Dota2 Meta Lab Platform with Helm..."
echo ""

# ========================================
# 📥 Parse arguments
# ========================================
ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}

print_blue "🎯 Deploying to environment: $ENVIRONMENT"
echo ""
print_blue "📦 Image tag: $IMAGE_TAG"
echo ""

# ========================================
# 🔐 Step 0: Detect environment and load credentials
# ========================================
print_blue "🔐 Step 0: Loading environment variables..."

if [ -n "$JENKINS_HOME" ]; then
    print_blue "🤖 Running in Jenkins CI/CD"
    IN_JENKINS=true
    SKIP_KIND=true
    SKIP_METRICS=true
    export DEBIAN_FRONTEND=noninteractive
    
    # Set kubeconfig if running in Jenkins
    export KUBECONFIG=${KUBECONFIG:-/var/jenkins_home/.kube/config}
    
    # Try to set context to kind-kind
    if kubectl config get-contexts kind-kind &> /dev/null; then
        kubectl config use-context kind-kind
        print_green "✅ Using kind-kind context"
    else
        print_yellow "⚠️  kind-kind context not found, using current context"
    fi
    
    # Verify kubectl can connect
    if ! kubectl cluster-info &> /dev/null; then
        print_red "❌ Cannot connect to Kubernetes cluster"
        print_yellow "Attempting to list available contexts..."
        kubectl config get-contexts || true
        exit 1
    fi
    
    print_green "✅ Kubernetes connection verified"
    
    # Load credentials from Kubernetes secrets (mounted as env vars)
    export MONGODB_USERNAME=${MONGODB_USERNAME:-admin}
    export MONGODB_PASSWORD=${MONGODB_PASSWORD:-password123}
    
else
    print_blue "💻 Running locally"
    IN_JENKINS=false
    SKIP_KIND=false
    SKIP_METRICS=false
    
    # Load .env file
    if [ ! -f ../.env ]; then
        print_red "❌ Error: .env file not found in root directory!"
        echo "Please create a .env file with:"
        echo "  MONGODB_USERNAME=your_username"
        echo "  MONGODB_PASSWORD=your_password"
        exit 1
    fi
    
    export $(cat ../.env | grep -v '^#' | xargs)
fi

# Verify required variables
if [ -z "$MONGODB_USERNAME" ] || [ -z "$MONGODB_PASSWORD" ]; then
    print_red "❌ Error: MONGODB_USERNAME or MONGODB_PASSWORD not set"
    exit 1
fi

print_green "✅ Environment variables loaded"
echo ""

# ========================================
# 🔍 Step 1: Cluster setup
# ========================================
if [ "$SKIP_KIND" = false ]; then
    print_blue "🔍 Step 1: Checking for existing cluster..."
    if kind get clusters 2>/dev/null | grep -q "ml-cluster"; then
        print_yellow "⚠️  Cluster 'ml-cluster' already exists. Skipping creation."
    else
        print_blue "🏗️  Creating directories..."
        mkdir -p ../data/{control-plane-{1..3},ml-training,mongodb,redis} ../models
        
        print_blue "🏗️  Creating Kind cluster..."
        kind create cluster --config ../k8s/ha/kind-ha-cluster.yaml --name ml-cluster
        print_green "✅ Cluster created"
        
        echo "⏳ Waiting for cluster to be ready..."
        kubectl wait --for=condition=Ready nodes --all --timeout=180s
        print_green "✅ Cluster is ready"
    fi
else
    print_blue "🔍 Step 1: Using existing Kubernetes cluster"
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
    echo "Current context: $CURRENT_CONTEXT"
    
    # Show available contexts if connection fails
    if [ "$CURRENT_CONTEXT" = "none" ]; then
        print_yellow "Available contexts:"
        kubectl config get-contexts || print_red "No kubeconfig found"
    fi
    
    print_green "✅ Cluster ready"
fi
echo ""

# ========================================
# 📊 Step 1.5: Metrics Server
# ========================================
if [ "$SKIP_METRICS" = false ]; then
    print_blue "📊 Step 1.5: Installing Metrics Server..."
    
    if ! kubectl cluster-info &> /dev/null; then
        print_red "❌ Cannot connect to cluster"
        echo "Current context: $(kubectl config current-context 2>/dev/null || echo 'none')"
        exit 1
    fi

    if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        print_yellow "⚠️  Metrics server already installed"
    else
        echo "Installing metrics server..."
        kubectl apply --validate=false -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        
        sleep 5
        
        echo "Patching metrics server for Kind cluster..."
        kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/args/-",
            "value": "--kubelet-insecure-tls"
        }
        ]'
        
        print_green "✅ Metrics server installed"
        echo "⏳ Waiting for metrics server to be ready..."
        kubectl wait --for=condition=available --timeout=120s deployment/metrics-server -n kube-system || {
            print_yellow "⚠️  Metrics server still starting (this is OK)"
        }
    fi
else
    print_blue "📊 Step 1.5: Skipping metrics server (already installed)"
fi
echo ""

# ========================================
# 📦 Step 2: Create namespaces
# ========================================
print_blue "📦 Step 2: Creating namespaces..."
kubectl create namespace data --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ml-pipeline --dry-run=client -o yaml | kubectl apply -f -
print_green "✅ Namespaces created"
echo ""

sleep 2

# ========================================
# 🔐 Step 3: Create secrets
# ========================================
print_blue "🔐 Step 3: Creating secrets..."
kubectl create secret generic mongodb-secret \
  --from-literal=username="$MONGODB_USERNAME" \
  --from-literal=password="$MONGODB_PASSWORD" \
  --namespace=data \
  --dry-run=client -o yaml | kubectl apply -f -

if kubectl get secret mongodb-secret -n data &> /dev/null; then
    print_green "✅ MongoDB secret created successfully"
else
    print_red "❌ Failed to create MongoDB secret"
    exit 1
fi
echo ""

# ========================================
# 🎡 Step 4: Deploy with Helm
# ========================================
print_blue "🎡 Step 4: Deploying with Helm..."

# Navigate to helm chart directory
cd "$(dirname "$0")/../deploy/helm" || {
    print_red "❌ Cannot find Helm chart directory"
    print_yellow "Current directory: $(pwd)"
    print_yellow "Looking for: $(dirname "$0")/../deploy/helm"
    exit 1
}

print_blue "Current directory: $(pwd)"

# Validate Helm chart
echo "Validating Helm chart..."
if helm lint .; then
    print_green "✅ Helm chart validation passed"
else
    print_red "❌ Helm chart validation failed"
    exit 1
fi
echo ""

# Check if values file exists
if [ ! -f "values-${ENVIRONMENT}.yaml" ]; then
    print_red "❌ Error: values-${ENVIRONMENT}.yaml not found!"
    echo ""
    echo "Available values files:"
    ls -1 values*.yaml 2>/dev/null || echo "No values files found"
    echo ""
    print_yellow "💡 Make sure you have created values-${ENVIRONMENT}.yaml"
    exit 1
fi

print_blue "Using values file: values-${ENVIRONMENT}.yaml"
echo ""

# Install or upgrade using single release name
echo "Installing/upgrading Helm release..."
if helm upgrade --install dota2-meta-lab . \
  --namespace data \
  --create-namespace \
  --values values-${ENVIRONMENT}.yaml \
  --set image.tag=${IMAGE_TAG} \
  --timeout 15m; then
    print_green "✅ Helm deployment successful"
else
    print_red "❌ Helm deployment failed"
    echo ""
    print_yellow "Troubleshooting tips:"
    echo "  1. Check if values-${ENVIRONMENT}.yaml is valid"
    echo "  2. Run: helm lint . -f values-${ENVIRONMENT}.yaml"
    echo "  3. Check logs: kubectl logs -n data -l app=dota2-api"
    exit 1
fi
echo ""

# ========================================
# ⏳ Step 5: Wait for pods
# ========================================
print_blue "⏳ Step 5: Waiting for pods to be ready..."
print_yellow "This may take a few minutes..."
echo ""

# Wait for any pods to appear first
echo "Waiting for pods to be created..."
sleep 10

# Check what pods exist
echo "Current pods in data namespace:"
kubectl get pods -n data 2>/dev/null || print_yellow "No pods found yet"
echo ""

# Try to wait for common pods
echo "Waiting for MongoDB..."
if kubectl wait --for=condition=ready pod -l app=mongodb -n data --timeout=180s 2>/dev/null; then
    print_green "✅ MongoDB ready"
else
    print_yellow "⚠️  MongoDB pods not found or not ready yet"
    kubectl get pods -n data -l app=mongodb 2>/dev/null || echo "No MongoDB pods"
fi
echo ""

echo "Waiting for Redis..."
if kubectl wait --for=condition=ready pod -l app=redis -n data --timeout=120s 2>/dev/null; then
    print_green "✅ Redis ready"
else
    print_yellow "⚠️  Redis pods not found or not ready yet"
    kubectl get pods -n data -l app=redis 2>/dev/null || echo "No Redis pods"
fi
echo ""

echo "Checking ML Pipeline namespace..."
if kubectl get namespace ml-pipeline &> /dev/null; then
    echo "Waiting for ML API..."
    if kubectl wait --for=condition=ready pod -l app=ml-api -n ml-pipeline --timeout=120s 2>/dev/null; then
        print_green "✅ ML API ready"
    else
        print_yellow "⚠️  ML API pods not found or not ready yet"
        kubectl get pods -n ml-pipeline -l app=ml-api 2>/dev/null || echo "No ML API pods"
    fi
else
    print_yellow "⚠️  ml-pipeline namespace not found (may not be needed for this environment)"
fi
echo ""

print_green "✅ Pod readiness check complete"
echo ""

# ========================================
# 📊 Step 6: Show deployment status
# ========================================
print_blue "📊 Deployment Status:"
echo ""
echo "=========================================="
echo "Helm Releases:"
echo "=========================================="
helm list -A
echo ""
echo "=========================================="
echo "Pods in data namespace:"
echo "=========================================="
kubectl get pods -n data -o wide 2>/dev/null || echo "No pods in data namespace"
echo ""
echo "=========================================="
echo "Services in data namespace:"
echo "=========================================="
kubectl get svc -n data 2>/dev/null || echo "No services in data namespace"
echo ""

# Show ml-pipeline if it exists
if kubectl get namespace ml-pipeline &> /dev/null; then
    echo "=========================================="
    echo "Pods in ml-pipeline namespace:"
    echo "=========================================="
    kubectl get pods -n ml-pipeline -o wide 2>/dev/null || echo "No pods in ml-pipeline namespace"
    echo ""
fi

# ========================================
# 🎉 Success
# ========================================
echo ""
print_green "=========================================="
print_green "🎉 Deployment Complete!"
print_green "=========================================="
echo ""
echo "Environment: $ENVIRONMENT"
echo "Image Tag: $IMAGE_TAG"
echo "Namespace: data"
echo ""
echo "=========================================="
echo "📝 Useful Commands:"
echo "=========================================="
echo ""
echo "Check pod status:"
echo "  kubectl get pods -n data"
echo ""
echo "View logs:"
echo "  kubectl logs -n data -l app.kubernetes.io/instance=dota2-meta-lab --tail=50"
echo ""
echo "Describe failing pods:"
echo "  kubectl describe pods -n data"
echo ""
echo "Check Helm release:"
echo "  helm list -n data"
echo "  helm status dota2-meta-lab -n data"
echo ""
echo "Port forward services:"
echo "  kubectl port-forward -n data svc/ml-api 8080:80"
echo ""
echo "Upgrade deployment:"
echo "  helm upgrade dota2-meta-lab . -f values-${ENVIRONMENT}.yaml --set image.tag=NEW_TAG -n data"
echo ""
echo "Rollback deployment:"
echo "  helm rollback dota2-meta-lab -n data"
echo ""
echo "Uninstall:"
echo "  helm uninstall dota2-meta-lab -n data"
echo ""