#!/bin/bash

set -e

echo "🔍 Dota 2 Meta Lab - Comprehensive Cluster Status"
echo "===================================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Status counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_subheader() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
}

check_status() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${RED}❌ $2${NC}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

check_warning() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# -----------------------------------------------------------------------------
# Cluster Connection Check
# -----------------------------------------------------------------------------
print_header "🌐 Cluster Connectivity"

if kubectl cluster-info &>/dev/null; then
    check_status 0 "Connected to Kubernetes cluster"
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
    echo "   Context: $CLUSTER_NAME"
else
    check_status 1 "Failed to connect to cluster"
    echo -e "${RED}Please ensure your cluster is running and kubeconfig is configured${NC}"
    exit 1
fi

# Get cluster version
CLUSTER_VERSION=$(kubectl version --short 2>/dev/null | grep -i server || echo "Unknown")
echo "   $CLUSTER_VERSION"

# -----------------------------------------------------------------------------
# Nodes Status
# -----------------------------------------------------------------------------
print_header "📦 Cluster Nodes"

NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo 0)

echo "Total Nodes: $NODE_COUNT | Ready: $READY_NODES"
echo ""
kubectl get nodes -o wide

if [ "$NODE_COUNT" -eq "$READY_NODES" ] && [ "$NODE_COUNT" -gt 0 ]; then
    check_status 0 "All nodes are Ready ($READY_NODES/$NODE_COUNT)"
else
    check_status 1 "Some nodes are not Ready ($READY_NODES/$NODE_COUNT)"
fi

# -----------------------------------------------------------------------------
# Namespaces Overview
# -----------------------------------------------------------------------------
print_header "📁 Namespaces"

kubectl get namespaces | grep -E "NAME|argocd|jenkins|data|ml-pipeline|kube-system"

# Check critical namespaces
for ns in "argocd" "jenkins" "data" "ml-pipeline"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        check_status 0 "Namespace '$ns' exists"
    else
        check_warning "Namespace '$ns' not found"
    fi
done

# -----------------------------------------------------------------------------
# Jenkins Status
# -----------------------------------------------------------------------------
print_header "🔧 Jenkins CI/CD"

if kubectl get namespace jenkins &>/dev/null; then
    print_subheader "Jenkins Pods"
    kubectl get pods -n jenkins -o wide 2>/dev/null || echo "  No pods found"
    
    # Check Jenkins pod status - support both Helm and simple installations
    JENKINS_POD_HELM=$(kubectl get pods -n jenkins -l app.kubernetes.io/name=jenkins --field-selector=status.phase=Running 2>/dev/null | grep -c Running || echo 0)
    JENKINS_POD_SIMPLE=$(kubectl get pods -n jenkins -l app=jenkins --field-selector=status.phase=Running 2>/dev/null | grep -c Running || echo 0)
    
    if [ "$JENKINS_POD_HELM" -gt 0 ] || [ "$JENKINS_POD_SIMPLE" -gt 0 ]; then
        check_status 0 "Jenkins pod is Running"
        
        # Get Jenkins pod name
        JENKINS_POD=$(kubectl get pods -n jenkins -l "app.kubernetes.io/name=jenkins" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
                      kubectl get pods -n jenkins -l "app=jenkins" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -n "$JENKINS_POD" ]; then
            echo "   Pod: $JENKINS_POD"
            
            # Check if container is ready
            READY=$(kubectl get pod "$JENKINS_POD" -n jenkins -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
            if [ "$READY" = "true" ]; then
                check_status 0 "Jenkins container is ready"
            else
                check_warning "Jenkins container is not ready yet"
            fi
        fi
    else
        check_status 1 "Jenkins pod is not Running"
    fi
    
    print_subheader "Jenkins Service"
    kubectl get svc -n jenkins 2>/dev/null || echo "  No services found"
    
    # Check Jenkins service
    if kubectl get svc jenkins -n jenkins &>/dev/null; then
        check_status 0 "Jenkins service exists"
        
        SERVICE_TYPE=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.spec.type}')
        echo "   Type: $SERVICE_TYPE"
        
        if [ "$SERVICE_TYPE" = "NodePort" ]; then
            NODE_PORT=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.spec.ports[0].nodePort}')
            echo -e "   ${GREEN}Access URL: http://localhost:${NODE_PORT}${NC}"
        fi
    else
        check_warning "Jenkins service not found"
    fi
    
    print_subheader "Jenkins PVC"
    kubectl get pvc -n jenkins 2>/dev/null || echo "  No PVCs found"
else
    check_warning "Jenkins namespace not found - Not installed"
    echo "   To install: cd scripts && ./install-jenkins.sh"
fi

# -----------------------------------------------------------------------------
# ArgoCD Status
# -----------------------------------------------------------------------------
print_header "🔄 ArgoCD GitOps"

if kubectl get namespace argocd &>/dev/null; then
    print_subheader "ArgoCD Pods"
    kubectl get pods -n argocd -o wide 2>/dev/null || echo "  No pods found"
    
    # Check ArgoCD server status
    ARGOCD_SERVER=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running 2>/dev/null | grep -c Running || echo 0)
    
    if [ "$ARGOCD_SERVER" -gt 0 ]; then
        check_status 0 "ArgoCD server is Running"
        
        # Check if server is ready
        READY=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
        if [ "$READY" = "true" ]; then
            check_status 0 "ArgoCD server is ready"
        else
            check_warning "ArgoCD server is not ready yet"
        fi
    else
        check_status 1 "ArgoCD server is not Running"
    fi
    
    # Check other ArgoCD components
    ARGOCD_CONTROLLER=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller --field-selector=status.phase=Running 2>/dev/null | grep -c Running || echo 0)
    ARGOCD_REPO=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server --field-selector=status.phase=Running 2>/dev/null | grep -c Running || echo 0)
    
    if [ "$ARGOCD_CONTROLLER" -gt 0 ]; then
        check_status 0 "ArgoCD application controller is Running"
    else
        check_status 1 "ArgoCD application controller is not Running"
    fi
    
    if [ "$ARGOCD_REPO" -gt 0 ]; then
        check_status 0 "ArgoCD repo server is Running"
    else
        check_status 1 "ArgoCD repo server is not Running"
    fi
    
    print_subheader "ArgoCD Services"
    kubectl get svc -n argocd 2>/dev/null || echo "  No services found"
    
    # Check ArgoCD service type
    if kubectl get svc argocd-server -n argocd &>/dev/null; then
        SERVICE_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}')
        echo "   Service Type: $SERVICE_TYPE"
        
        if [ "$SERVICE_TYPE" = "NodePort" ]; then
            NODE_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
            echo -e "   ${GREEN}Access URL: https://localhost:${NODE_PORT}${NC}"
        else
            echo -e "   ${YELLOW}Use port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
        fi
    fi
    
    # Check for ArgoCD applications
    print_subheader "ArgoCD Applications"
    if kubectl get applications -n argocd &>/dev/null 2>&1; then
        APP_COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
        if [ "$APP_COUNT" -gt 0 ]; then
            echo "Found $APP_COUNT ArgoCD application(s):"
            kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null
        else
            echo "   No ArgoCD applications deployed yet"
        fi
    fi
else
    check_warning "ArgoCD namespace not found - Not installed"
    echo "   To install: cd scripts && ./install-argocd.sh"
fi

# -----------------------------------------------------------------------------
# Data Services (MongoDB & Redis)
# -----------------------------------------------------------------------------
print_header "🍃 Data Services"

if kubectl get namespace data &>/dev/null; then
    print_subheader "Data Namespace Pods"
    kubectl get pods -n data -o wide 2>/dev/null || echo "  No pods found"
    
    # Check MongoDB
    MONGO_PODS=$(kubectl get pods -n data -l app=mongodb --no-headers 2>/dev/null | wc -l)
    MONGO_RUNNING=$(kubectl get pods -n data -l app=mongodb --field-selector=status.phase=Running 2>/dev/null | wc -l)
    
    if [ "$MONGO_PODS" -gt 0 ]; then
        if [ "$MONGO_RUNNING" -eq "$MONGO_PODS" ]; then
            check_status 0 "MongoDB pods running ($MONGO_RUNNING/$MONGO_PODS)"
        else
            check_warning "MongoDB pods not all running ($MONGO_RUNNING/$MONGO_PODS)"
        fi
    else
        check_warning "MongoDB not deployed"
    fi
    
    # Check Redis
    REDIS_PODS=$(kubectl get pods -n data -l app=redis --no-headers 2>/dev/null | wc -l)
    REDIS_RUNNING=$(kubectl get pods -n data -l app=redis --field-selector=status.phase=Running 2>/dev/null | wc -l)
    
    if [ "$REDIS_PODS" -gt 0 ]; then
        if [ "$REDIS_RUNNING" -eq "$REDIS_PODS" ]; then
            check_status 0 "Redis pods running ($REDIS_RUNNING/$REDIS_PODS)"
        else
            check_warning "Redis pods not all running ($REDIS_RUNNING/$REDIS_PODS)"
        fi
    else
        check_warning "Redis not deployed"
    fi
    
    print_subheader "Data Services"
    kubectl get svc -n data 2>/dev/null || echo "  No services found"
    
    print_subheader "Data Storage (PVCs)"
    kubectl get pvc -n data 2>/dev/null || echo "  No PVCs found"
else
    check_warning "Data namespace not found"
    echo "   To deploy: cd scripts && ./deploy-with-helm.sh dev"
fi

# -----------------------------------------------------------------------------
# ML Pipeline
# -----------------------------------------------------------------------------
print_header "🤖 ML Pipeline"

if kubectl get namespace ml-pipeline &>/dev/null; then
    print_subheader "ML Pipeline Pods"
    kubectl get pods -n ml-pipeline -o wide 2>/dev/null || echo "  No pods found"
    
    # Check ML API
    ML_API_PODS=$(kubectl get pods -n ml-pipeline -l app=ml-api --no-headers 2>/dev/null | wc -l)
    ML_API_RUNNING=$(kubectl get pods -n ml-pipeline -l app=ml-api --field-selector=status.phase=Running 2>/dev/null | wc -l)
    
    if [ "$ML_API_PODS" -gt 0 ]; then
        if [ "$ML_API_RUNNING" -eq "$ML_API_PODS" ]; then
            check_status 0 "ML API pods running ($ML_API_RUNNING/$ML_API_PODS)"
        else
            check_warning "ML API pods not all running ($ML_API_RUNNING/$ML_API_PODS)"
        fi
    else
        check_warning "ML API not deployed"
    fi
    
    # Check for ML training jobs
    TRAINING_JOBS=$(kubectl get jobs -n ml-pipeline --no-headers 2>/dev/null | wc -l)
    if [ "$TRAINING_JOBS" -gt 0 ]; then
        echo "   Found $TRAINING_JOBS training job(s)"
    fi
    
    print_subheader "ML Pipeline Services"
    kubectl get svc -n ml-pipeline 2>/dev/null || echo "  No services found"
    
    print_subheader "ML Pipeline Storage (PVCs)"
    kubectl get pvc -n ml-pipeline 2>/dev/null || echo "  No PVCs found"
else
    check_warning "ML Pipeline namespace not found"
    echo "   To deploy: cd scripts && ./deploy-with-helm.sh dev"
fi

# -----------------------------------------------------------------------------
# Storage Overview
# -----------------------------------------------------------------------------
print_header "💾 Storage Overview"

print_subheader "All PVCs in Cluster"
kubectl get pvc --all-namespaces 2>/dev/null || echo "  No PVCs found"

# Check storage class
print_subheader "Storage Classes"
kubectl get storageclass 2>/dev/null || echo "  No storage classes found"

# -----------------------------------------------------------------------------
# Helm Releases
# -----------------------------------------------------------------------------
print_header "🎡 Helm Releases"

HELM_RELEASES=$(helm list -A --no-headers 2>/dev/null | wc -l)
if [ "$HELM_RELEASES" -gt 0 ]; then
    helm list -A
    echo ""
    echo "Total releases: $HELM_RELEASES"
    
    # Check for dota2-meta-lab releases
    print_subheader "Dota2 Meta Lab Releases"
    for release in $(helm list -A -q | grep -i 'dota2' 2>/dev/null); do
        namespace=$(helm list -A | grep "$release" | awk '{print $2}')
        status=$(helm list -A | grep "$release" | awk '{print $8}')
        revision=$(helm list -A | grep "$release" | awk '{print $3}')
        
        echo -e "${GREEN}Release: $release${NC}"
        echo "  Namespace: $namespace"
        echo "  Status: $status"
        echo "  Revision: $revision"
        
        if [ "$status" = "deployed" ]; then
            check_status 0 "Helm release '$release' is deployed"
        else
            check_warning "Helm release '$release' status: $status"
        fi
        echo ""
    done
else
    check_warning "No Helm releases found"
fi

# -----------------------------------------------------------------------------
# Metrics Server
# -----------------------------------------------------------------------------
print_header "📊 Metrics Server"

if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    METRICS_STATUS=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    METRICS_READY=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}')
    METRICS_DESIRED=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.replicas}')
    
    if [ "$METRICS_STATUS" = "True" ]; then
        check_status 0 "Metrics Server is running (${METRICS_READY}/${METRICS_DESIRED} ready)"
    else
        check_warning "Metrics Server installed but not ready yet"
        kubectl get pods -n kube-system -l k8s-app=metrics-server
    fi
else
    check_warning "Metrics Server not installed"
    echo "   To install: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

# -----------------------------------------------------------------------------
# Resource Usage (if metrics available)
# -----------------------------------------------------------------------------
print_header "📊 Resource Usage"

if kubectl top nodes &>/dev/null; then
    print_subheader "Node Resource Usage"
    kubectl top nodes
    
    echo ""
    print_subheader "Pod Resource Usage - Data Namespace"
    kubectl top pods -n data 2>/dev/null || echo "  Metrics not available yet"
    
    echo ""
    print_subheader "Pod Resource Usage - ML Pipeline"
    kubectl top pods -n ml-pipeline 2>/dev/null || echo "  Metrics not available yet"
    
    echo ""
    print_subheader "Pod Resource Usage - Jenkins"
    kubectl top pods -n jenkins 2>/dev/null || echo "  Metrics not available yet"
    
    echo ""
    print_subheader "Pod Resource Usage - ArgoCD"
    kubectl top pods -n argocd 2>/dev/null || echo "  Metrics not available yet"
else
    if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        check_warning "Metrics server is installed but still collecting data"
        echo "   Wait 30-60 seconds and try again"
    else
        check_warning "Metrics server not installed"
    fi
fi

# -----------------------------------------------------------------------------
# Recent Events
# -----------------------------------------------------------------------------
print_header "📰 Recent Cluster Events"

echo "Last 10 events across all namespaces:"
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10

# -----------------------------------------------------------------------------
# Quick Access Commands
# -----------------------------------------------------------------------------
print_header "📝 Quick Access Commands"

echo ""
echo -e "${CYAN}Port-forward to services:${NC}"
echo "  Jenkins:   kubectl port-forward -n jenkins svc/jenkins 8080:8080"
echo "  ArgoCD:    kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  ML API:    kubectl port-forward -n ml-pipeline svc/ml-api 8080:80"
echo "  MongoDB:   kubectl port-forward -n data svc/mongodb 27017:27017"
echo "  Redis:     kubectl port-forward -n data svc/redis 6379:6379"
echo ""

echo -e "${CYAN}Check logs:${NC}"
echo "  Jenkins:   kubectl logs -n jenkins -l app=jenkins --tail=50 -f"
echo "  ArgoCD:    kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 -f"
echo "  MongoDB:   kubectl logs -n data -l app=mongodb --tail=50"
echo "  Redis:     kubectl logs -n data -l app=redis --tail=50"
echo "  ML API:    kubectl logs -n ml-pipeline -l app=ml-api --tail=50 -f"
echo ""

echo -e "${CYAN}Restart deployments:${NC}"
echo "  Jenkins:   kubectl rollout restart deployment/jenkins -n jenkins"
echo "  ArgoCD:    kubectl rollout restart deployment/argocd-server -n argocd"
echo "  ML API:    kubectl rollout restart deployment/ml-api -n ml-pipeline"
echo ""

# -----------------------------------------------------------------------------
# Summary Report
# -----------------------------------------------------------------------------
print_header "📊 Health Summary"

echo ""
echo -e "Total Checks:    ${BLUE}$TOTAL_CHECKS${NC}"
echo -e "Passed:          ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed:          ${RED}$FAILED_CHECKS${NC}"
echo -e "Warnings:        ${YELLOW}$WARNING_CHECKS${NC}"
echo ""

# Calculate health percentage
if [ "$TOTAL_CHECKS" -gt 0 ]; then
    HEALTH_PERCENTAGE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    
    if [ "$HEALTH_PERCENTAGE" -ge 90 ]; then
        echo -e "${GREEN}✅ Cluster Health: ${HEALTH_PERCENTAGE}% - Excellent${NC}"
    elif [ "$HEALTH_PERCENTAGE" -ge 70 ]; then
        echo -e "${YELLOW}⚠️  Cluster Health: ${HEALTH_PERCENTAGE}% - Good${NC}"
    elif [ "$HEALTH_PERCENTAGE" -ge 50 ]; then
        echo -e "${YELLOW}⚠️  Cluster Health: ${HEALTH_PERCENTAGE}% - Fair${NC}"
    else
        echo -e "${RED}❌ Cluster Health: ${HEALTH_PERCENTAGE}% - Poor${NC}"
    fi
fi

echo ""
echo -e "${GREEN}✅ Status check complete!${NC}"
echo ""