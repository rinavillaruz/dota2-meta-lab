#!/bin/bash

set -e  # Exit on any error

echo "🚀 Deploying Dota2 ML Platform to Kubernetes..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 0: Load environment variables from .env
echo -e "${BLUE}🔐 Step 0: Loading environment variables...${NC}"
if [ ! -f ../.env ]; then
    echo -e "${RED}❌ Error: .env file not found in root directory!${NC}"
    echo "Please create a .env file with:"
    echo "  MONGODB_USERNAME=your_username"
    echo "  MONGODB_PASSWORD=your_password"
    exit 1
fi

# Load .env variables
export $(cat ../.env | grep -v '^#' | xargs)

# Verify required variables are set
if [ -z "$MONGODB_USERNAME" ] || [ -z "$MONGODB_PASSWORD" ]; then
    echo -e "${RED}❌ Error: MONGODB_USERNAME or MONGODB_PASSWORD not set in .env${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Environment variables loaded${NC}\n"

# Step 1: Check if cluster exists, if not create it
echo -e "${BLUE}🔍 Step 1: Checking for existing cluster...${NC}"
if kind get clusters | grep -q "ml-cluster"; then
    echo -e "${YELLOW}⚠️  Cluster 'ml-cluster' already exists. Skipping creation.${NC}\n"
else
    
    echo -e "${BLUE}🏗️  Creating Directories control planes, ml-training, mongodb, redis and models...${NC}"
    mkdir -p ../data/{control-plane-{1..3},ml-training,mongodb,redis} ../models

    echo -e "${BLUE}🏗️  Creating Kind cluster...${NC}"
    kind create cluster --config ../k8s/ha/kind-ha-cluster.yaml --name ml-cluster
    echo -e "${GREEN}✅ Cluster created${NC}\n"
    
    # Wait for cluster to be fully ready
    echo "⏳ Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=180s
    echo -e "${GREEN}✅ Cluster is ready${NC}\n"
fi

# Step 2: Create namespaces
echo -e "${BLUE}📦 Step 2: Creating namespaces...${NC}"
kubectl apply -f ../k8s/namespaces/namespaces.yaml
echo -e "${GREEN}✅ Namespaces created${NC}\n"

# Wait a bit for namespaces to be ready
sleep 2

# Step 3: Create storage resources
echo -e "${BLUE}💾 Step 3: Setting up storage...${NC}"

# Check available StorageClasses
echo "Available StorageClasses:"
kubectl get storageclass

# Apply storage class if exists
if [ -f "../k8s/storage/storage-class.yaml" ]; then
    kubectl apply -f ../k8s/storage/storage-class.yaml
fi

# Check if fast-storage exists, if not warn user
if ! kubectl get storageclass fast-storage &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: 'fast-storage' StorageClass not found${NC}"
    echo -e "${YELLOW}   Make sure your PVCs use 'standard' StorageClass${NC}"
fi

kubectl apply -f ../k8s/storage/pvc-ml-training.yaml
kubectl apply -f ../k8s/storage/pvc-models.yaml
echo -e "${GREEN}✅ Storage configured${NC}\n"

# Step 4: Deploy MongoDB
echo -e "${BLUE}🍃 Step 4: Deploying MongoDB...${NC}"

# Generate and apply MongoDB secret with environment variables
echo "Generating MongoDB secret from environment variables..."
envsubst < ../k8s/data/mongodb/mongodb-secret.yaml | kubectl apply -f -

# Verify secret was created
if kubectl get secret mongodb-secret -n data &> /dev/null; then
    echo -e "${GREEN}✅ MongoDB secret created successfully${NC}"
else
    echo -e "${RED}❌ Failed to create MongoDB secret${NC}"
    exit 1
fi

# Then deploy service and statefulset
kubectl apply -f ../k8s/data/mongodb/mongodb-service.yaml
kubectl apply -f ../k8s/data/mongodb/mongodb-statefulset.yaml
echo -e "${GREEN}✅ MongoDB deployed${NC}\n"

# Step 5: Deploy Redis
echo -e "${BLUE}🔴 Step 5: Deploying Redis...${NC}"
kubectl apply -f ../k8s/data/redis/redis-deployment.yaml
kubectl apply -f ../k8s/data/redis/redis-service.yaml
echo -e "${GREEN}✅ Redis deployed${NC}\n"

# Wait for Redis to be ready
echo "⏳ Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app=redis -n data --timeout=120s
echo -e "${GREEN}✅ Redis is ready${NC}\n"

# Step 6: Install Ingress Controller
echo -e "${BLUE}🌐 Step 6: Installing Ingress Controller...${NC}"

# Check if ingress-nginx namespace exists
if kubectl get namespace ingress-nginx &> /dev/null; then
    echo -e "${YELLOW}⚠️  Ingress controller already exists, skipping installation${NC}\n"
else
    echo "Installing ingress-nginx..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/kind/deploy.yaml
    echo -e "${GREEN}✅ Ingress controller installed${NC}\n"
fi

# Wait for ingress controller to be ready
echo "⏳ Waiting for Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s || {
    echo -e "${YELLOW}⚠️  Ingress controller not ready yet, but continuing...${NC}"
}
echo -e "${GREEN}✅ Ingress controller ready${NC}\n"

# Step 7: Deploy ML API
echo -e "${BLUE}🤖 Step 7: Deploying ML API...${NC}"
kubectl apply -f ../k8s/ml-pipeline/ml-api-service.yaml
kubectl apply -f ../k8s/ml-pipeline/ml-api-deployment.yaml
echo -e "${GREEN}✅ ML API deployed${NC}\n"

# Wait for ML API to be ready
echo "⏳ Waiting for ML API pods to be ready..."
kubectl wait --for=condition=ready pod -l app=ml-api -n ml-pipeline --timeout=120s || {
    echo -e "${RED}❌ ML API pods failed to start${NC}"
    kubectl get pods -n ml-pipeline
    kubectl describe pods -n ml-pipeline -l app=ml-api
    exit 1
}
echo -e "${GREEN}✅ ML API is ready${NC}\n"

# Step 8: Show deployment status
echo -e "${BLUE}📊 Deployment Status:${NC}"
echo ""
echo "Nodes:"
kubectl get nodes
echo ""
echo "Namespaces:"
kubectl get namespaces | grep -E 'NAME|data|ml-pipeline|ingress-nginx'
echo ""
echo "Storage:"
kubectl get pvc -n ml-pipeline
echo ""
echo "Data Services:"
kubectl get pods -n data
echo ""
echo "ML Pipeline:"
kubectl get pods -n ml-pipeline
echo ""
echo "Services:"
kubectl get svc -n ml-pipeline
kubectl get svc -n data
echo ""

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo "📝 Next Steps:"
echo ""
echo "To test the ML API health check:"
echo "  kubectl exec -n ml-pipeline deployment/ml-api -- curl -s http://localhost:8000/health"
echo ""
echo "To test database connectivity:"
echo "  kubectl exec -n ml-pipeline deployment/ml-api -- curl -s http://localhost:8000/health/ready"
echo ""
echo "To access ML API via port-forward:"
echo "  kubectl port-forward -n ml-pipeline svc/ml-api 8000:8000"
echo "  curl http://localhost:8000/health"
echo ""
echo "To check logs:"
echo "  kubectl logs -n ml-pipeline -l app=ml-api --tail=50"