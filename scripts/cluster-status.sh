#!/bin/bash

echo "🔍 Checking Cluster Status..."
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check Helm releases
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🎡 Helm Releases:${NC}"
echo -e "${BLUE}========================================${NC}"
helm list -A
echo ""

# Check nodes
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📦 Nodes:${NC}"
echo -e "${BLUE}========================================${NC}"
kubectl get nodes -o wide
echo ""

# Check namespaces
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📁 Namespaces:${NC}"
echo -e "${BLUE}========================================${NC}"
kubectl get namespaces | grep -E 'NAME|data|ml-pipeline'
echo ""

# Check storage
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}💾 Storage (PVCs):${NC}"
echo -e "${BLUE}========================================${NC}"
kubectl get pvc --all-namespaces
echo ""

# Check data services
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🍃 Data Services (namespace: data):${NC}"
echo -e "${BLUE}========================================${NC}"
kubectl get pods -n data -o wide 2>/dev/null || echo "No pods found in 'data' namespace"
echo ""

# Check ML Pipeline services
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🤖 ML Pipeline (namespace: ml-pipeline):${NC}"
echo -e "${BLUE}========================================${NC}"
kubectl get pods -n ml-pipeline -o wide 2>/dev/null || echo "No pods found in 'ml-pipeline' namespace"
echo ""

# Check all services
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🌐 Services:${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Data namespace:"
kubectl get svc -n data 2>/dev/null || echo "  No services found"
echo ""
echo "ML Pipeline namespace:"
kubectl get svc -n ml-pipeline 2>/dev/null || echo "  No services found"
echo ""

# Check Helm revision history
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📜 Helm History:${NC}"
echo -e "${BLUE}========================================${NC}"
for release in $(helm list -A -q | grep 'dota2-meta-lab'); do
    namespace=$(helm list -A | grep "$release" | awk '{print $2}')
    echo -e "${GREEN}Release: $release (namespace: $namespace)${NC}"
    helm history "$release" -n "$namespace"
    echo ""
done

# Check Metrics Server Status
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📊 Metrics Server Status:${NC}"
echo -e "${BLUE}========================================${NC}"
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    METRICS_STATUS=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    METRICS_READY=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}')
    METRICS_DESIRED=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.replicas}')
    
    if [ "$METRICS_STATUS" = "True" ]; then
        echo -e "${GREEN}✅ Metrics Server: Running (${METRICS_READY}/${METRICS_DESIRED} ready)${NC}"
    else
        echo -e "${YELLOW}⚠️  Metrics Server: Installed but not ready yet${NC}"
        kubectl get pods -n kube-system -l k8s-app=metrics-server
    fi
else
    echo -e "${RED}❌ Metrics Server: Not installed${NC}"
    echo "To install: cd scripts && ./install-metrics-server.sh"
fi
echo ""

# Show resource usage if metrics server is available
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📊 Resource Usage:${NC}"
echo -e "${BLUE}========================================${NC}"
if kubectl top nodes &>/dev/null; then
    echo "Nodes:"
    kubectl top nodes
    echo ""
    echo "Pods (data namespace):"
    kubectl top pods -n data 2>/dev/null || echo "  Metrics not available yet (still collecting)"
    echo ""
    echo "Pods (ml-pipeline namespace):"
    kubectl top pods -n ml-pipeline 2>/dev/null || echo "  Metrics not available yet (still collecting)"
else
    if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        echo -e "${YELLOW}⚠️  Metrics server is installed but still collecting data${NC}"
        echo "Wait 30-60 seconds and try again, or run: kubectl top nodes"
    else
        echo -e "${YELLOW}⚠️  Metrics server not installed${NC}"
        echo "To install: cd scripts && ./install-metrics-server.sh"
    fi
fi
echo ""

# Summary of access methods
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📝 Quick Access Commands:${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Port-forward to services:"
echo "  ML API:   kubectl port-forward -n ml-pipeline svc/ml-api 8080:80"
echo "  MongoDB:  kubectl port-forward -n data svc/mongodb 27017:27017"
echo "  Redis:    kubectl port-forward -n data svc/redis 6379:6379"
echo ""
echo "Check logs:"
echo "  kubectl logs -n data -l app=mongodb --tail=50"
echo "  kubectl logs -n data -l app=redis --tail=50"
echo "  kubectl logs -n ml-pipeline -l app=ml-api --tail=50"
echo ""
echo "Check resource usage:"
echo "  kubectl top nodes"
echo "  kubectl top pods -n data"
echo "  kubectl top pods -n ml-pipeline"
echo ""

echo -e "${GREEN}✅ Status check complete!${NC}"