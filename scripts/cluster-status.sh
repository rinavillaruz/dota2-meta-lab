#!/bin/bash

echo "🔍 Checking Cluster Status..."
echo ""

# Check nodes
echo "📦 Nodes:"
kubectl get nodes
echo ""

# Check namespaces
echo "📁 Namespaces:"
kubectl get namespaces | grep -E 'NAME|data|ml-pipeline|ingress-nginx'
echo ""

# Check storage
echo "💾 Storage (PVCs):"
kubectl get pvc --all-namespaces
echo ""

# Check data services
echo "🍃 Data Services:"
kubectl get pods -n data -o wide
echo ""

# Check ML services
echo "🤖 ML Pipeline:"
kubectl get pods -n ml-pipeline -o wide
echo ""

# Check services
echo "🌐 Services:"
kubectl get svc --all-namespaces | grep -E 'NAMESPACE|data|ml-pipeline'
echo ""

# Check ingress
echo "🔗 Ingress:"
kubectl get ingress --all-namespaces
echo ""

echo "✅ Status check complete!"