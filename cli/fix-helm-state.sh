#!/bin/bash

set -e

echo -e "\033[0;31m================================\033[0m"
echo -e "\033[0;31m🔥 NUCLEAR CLEANUP - This will delete EVERYTHING\033[0m"
echo -e "\033[0;31m================================\033[0m"
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

# Cluster Configuration (optional, has defaults)
CLUSTER_NAME="${CLUSTER_NAME:-dota2-dev}"

# Debug mode
if [ "${DEBUG:-false}" = "true" ]; then
    echo "🐛 Debug - Configuration:"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  CLUSTER_NAME: $CLUSTER_NAME"
    echo ""
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

read -p "Are you SURE you want to delete all data and start fresh? (yes/no): " -r
if [[ ! $REPLY == "yes" ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 1: Removing Helm release and all associated resources...${NC}"

# Remove Helm release (all versions)
helm uninstall dota2-meta-lab -n data 2>/dev/null || echo "No Helm release found"

# Delete all Helm secrets for this release
kubectl delete secret -n data -l owner=helm,name=dota2-meta-lab --force --grace-period=0 2>/dev/null || true

echo ""
echo -e "${YELLOW}Step 2: Stopping all workloads...${NC}"

# Delete all workloads
kubectl delete deployment,statefulset,job,pod --all -n data --force --grace-period=0 2>/dev/null || true

# Wait a moment
sleep 3

echo ""
echo -e "${YELLOW}Step 3: Removing all PVCs and finalizers...${NC}"

# Get all PVCs and remove finalizers
for pvc in $(kubectl get pvc -n data -o name 2>/dev/null); do
    echo "Processing $pvc..."
    kubectl patch $pvc -n data -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl delete $pvc -n data --force --grace-period=0 2>/dev/null || true
done

echo ""
echo -e "${YELLOW}Step 4: Cleaning up PersistentVolumes...${NC}"

# Delete PVs that were bound to this namespace
for pv in $(kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef.namespace=="data") | .metadata.name' 2>/dev/null); do
    echo "Deleting PV: $pv"
    kubectl patch pv $pv -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl delete pv $pv --force --grace-period=0 2>/dev/null || true
done

echo ""
echo -e "${YELLOW}Step 5: Recreating namespace...${NC}"

# Delete and recreate namespace
kubectl delete namespace data --force --grace-period=0 2>/dev/null || true

# Wait for namespace to be fully deleted
echo "Waiting for namespace deletion..."
while kubectl get namespace data 2>/dev/null; do
    # Force finalize if stuck
    kubectl get namespace data -o json 2>/dev/null | \
        jq '.spec.finalizers = []' | \
        kubectl replace --raw "/api/v1/namespaces/data/finalize" -f - 2>/dev/null || true
    sleep 2
done

# Recreate namespace
kubectl create namespace data

echo ""
echo -e "${YELLOW}Step 6: Verifying clean state...${NC}"

echo "Checking Helm releases:"
helm list -n data

echo ""
echo "Checking PVCs:"
kubectl get pvc -n data 2>/dev/null || echo "✓ No PVCs"

echo ""
echo "Checking PVs:"
kubectl get pv 2>/dev/null | grep data || echo "✓ No PVs bound to data namespace"

echo ""
echo "Checking pods:"
kubectl get pods -n data 2>/dev/null || echo "✓ No pods"

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}✅ Environment completely reset!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "You can now run: ./cli/start-dev-k8s.sh"
echo ""