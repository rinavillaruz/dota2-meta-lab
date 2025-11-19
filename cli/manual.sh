# Ignore this

mkdir -p ../data/{control-plane-{1..3},ml-training,mongodb,redis} ../models
kind create cluster --config ../k8s/ha/kind-ha-cluster.yaml --name ml-cluster

echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=180s

kubectl cluster-info

// check if metric server is installed
kubectl get deployment metrics-server -n kube-system

kubectl apply --validate=false -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for Kind (allow insecure TLS)
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
    {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
    }
]'

kubectl describe deployment metrics-server -n kube-system

kubectl top nodes
kubectl top pods -A

kubectl create namespace data --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ml-pipeline --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic mongodb-secret \
  --from-literal=username="admin" \
  --from-literal=password="changeme123" \
  --namespace=data \
  --dry-run=client -o yaml | kubectl apply -f -


kubectl get secret mongodb-secret -n data

helm lint ../deploy/helm

helm list -n data | grep -q "dota2-meta-lab-dev"

# if helm release already exists
helm upgrade dota2-meta-lab-dev ../deploy/helm \
      -f ../deploy/helm/values.yaml \
      -f ../deploy/helm/values-dev.yaml \
      --namespace data
# If not, install
helm install dota2-meta-lab-dev ../deploy/helm \
      -f ../deploy/helm/values.yaml \
      -f ../deploy/helm/values-dev.yaml \
      --namespace data

kubectl get pods -n data -l app=mongodb

kubectl get pods -n data -l app=redis

kubectl get pods -n ml-pipeline -l app=ml-api

###############################################

kubectl apply -f "../jenkins-k8s/base/00-namespace.yaml"
kubectl apply -f "../jenkins-k8s/base/01-serviceaccount.yaml"
kubectl apply -f "../jenkins-k8s/base/02-clusterrole.yaml"
kubectl apply -f "../jenkins-k8s/base/03-clusterrolebinding.yaml"
kubectl apply -f "../jenkins-k8s/base/04-pvc.yaml"
kubectl apply -f "../jenkins-k8s/base/05-configmap.yaml"
kubectl apply -f "../jenkins-k8s/base/06-deployment.yaml"
kubectl apply -f "../jenkins-k8s/base/07-service.yaml"

##############################################

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
kubectl create namespace argocd

mkdir -p ../tmp

cat > "../tmp/argocd-values.yaml" <<'EOF'
# ArgoCD configuration for local Kind cluster

global:
  domain: argocd.local

server:
  service:
    type: NodePort
    nodePortHttps: 30443
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

controller:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi

repoServer:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

redis:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

redis-ha:
  enabled: false

configs:
  params:
    server.insecure: true
EOF

# Check if kubectl can connect to cluster
kubectl cluster-info

# Check if argocd is installed
kubectl get namespace argocd

helm list -n argocd | grep -q "argocd"


# Proceed with installation of argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Ensure namespace exists
# kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Check if ArgoCD release already exists
helm list -n argocd

helm install argocd argo/argo-cd \
      --namespace argocd \
      --values "../tmp/argocd-values.yaml"

# Get the password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Wait for rollout
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

# Wait for argocd pods to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=300s


rm -f "../tmp/argocd-values.yaml"

############## Login to argocd #################
argocd login localhost:30443 --username admin --password "$ARGOCD_PASSWORD" --insecure

################################################

kubectl patch statefulset argocd-application-controller -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/tolerations",
    "value": [
      {
        "key": "node-role.kubernetes.io/control-plane",
        "operator": "Exists",
        "effect": "NoSchedule"
      }
    ]
  },
  {
    "op": "add",
    "path": "/spec/template/spec/nodeSelector",
    "value": {
      "topology": "control-plane"
    }
  }
]'

# After patching, delete the pending pod:
kubectl delete pod -n argocd argocd-application-controller-0