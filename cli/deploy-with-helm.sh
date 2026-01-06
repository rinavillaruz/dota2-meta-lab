#!/bin/bash

set -e

echo "🚀 Deploying Dota2 Meta Lab Platform with Helm..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Determine environment (default to dev)
ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}

echo -e "${BLUE}🎯 Deploying to environment: ${ENVIRONMENT}${NC}\n"
echo -e "${BLUE}📦 Image tag: ${IMAGE_TAG}${NC}\n"

# Detect if running in Jenkins
if [ -n "$JENKINS_HOME" ]; then
    echo -e "${BLUE}🤖 Running in Jenkins CI/CD${NC}"
    IN_JENKINS=true
    
    # Skip Kind cluster creation
    SKIP_KIND=true
    
    # Skip metrics server (already installed)
    SKIP_METRICS=true
    
    # Skip interactive prompts
    export DEBIAN_FRONTEND=noninteractive
else
    echo -e "${BLUE}💻 Running locally${NC}"
    IN_JENKINS=false
    SKIP_KIND=false
    SKIP_METRICS=false
fi
echo ""

# Step 0: Load environment variables from .env
echo -e "${BLUE}🔐 Step 0: Loading environment variables...${NC}"
if [ "$IN_JENKINS" = true ]; then
    # In Jenkins: Use Kubernetes secrets
    echo "Loading credentials from Kubernetes secrets..."
    export MONGODB_USERNAME=$(cat /run/secrets/mongodb/username 2>/dev/null || echo "admin")
    export MONGODB_PASSWORD=$(cat /run/secrets/mongodb/password 2>/dev/null || echo "password")
else
    # Locally: Use .env file
    if [ ! -f ../.env ]; then
        echo -e "${RED}❌ Error: .env file not found in root directory!${NC}"
        echo "Please create a .env file with:"
        echo "  MONGODB_USERNAME=your_username"
        echo "  MONGODB_PASSWORD=your_password"
        exit 1
    fi
    
    # Load .env variables
    export $(cat ../.env | grep -v '^#' | xargs)
fi

# Verify required variables are set
if [ -z "$MONGODB_USERNAME" ] || [ -z "$MONGODB_PASSWORD" ]; then
    echo -e "${RED}❌ Error: MONGODB_USERNAME or MONGODB_PASSWORD not set in .env${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Environment variables loaded${NC}\n"

# Step 1: Check if cluster exists, if not create it
if [ "$SKIP_KIND" = false ]; then
    echo -e "${BLUE}🔍 Step 1: Checking for existing cluster...${NC}"
    if kind get clusters | grep -q "ml-cluster"; then
        echo -e "${YELLOW}⚠️  Cluster 'ml-cluster' already exists. Skipping creation.${NC}\n"
    else
        echo -e "${BLUE}🏗️  Creating directories...${NC}"
        mkdir -p ../data/{control-plane-{1..3},ml-training,mongodb,redis} ../models
        
        echo -e "${BLUE}🏗️  Creating Kind cluster...${NC}"
        kind create cluster --config ../k8s/ha/kind-ha-cluster.yaml --name ml-cluster
        echo -e "${GREEN}✅ Cluster created${NC}\n"
        
        echo "⏳ Waiting for cluster to be ready..."
        kubectl wait --for=condition=Ready nodes --all --timeout=180s
        echo -e "${GREEN}✅ Cluster is ready${NC}\n"
    fi
else
    echo -e "${BLUE}🔍 Step 1: Using existing Kubernetes cluster${NC}"
    echo "Current context: $(kubectl config current-context)"
    echo -e "${GREEN}✅ Cluster ready${NC}\n"
fi

# Step 1.5: Install Metrics Server
if [ "$SKIP_METRICS" = false ]; then
    echo -e "${BLUE}📊 Step 1.5: Installing Metrics Server...${NC}"

    # Verify kubectl can connect to the cluster
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to cluster. Please check your kubectl context.${NC}"
        echo "Current context: $(kubectl config current-context 2>/dev/null || echo 'none')"
        echo "Run: kubectl config use-context kind-ml-cluster"
        exit 1
    fi

    if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        echo -e "${YELLOW}⚠️  Metrics server already installed${NC}\n"
    else
        echo "Installing metrics server..."
        kubectl apply --validate=false -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        
        # Wait a moment for the deployment to be created
        sleep 5
        
        # Patch for Kind (allow insecure TLS)
        echo "Patching metrics server for Kind cluster..."
        kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/args/-",
            "value": "--kubelet-insecure-tls"
        }
        ]'
        
        echo -e "${GREEN}✅ Metrics server installed${NC}"
        echo "⏳ Waiting for metrics server to be ready..."
        kubectl wait --for=condition=available --timeout=120s deployment/metrics-server -n kube-system || {
            echo -e "${YELLOW}⚠️  Metrics server still starting (this is OK, it will be ready soon)${NC}"
        }
        echo ""
    fi
else
    echo -e "${BLUE}📊 Step 1.5: Skipping metrics server (already installed)${NC}\n"
fi

# Step 2: Create namespaces
echo -e "${BLUE}📦 Step 2: Creating namespaces...${NC}"
kubectl create namespace data --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ml-pipeline --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✅ Namespaces created${NC}\n"

sleep 2

# Step 3: Create secrets
echo -e "${BLUE}🔐 Step 3: Creating secrets...${NC}"
kubectl create secret generic mongodb-secret \
  --from-literal=username="$MONGODB_USERNAME" \
  --from-literal=password="$MONGODB_PASSWORD" \
  --namespace=data \
  --dry-run=client -o yaml | kubectl apply -f -

if kubectl get secret mongodb-secret -n data &> /dev/null; then
    echo -e "${GREEN}✅ MongoDB secret created successfully${NC}\n"
else
    echo -e "${RED}❌ Failed to create MongoDB secret${NC}"
    exit 1
fi

# Step 4: Deploy with Helm
echo -e "${BLUE}🎡 Step 4: Deploying with Helm...${NC}"

# Validate Helm chart first
echo "Validating Helm chart..."
if helm lint ../deploy/helm; then
    echo -e "${GREEN}✅ Helm chart validation passed${NC}\n"
else
    echo -e "${RED}❌ Helm chart validation failed${NC}"
    exit 1
fi

if helm list -n data | grep -q "dota2-meta-lab-${ENVIRONMENT}"; then
    echo -e "${YELLOW}⚠️  Helm release already exists. Upgrading...${NC}"
    helm upgrade dota2-meta-lab-${ENVIRONMENT} ../deploy/helm \
      -f ../deploy/helm/values.yaml \
      -f ../deploy/helm/values-${ENVIRONMENT}.yaml \
      --set image.tag=${IMAGE_TAG} \
      --namespace data
else
    echo "Installing Helm chart..."
    helm install dota2-meta-lab-${ENVIRONMENT} ../deploy/helm \
      -f ../deploy/helm/values.yaml \
      -f ../deploy/helm/values-${ENVIRONMENT}.yaml \
      --set image.tag=${IMAGE_TAG} \
      --namespace data
fi

echo -e "${GREEN}✅ Helm deployment complete${NC}\n"

# Step 5: Wait for pods to be ready
echo -e "${BLUE}⏳ Step 5: Waiting for pods to be ready...${NC}"

echo "Waiting for MongoDB..."
kubectl wait --for=condition=ready pod -l app=mongodb -n data --timeout=180s || {
    echo -e "${YELLOW}⚠️  MongoDB not ready yet, checking status...${NC}"
    kubectl get pods -n data -l app=mongodb
}

echo "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app=redis -n data --timeout=120s || {
    echo -e "${YELLOW}⚠️  Redis not ready yet, checking status...${NC}"
    kubectl get pods -n data -l app=redis
}

echo "Waiting for ML API..."
kubectl wait --for=condition=ready pod -l app=ml-api -n ml-pipeline --timeout=120s || {
    echo -e "${YELLOW}⚠️  ML API not ready yet, checking status...${NC}"
    kubectl get pods -n ml-pipeline -l app=ml-api
}

echo -e "${GREEN}✅ Pod readiness check complete${NC}\n"

# Step 6: Show deployment status
echo -e "${BLUE}📊 Deployment Status:${NC}"
echo ""
echo "=========================================="
echo "Helm Releases:"
echo "=========================================="
helm list -A
echo ""
echo "=========================================="
echo "Nodes:"
echo "=========================================="
kubectl get nodes -o wide
echo ""
echo "=========================================="
echo "Namespaces:"
echo "=========================================="
kubectl get namespaces | grep -E 'NAME|data|ml-pipeline'
echo ""
echo "=========================================="
echo "Storage (PVCs):"
echo "=========================================="
kubectl get pvc -A
echo ""
echo "=========================================="
echo "Data Services (namespace: data):"
echo "=========================================="
kubectl get pods -n data -o wide
echo ""
echo "=========================================="
echo "ML Pipeline (namespace: ml-pipeline):"
echo "=========================================="
kubectl get pods -n ml-pipeline -o wide
echo ""
echo "=========================================="
echo "Services:"
echo "=========================================="
echo "Data namespace:"
kubectl get svc -n data
echo ""
echo "ML Pipeline namespace:"
kubectl get svc -n ml-pipeline
echo ""

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo "=========================================="
echo "📝 Access Your Services via Port-Forward:"
echo "=========================================="
echo ""
echo "ML API:"
echo "  kubectl port-forward -n ml-pipeline svc/ml-api 8080:80"
echo "  curl http://localhost:8080"
echo ""
echo "MongoDB:"
echo "  kubectl port-forward -n data svc/mongodb 27017:27017"
echo "  mongosh mongodb://localhost:27017"
echo ""
echo "Redis:"
echo "  kubectl port-forward -n data svc/redis 6379:6379"
echo "  redis-cli -h localhost -p 6379"
echo ""
echo "Metric Server:"
echo "  kubectl port-forward -n kube-system svc/metrics-server 4443:443"
echo "  kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq (visit in new terminal)"
echo "  https://localhost:4443/apis/metrics.k8s.io/v1beta1/nodes (or open in browser)"
echo "  kubectl logs -n kube-system deploy/metrics-server (verify logs)"
echo ""
echo "=========================================="
echo "📝 Useful Commands:"
echo "=========================================="
echo ""
echo "Check logs:"
echo "  kubectl logs -n data -l app=mongodb --tail=50"
echo "  kubectl logs -n data -l app=redis --tail=50"
echo "  kubectl logs -n ml-pipeline -l app=ml-api --tail=50"
echo ""
echo "Upgrade deployment:"
echo "  helm upgrade dota2-meta-lab-${ENVIRONMENT} ../deploy/helm -f ../deploy/helm/values-${ENVIRONMENT}.yaml -n data"
echo ""
echo "Rollback:"
echo "  helm rollback dota2-meta-lab-${ENVIRONMENT} -n data"
echo ""
echo "Check status:"
echo "  cd scripts && ./cluster-status.sh"