#!/bin/bash

set -e

echo "🧹 Cleaning up deployments..."

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Determine environment (default to all)
ENVIRONMENT=${1:-all}

if [ "$ENVIRONMENT" = "all" ]; then
    echo -e "${BLUE}Uninstalling all Helm releases...${NC}"
    
    # Uninstall all dota2-meta-lab releases
    for release in $(helm list -A | grep dota2-meta-lab | awk '{print $1":"$2}'); do
        name=$(echo $release | cut -d: -f1)
        namespace=$(echo $release | cut -d: -f2)
        echo "Uninstalling $name from namespace $namespace..."
        helm uninstall "$name" -n "$namespace"
    done
else
    echo -e "${BLUE}Uninstalling Helm release for environment: ${ENVIRONMENT}${NC}"
    helm uninstall dota2-meta-lab-${ENVIRONMENT} -n data --ignore-not-found
fi

echo -e "${GREEN}✅ Helm releases removed${NC}\n"

# Delete namespaces (this will cascade delete everything)
echo -e "${BLUE}Deleting namespaces...${NC}"
kubectl delete namespace data --ignore-not-found=true
kubectl delete namespace ml-pipeline --ignore-not-found=true

echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo ""
echo "Note: To fully reset, delete the kind cluster:"
echo "  kind delete cluster --name ml-cluster"

read -p "Do you want to delete the Kind cluster? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kind delete cluster --name ml-cluster
    echo -e "${GREEN}✅ ml-cluster has been deleted!${NC}"
fi