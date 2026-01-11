#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}🔐 Jenkins Secrets Setup${NC}"
echo -e "${BLUE}================================${NC}"

NAMESPACE="jenkins"
DOCKER_REGISTRY="docker.io"
DOCKER_IMAGE_PREFIX="rinavillaruz"

echo ""
echo -e "${YELLOW}Please provide the following credentials:${NC}"
echo ""

# Slack Webhook URL
read -p "Enter Slack Webhook URL: " SLACK_WEBHOOK
if [ -z "$SLACK_WEBHOOK" ]; then
    echo -e "${RED}❌ Slack webhook URL cannot be empty${NC}"
    exit 1
fi

# Docker Hub credentials (optional)
read -p "Enter Docker Hub username (default: $DOCKER_IMAGE_PREFIX): " DOCKERHUB_USERNAME
DOCKERHUB_USERNAME=${DOCKERHUB_USERNAME:-$DOCKER_IMAGE_PREFIX}

read -sp "Enter Docker Hub password/token (press Enter to skip): " DOCKERHUB_PASSWORD
echo ""

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}📦 Creating Kubernetes secrets${NC}"
echo -e "${BLUE}================================${NC}"

# Create namespace if doesn't exist
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "Creating namespace: $NAMESPACE"
    kubectl create namespace $NAMESPACE
else
    echo "✓ Namespace $NAMESPACE exists"
fi

# Delete existing secrets (for updates)
echo "Cleaning up old secrets..."
kubectl delete secret jenkins-docker-creds -n $NAMESPACE --ignore-not-found=true
kubectl delete secret jenkins-slack-webhook -n $NAMESPACE --ignore-not-found=true
kubectl delete secret jenkins-dockerhub-auth -n $NAMESPACE --ignore-not-found=true

# Create Docker registry credentials
echo "Creating jenkins-docker-creds secret..."
kubectl create secret generic jenkins-docker-creds \
  --from-literal=registry-url="$DOCKER_REGISTRY" \
  --from-literal=image-prefix="$DOCKER_IMAGE_PREFIX" \
  -n $NAMESPACE

echo -e "${GREEN}✓ jenkins-docker-creds created${NC}"

# Create Slack webhook secret
echo "Creating jenkins-slack-webhook secret..."
kubectl create secret generic jenkins-slack-webhook \
  --from-literal=webhook-url="$SLACK_WEBHOOK" \
  -n $NAMESPACE

echo -e "${GREEN}✓ jenkins-slack-webhook created${NC}"

# Create Docker Hub authentication secret (if password provided)
if [ -n "$DOCKERHUB_PASSWORD" ]; then
    echo "Creating jenkins-dockerhub-auth secret..."
    kubectl create secret generic jenkins-dockerhub-auth \
      --from-literal=username="$DOCKERHUB_USERNAME" \
      --from-literal=password="$DOCKERHUB_PASSWORD" \
      -n $NAMESPACE
    echo -e "${GREEN}✓ jenkins-dockerhub-auth created${NC}"
else
    echo -e "${YELLOW}⚠️  Skipping jenkins-dockerhub-auth (no password provided)${NC}"
fi

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}✅ All secrets created!${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo "Secrets in namespace $NAMESPACE:"
kubectl get secrets -n $NAMESPACE | grep jenkins-

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo -e "${BLUE}================================${NC}"
echo "1. kubectl apply -f jenkins-k8s/base/06-deployment.yaml"
echo "2. kubectl rollout restart deployment/jenkins -n jenkins"
echo "3. kubectl wait --for=condition=Ready pod -l app=jenkins -n jenkins --timeout=300s"
echo ""
echo -e "${GREEN}🎉 Done!${NC}"