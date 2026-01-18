#!/bin/bash

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}🚀 Starting Local Kubernetes Dev Environment${NC}"
echo -e "${BLUE}================================${NC}"
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
CLUSTER_NAME="${CLUSTER_NAME:-dota2-dev}"
MONGODB_USERNAME="${MONGODB_USERNAME:-admin}"
MONGODB_PASSWORD="${MONGODB_PASSWORD:-changeme123}"

# Debug mode
if [ "${DEBUG:-false}" = "true" ]; then
    echo "🐛 Debug - Configuration:"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  CLUSTER_NAME: $CLUSTER_NAME"
    echo ""
fi

cd "$PROJECT_ROOT"

# -----------------------------------------------------------------------------
# Step 1: Check if Kind cluster exists
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1: Checking Kind cluster...${NC}"

if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    echo -e "${GREEN}✅ Kind cluster '$CLUSTER_NAME' exists${NC}"
else
    echo -e "${YELLOW}⚠️  Kind cluster not found${NC}"
    read -p "Create Kind cluster now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if [ ! -f "k8s/ha/kind-ha-cluster.yaml" ]; then
            echo -e "${RED}❌ k8s/ha/kind-ha-cluster.yaml not found${NC}"
            echo "Please create your Kind cluster config first"
            exit 1
        fi
        
        echo "Creating Kind cluster..."
        kind create cluster --config k8s/ha/kind-ha-cluster.yaml --name "$CLUSTER_NAME"
        echo -e "${GREEN}✅ Cluster created${NC}"
    else
        echo -e "${RED}❌ Cannot continue without cluster${NC}"
        exit 1
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Step 1.5: Clean up orphaned resources (optional)
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1.5: Check for existing deployment...${NC}"

# Check if anything exists in data namespace
if kubectl get all,pvc -n data 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}⚠️  Found existing resources in data namespace${NC}"
    kubectl get all,pvc -n data
    echo ""
    read -p "Delete ALL resources and start fresh? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing Helm release..."
        helm uninstall dota2-meta-lab -n data 2>/dev/null || true
        
        echo "Deleting Helm secrets..."
        kubectl delete secret -n data -l owner=helm --force --grace-period=0 2>/dev/null || true
        
        echo "Removing finalizers from all resources..."
        kubectl get all,pvc,secrets,configmaps -n data -o name 2>/dev/null | while read resource; do
            kubectl patch $resource -n data -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done
        
        echo "Deleting all resources..."
        kubectl delete all,pvc,secrets,configmaps,serviceaccounts --all -n data --force --grace-period=0 2>/dev/null || true
        
        echo "Waiting for cleanup..."
        sleep 5
        
        echo -e "${GREEN}✅ Cleanup complete${NC}"
        kubectl get all,pvc -n data 2>/dev/null || echo "Namespace is clean"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Step 1.6: Ensure storage provisioner exists
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 1.6: Checking storage provisioner...${NC}"

if ! kubectl get deployment local-path-provisioner -n local-path-storage &>/dev/null; then
    echo "Installing local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
    
    echo "Waiting for provisioner to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=local-path-provisioner \
        -n local-path-storage \
        --timeout=120s
    
    echo -e "${GREEN}✅ Storage provisioner installed${NC}"
else
    echo -e "${GREEN}✅ Storage provisioner already exists${NC}"
fi

# Ensure StorageClass exists and is named 'standard' for compatibility
if ! kubectl get storageclass standard &>/dev/null; then
    if kubectl get storageclass local-path &>/dev/null; then
        echo "Creating 'standard' StorageClass alias..."
        kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
        kubectl get storageclass local-path -o yaml | \
            sed 's/name: local-path/name: standard/' | \
            kubectl apply -f -
    fi
    echo -e "${GREEN}✅ StorageClass 'standard' available${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 2: Create namespaces
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2: Creating namespaces...${NC}"

kubectl create namespace data --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev-tools --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✅ Namespaces created${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 2.5: Create required secrets
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 2.5: Creating secrets...${NC}"

# Create MongoDB secret if it doesn't exist
if ! kubectl get secret mongodb-secret -n data &>/dev/null; then
    echo "Creating MongoDB secret..."
    kubectl create secret generic mongodb-secret -n data \
        --from-literal=username="$MONGODB_USERNAME" \
        --from-literal=password="$MONGODB_PASSWORD"
    echo -e "${GREEN}✅ MongoDB secret created${NC}"
else
    echo -e "${GREEN}✅ MongoDB secret already exists${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 3: Build Docker images locally
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 3: Building Docker images...${NC}"

read -p "Build/rebuild Docker images? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Building images..."
    
    # Build all images using Dockerfile.dev
    echo "Building data-fetcher..."
    docker build -t rinavillaruz/dota2-fetcher:latest \
        --target data-fetcher \
        -f build/Dockerfile.dev . 2>&1 | grep -E "^Step|Successfully|^#"
    
    echo "Building trainer..."
    docker build -t rinavillaruz/dota2-trainer:latest \
        --target trainer \
        -f build/Dockerfile.dev . 2>&1 | grep -E "^Step|Successfully|^#"
    
    echo "Building API..."
    docker build -t rinavillaruz/dota2-api:latest \
        --target api \
        -f build/Dockerfile.dev . 2>&1 | grep -E "^Step|Successfully|^#"
    
    # Build Jupyter with dedicated Dockerfile
    echo "Building Jupyter (data science environment)..."
    docker build -t rinavillaruz/dota2-jupyter:latest \
        -f build/Dockerfile.jupyter . 2>&1 | grep -E "^Step|Successfully|^#"
    
    # Load images into Kind cluster
    echo ""
    echo "Loading images into Kind cluster..."
    kind load docker-image rinavillaruz/dota2-fetcher:latest --name "$CLUSTER_NAME"
    kind load docker-image rinavillaruz/dota2-trainer:latest --name "$CLUSTER_NAME"
    kind load docker-image rinavillaruz/dota2-api:latest --name "$CLUSTER_NAME"
    kind load docker-image rinavillaruz/dota2-jupyter:latest --name "$CLUSTER_NAME"
    
    echo -e "${GREEN}✅ Images built and loaded${NC}"
else
    echo "Skipping image build"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 4: Deploy with Helm (using values-dev.yaml)
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 4: Deploying with Helm...${NC}"

if [ ! -f "deploy/helm/values-dev.yaml" ]; then
    echo -e "${RED}❌ deploy/helm/values-dev.yaml not found${NC}"
    exit 1
fi

helm upgrade --install dota2-meta-lab ./deploy/helm \
    -f ./deploy/helm/values-dev.yaml \
    -n data \
    --create-namespace \
    --timeout 5m

echo -e "${GREEN}✅ Helm deployment complete${NC}"
echo ""

# Give resources a moment to be created
sleep 3

# Show current status
echo "Deployment status:"
kubectl get all,pvc -n data
echo ""

# -----------------------------------------------------------------------------
# Step 5: Deploy Jupyter (optional dev tool)
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 5: Deploying Jupyter (optional)...${NC}"

read -p "Deploy Jupyter notebook? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    
    # Create Jupyter deployment
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jupyter
  namespace: dev-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jupyter
  template:
    metadata:
      labels:
        app: jupyter
    spec:
      containers:
      - name: jupyter
        image: rinavillaruz/dota2-jupyter:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8888
        env:
        - name: MONGODB_URI
          value: "mongodb://mongodb.data.svc.cluster.local:27017/local_dota2_meta_lab"
        - name: REDIS_HOST
          value: "redis.data.svc.cluster.local"
        - name: REDIS_PORT
          value: "6379"
        volumeMounts:
        - name: notebooks
          mountPath: /workspace/notebooks
        - name: src
          mountPath: /workspace/src
        - name: data
          mountPath: /workspace/data
        - name: models
          mountPath: /workspace/models
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
          limits:
            memory: 1Gi
            cpu: 500m
      volumes:
      - name: notebooks
        hostPath:
          path: ${PROJECT_ROOT}/notebooks
          type: DirectoryOrCreate
      - name: src
        hostPath:
          path: ${PROJECT_ROOT}/src
          type: DirectoryOrCreate
      - name: data
        hostPath:
          path: ${PROJECT_ROOT}/data
          type: DirectoryOrCreate
      - name: models
        hostPath:
          path: ${PROJECT_ROOT}/models
          type: DirectoryOrCreate
---
apiVersion: v1
kind: Service
metadata:
  name: jupyter
  namespace: dev-tools
spec:
  type: NodePort
  selector:
    app: jupyter
  ports:
  - port: 8888
    targetPort: 8888
    nodePort: 30888
EOF
    
    echo -e "${GREEN}✅ Jupyter deployed${NC}"
else
    echo "Skipping Jupyter deployment"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 6: Wait for pods
# -----------------------------------------------------------------------------
echo -e "${BLUE}Step 6: Waiting for pods to be ready...${NC}"

echo "Waiting for MongoDB..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mongodb -n data --timeout=300s 2>/dev/null || echo "MongoDB still starting..."

echo "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n data --timeout=300s 2>/dev/null || echo "Redis still starting..."

if kubectl get deployment dota2-api -n data &>/dev/null; then
    echo "Waiting for API..."
    kubectl wait --for=condition=ready pod -l app=dota2-api -n data --timeout=300s 2>/dev/null || echo "API still starting..."
fi

if kubectl get deployment jupyter -n dev-tools &>/dev/null; then
    echo "Waiting for Jupyter..."
    kubectl wait --for=condition=ready pod -l app=jupyter -n dev-tools --timeout=300s 2>/dev/null || echo "Jupyter still starting..."
fi

echo ""

# -----------------------------------------------------------------------------
# Step 7: Show status
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}✅ Local Kubernetes environment is ready!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "${BLUE}Service URLs:${NC}"
echo ""

# Check if API service exists and get NodePort
if kubectl get svc -n data 2>/dev/null | grep -q api; then
    API_PORT=$(kubectl get svc dota2-api -n data -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -n "$API_PORT" ]; then
        echo -e "🌐 API:      ${YELLOW}http://localhost:${API_PORT}${NC}"
    else
        echo -e "🌐 API:      ${YELLOW}http://localhost:8000 (use port-forward)${NC}"
    fi
fi

# Check if Jupyter service exists
if kubectl get svc jupyter -n dev-tools &>/dev/null; then
    echo -e "📊 Jupyter:  ${YELLOW}http://localhost:30888${NC}"
    echo -e "   ${BLUE}(No password required - configured for local dev)${NC}"
fi

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Kubernetes Resources:${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

echo "Pods in 'data' namespace:"
kubectl get pods -n data
echo ""

if kubectl get pods -n dev-tools &>/dev/null 2>&1; then
    echo "Pods in 'dev-tools' namespace:"
    kubectl get pods -n dev-tools
    echo ""
fi

echo "Services in 'data' namespace:"
kubectl get svc -n data
echo ""

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo "View all pods:"
echo "  kubectl get pods -A"
echo ""
echo "View logs:"
echo "  kubectl logs -f -n data deployment/dota2-api"
if kubectl get deployment jupyter -n dev-tools &>/dev/null; then
    echo "  kubectl logs -f -n dev-tools deployment/jupyter"
fi
echo ""
echo "Shell into container:"
echo "  kubectl exec -it -n data deployment/dota2-api -- bash"
if kubectl get deployment jupyter -n dev-tools &>/dev/null; then
    echo "  kubectl exec -it -n dev-tools deployment/jupyter -- bash"
fi
echo ""
echo "Restart deployment:"
echo "  kubectl rollout restart deployment/dota2-api -n data"
echo ""
echo "Check MongoDB:"
kubectl get pod -n data -l app.kubernetes.io/name=mongodb -o name 2>/dev/null | head -1 | xargs -I {} echo "  kubectl exec -it {} -n data -- mongosh"
echo ""
echo "Port forward (for ClusterIP services):"
echo "  kubectl port-forward -n data svc/dota2-api 8000:8000"
if kubectl get svc jupyter -n dev-tools &>/dev/null; then
    echo "  kubectl port-forward -n dev-tools svc/jupyter 8888:8888"
fi
echo ""
echo "Clean up:"
echo "  ./cli/stop-dev-k8s.sh"
echo ""
echo -e "${GREEN}🎉 Happy developing in Kubernetes!${NC}"
echo ""