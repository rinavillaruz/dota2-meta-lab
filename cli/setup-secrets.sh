#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}🔐 Secrets Setup for Dota2 Meta Lab${NC}"
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
JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-}"
MONGODB_USERNAME="${MONGODB_USERNAME:-admin}"
MONGODB_PASSWORD="${MONGODB_PASSWORD:-}"
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"
DOCKERHUB_EMAIL="${DOCKERHUB_EMAIL:-admin@example.com}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
DOTA2_API_KEY="${DOTA2_API_KEY:-}"

# Debug mode
if [ "${DEBUG:-false}" = "true" ]; then
    echo "🐛 Debug - Configuration:"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  JENKINS_NAMESPACE: $JENKINS_NAMESPACE"
    echo "  MONGODB_USERNAME: $MONGODB_USERNAME"
    echo "  GITHUB_USERNAME: $GITHUB_USERNAME"
    echo "  DOCKERHUB_USERNAME: $DOCKERHUB_USERNAME"
    echo ""
fi

# Parse environment argument
ENVIRONMENT=${1:-dev}
echo -e "${BLUE}Environment: ${YELLOW}${ENVIRONMENT}${NC}"
echo ""

# ========================================
# MongoDB Secrets (data namespace)
# ========================================
echo -e "${BLUE}📦 MongoDB Credentials${NC}"
echo ""

if [ -n "$JENKINS_HOME" ]; then
    # Running in Jenkins - use environment variables
    echo "Running in Jenkins - using environment variables"
    MONGODB_USERNAME=${MONGODB_USERNAME:-admin}
    MONGODB_PASSWORD=${MONGODB_PASSWORD:-password123}
else
    # Running locally - use .env or prompt
    if [ -z "$MONGODB_PASSWORD" ]; then
        read -p "MongoDB username (default: admin): " INPUT_USERNAME
        MONGODB_USERNAME=${INPUT_USERNAME:-admin}
        
        read -sp "MongoDB password (default: changeme123): " INPUT_PASSWORD
        echo ""
        MONGODB_PASSWORD=${INPUT_PASSWORD:-changeme123}
    else
        echo "Using MongoDB credentials from .env"
    fi
fi

# Create data namespace if doesn't exist
kubectl create namespace data --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

# Create MongoDB secret
if kubectl get secret mongodb-secret -n data &>/dev/null; then
    echo -e "${YELLOW}⚠️  mongodb-secret already exists in data namespace${NC}"
    read -p "Recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete secret mongodb-secret -n data
        kubectl create secret generic mongodb-secret -n data \
            --from-literal=username="$MONGODB_USERNAME" \
            --from-literal=password="$MONGODB_PASSWORD"
        echo -e "${GREEN}✓ mongodb-secret recreated in data namespace${NC}"
    else
        echo "Keeping existing secret"
    fi
else
    kubectl create secret generic mongodb-secret -n data \
        --from-literal=username="$MONGODB_USERNAME" \
        --from-literal=password="$MONGODB_PASSWORD"
    echo -e "${GREEN}✓ mongodb-secret created in data namespace${NC}"
fi

echo ""

# ========================================
# Jenkins Secrets (jenkins namespace)
# ========================================
if [ "$ENVIRONMENT" != "production" ]; then
    echo -e "${BLUE}🤖 Jenkins/CI Credentials${NC}"
    echo ""
    
    read -p "Setup Jenkins secrets? (Y/n): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        # Create jenkins namespace if doesn't exist
        kubectl create namespace "$JENKINS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
        echo -e "${GREEN}✓ Jenkins namespace created/verified${NC}"
        echo ""
        
        # ========================================
        # 1. Jenkins Admin Credentials
        # ========================================
        echo -e "${BLUE}1. Jenkins Admin Password${NC}"
        if [ -z "$JENKINS_ADMIN_PASSWORD" ]; then
            read -sp "Jenkins admin password (default: changeme): " INPUT_JENKINS_PASSWORD
            echo ""
            JENKINS_ADMIN_PASSWORD=${INPUT_JENKINS_PASSWORD:-changeme}
        else
            echo "Using Jenkins admin password from .env"
        fi
        
        kubectl create secret generic jenkins-admin-credentials \
            --from-literal=password="$JENKINS_ADMIN_PASSWORD" \
            -n "$JENKINS_NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo -e "${GREEN}✓ jenkins-admin-credentials created${NC}"
        echo ""
        
        # ========================================
        # 2. GitHub Credentials
        # ========================================
        echo -e "${BLUE}2. GitHub Credentials${NC}"
        if [ -z "$GITHUB_USERNAME" ]; then
            read -p "GitHub username (optional, press Enter to skip): " GITHUB_USERNAME
        fi
        
        if [ -z "$GITHUB_TOKEN" ] && [ -n "$GITHUB_USERNAME" ]; then
            read -sp "GitHub token (optional): " GITHUB_TOKEN
            echo ""
        fi
        
        if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_TOKEN" ]; then
            kubectl create secret generic github-credentials \
                --from-literal=username="$GITHUB_USERNAME" \
                --from-literal=token="$GITHUB_TOKEN" \
                -n "$JENKINS_NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
            echo -e "${GREEN}✓ github-credentials created${NC}"
        else
            echo -e "${YELLOW}⚠️  GitHub credentials not provided - skipping${NC}"
        fi
        echo ""
        
        # ========================================
        # 3. Docker Hub Credentials
        # ========================================
        echo -e "${BLUE}3. Docker Hub Credentials${NC}"
        if [ -z "$DOCKERHUB_USERNAME" ]; then
            read -p "Docker Hub username (default: rinavillaruz): " INPUT_DOCKERHUB_USERNAME
            DOCKERHUB_USERNAME=${INPUT_DOCKERHUB_USERNAME:-rinavillaruz}
        else
            echo "Using Docker Hub username from .env: $DOCKERHUB_USERNAME"
        fi
        
        if [ -z "$DOCKERHUB_TOKEN" ]; then
            read -sp "Docker Hub token (optional, press Enter to skip): " DOCKERHUB_TOKEN
            echo ""
        fi
        
        # Create dockerhub-credentials (for CLI/API use)
        if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
            kubectl create secret generic dockerhub-credentials \
                --from-literal=username="$DOCKERHUB_USERNAME" \
                --from-literal=token="$DOCKERHUB_TOKEN" \
                -n "$JENKINS_NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
            echo -e "${GREEN}✓ dockerhub-credentials created${NC}"
            
            # Create dockerhub-pull-secret (ImagePullSecret for pulling private images)
            kubectl create secret docker-registry dockerhub-pull-secret \
                --docker-server=https://index.docker.io/v1/ \
                --docker-username="$DOCKERHUB_USERNAME" \
                --docker-password="$DOCKERHUB_TOKEN" \
                --docker-email="$DOCKERHUB_EMAIL" \
                -n "$JENKINS_NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
            echo -e "${GREEN}✓ dockerhub-pull-secret created${NC}"
        else
            echo -e "${YELLOW}⚠️  Docker Hub credentials not provided - skipping${NC}"
        fi
        echo ""
        
        # ========================================
        # 4. Slack Webhook (Optional)
        # ========================================
        echo -e "${BLUE}4. Slack Webhook (Optional)${NC}"
        if [ -z "$SLACK_WEBHOOK" ]; then
            read -p "Slack Webhook URL (optional, press Enter to skip): " SLACK_WEBHOOK
        fi
        
        if [ -n "$SLACK_WEBHOOK" ]; then
            kubectl create secret generic jenkins-slack-webhook \
                --from-literal=webhook-url="$SLACK_WEBHOOK" \
                -n "$JENKINS_NAMESPACE" \
                --dry-run=client -o yaml | kubectl apply -f -
            echo -e "${GREEN}✓ jenkins-slack-webhook created${NC}"
        else
            echo -e "${YELLOW}⚠️  Slack webhook not provided - skipping${NC}"
        fi
        echo ""
    fi
fi

# ========================================
# API Keys & External Services (Optional)
# ========================================
echo -e "${BLUE}🔑 External API Keys (Optional)${NC}"
echo ""

read -p "Setup Dota2 API key? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -z "$DOTA2_API_KEY" ]; then
        read -p "Dota2 API Key: " DOTA2_API_KEY
    fi
    
    if [ -n "$DOTA2_API_KEY" ]; then
        kubectl create secret generic dota2-api-secret -n data \
            --from-literal=api-key="$DOTA2_API_KEY" \
            --dry-run=client -o yaml | kubectl apply -f -
        echo -e "${GREEN}✓ dota2-api-secret created in data namespace${NC}"
    fi
fi

echo ""

# ========================================
# Summary
# ========================================
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}✅ Secrets Setup Complete!${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

echo "Secrets in data namespace:"
kubectl get secrets -n data 2>/dev/null | grep -E "mongodb-secret|dota2-api-secret" || echo "  None"
echo ""

if kubectl get namespace "$JENKINS_NAMESPACE" &>/dev/null; then
    echo "Secrets in $JENKINS_NAMESPACE namespace:"
    kubectl get secrets -n "$JENKINS_NAMESPACE" 2>/dev/null | grep -E "jenkins-|github-|dockerhub-" || echo "  None"
    echo ""
fi

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}📋 Created Secrets Summary:${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Check which secrets were created
SECRETS_CREATED=0

echo "Data namespace:"
if kubectl get secret mongodb-secret -n data &>/dev/null; then
    echo "  ✅ mongodb-secret"
    SECRETS_CREATED=$((SECRETS_CREATED + 1))
fi
if kubectl get secret dota2-api-secret -n data &>/dev/null; then
    echo "  ✅ dota2-api-secret"
    SECRETS_CREATED=$((SECRETS_CREATED + 1))
fi

echo ""
echo "Jenkins namespace:"
if kubectl get secret jenkins-admin-credentials -n "$JENKINS_NAMESPACE" &>/dev/null; then
    echo "  ✅ jenkins-admin-credentials"
    SECRETS_CREATED=$((SECRETS_CREATED + 1))
fi
if kubectl get secret github-credentials -n "$JENKINS_NAMESPACE" &>/dev/null; then
    echo "  ✅ github-credentials"
    SECRETS_CREATED=$((SECRETS_CREATED + 1))
fi
if kubectl get secret dockerhub-credentials -n "$JENKINS_NAMESPACE" &>/dev/null; then
    echo "  ✅ dockerhub-credentials"
    SECRETS_CREATED=$((SECRETS_CREATED + 1))
fi
if kubectl get secret dockerhub-pull-secret -n "$JENKINS_NAMESPACE" &>/dev/null; then
    echo "  ✅ dockerhub-pull-secret"
    SECRETS_CREATED=$((SECRETS_CREATED + 1))
fi
if kubectl get secret jenkins-slack-webhook -n "$JENKINS_NAMESPACE" &>/dev/null; then
    echo "  ✅ jenkins-slack-webhook"
    SECRETS_CREATED=$((SECRETS_CREATED + 1))
fi

echo ""
echo -e "${GREEN}Total secrets created: $SECRETS_CREATED${NC}"
echo ""

echo -e "${BLUE}================================${NC}"
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

if [ "$ENVIRONMENT" = "dev" ]; then
    echo "  Run: ./cli/start-dev-k8s.sh"
else
    echo "  Run: ./cli/deploy-with-helm.sh $ENVIRONMENT"
fi

echo ""
echo -e "${GREEN}🎉 Done!${NC}"