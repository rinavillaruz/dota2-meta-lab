#!/bin/bash

echo "🧹 Cleaning up deployments..."

# Delete in reverse order
echo "Deleting ML Pipeline..."
kubectl delete -f ../k8s/ml-pipeline/ --ignore-not-found=true

echo "Deleting Data Services..."
kubectl delete -f ../k8s/data/redis/ --ignore-not-found=true
kubectl delete -f ../k8s/data/mongodb/ --ignore-not-found=true

echo "Deleting Storage..."
kubectl delete -f ../k8s/storage/ --ignore-not-found=true

echo "Deleting Namespaces..."
kubectl delete -f ../k8s/namespaces/namespaces.yaml --ignore-not-found=true

echo "✅ Cleanup complete!"
echo ""
echo "Note: To fully reset, delete the kind cluster:"
echo "  kind delete cluster --name ml-cluster"
kind delete cluster --name ml-cluster
echo ""
echo "✅ ml-cluster has been deleted!"