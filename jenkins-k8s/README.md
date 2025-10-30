# Jenkins Kubernetes Manifests

This directory contains Kubernetes manifests for deploying Jenkins in your cluster.

## 📁 Directory Structure

```
jenkins-k8s/
├── base/                           # Base manifests (environment-agnostic)
│   ├── 00-namespace.yaml          # Jenkins namespace
│   ├── 01-serviceaccount.yaml     # ServiceAccount for Jenkins
│   ├── 02-clusterrole.yaml        # Permissions Jenkins needs
│   ├── 03-clusterrolebinding.yaml # Bind role to ServiceAccount
│   ├── 04-pvc.yaml                # Persistent storage for Jenkins data
│   ├── 05-configmap.yaml          # Jenkins Configuration as Code (JCasC)
│   ├── 06-deployment.yaml         # Jenkins deployment
│   └── 07-service.yaml            # Service to expose Jenkins
├── overlays/                       # Environment-specific overrides
│   └── dev/                        # Development environment
└── README.md                       # This file
```

## 🔍 File Breakdown

### 00-namespace.yaml
**What it does:** Creates a dedicated namespace for Jenkins  
**Why:** Isolates Jenkins resources from other applications

### 01-serviceaccount.yaml
**What it does:** Creates a ServiceAccount for Jenkins pods  
**Why:** Jenkins needs an identity to interact with Kubernetes API

### 02-clusterrole.yaml
**What it does:** Defines permissions Jenkins needs  
**Permissions:**
- Create/manage pods (for dynamic build agents)
- Exec into pods (for running commands)
- Read pod logs (for displaying in Jenkins)
- Manage secrets (for storing credentials)
- Read ConfigMaps (for configuration)

### 03-clusterrolebinding.yaml
**What it does:** Binds the ClusterRole to Jenkins ServiceAccount  
**Why:** Grants Jenkins the permissions defined in ClusterRole

### 04-pvc.yaml
**What it does:** Requests persistent storage for Jenkins  
**Storage:** 10Gi for Jenkins home directory  
**Why:** Preserves Jenkins configuration, jobs, and build history across pod restarts

### 05-configmap.yaml
**What it does:** Jenkins Configuration as Code (JCasC)  
**Contains:**
- Initial admin credentials (admin/admin)
- Security settings
- Credential placeholders
- Pre-configured pipeline job
**Why:** Automates Jenkins setup instead of manual configuration

### 06-deployment.yaml
**What it does:** Deploys Jenkins as a pod  
**Key features:**
- Uses official Jenkins LTS image
- Mounts persistent storage
- Mounts Docker socket (for building images)
- Loads JCasC configuration
- Health checks
- Resource limits

### 07-service.yaml
**What it does:** Exposes Jenkins  
**Type:** NodePort (accessible on localhost:30808)  
**Ports:**
- 8080: Jenkins UI
- 50000: JNLP (for build agents)

## 🚀 Installation

### Option 1: Apply All at Once (Quick)

```bash
kubectl apply -f jenkins-k8s/base/
```

### Option 2: Apply Step-by-Step (Recommended for Learning)

```bash
# 1. Create namespace
kubectl apply -f jenkins-k8s/base/00-namespace.yaml

# 2. Create ServiceAccount
kubectl apply -f jenkins-k8s/base/01-serviceaccount.yaml

# 3. Set up RBAC
kubectl apply -f jenkins-k8s/base/02-clusterrole.yaml
kubectl apply -f jenkins-k8s/base/03-clusterrolebinding.yaml

# 4. Create storage
kubectl apply -f jenkins-k8s/base/04-pvc.yaml

# 5. Add configuration
kubectl apply -f jenkins-k8s/base/05-configmap.yaml

# 6. Deploy Jenkins
kubectl apply -f jenkins-k8s/base/06-deployment.yaml

# 7. Expose Jenkins
kubectl apply -f jenkins-k8s/base/07-service.yaml
```

### Option 3: Use the Installation Script

```bash
cd scripts
./install-jenkins.sh
```

## ✅ Verification

```bash
# Check if all resources are created
kubectl get all -n jenkins

# Check PVC
kubectl get pvc -n jenkins

# Check ConfigMap
kubectl get configmap -n jenkins

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=300s

# Check pod logs
kubectl logs -n jenkins -l app=jenkins -f
```

## 🌐 Access Jenkins

Once deployed, access Jenkins at:
```
http://localhost:30808
```

**Default Credentials:**
- Username: `admin`
- Password: `admin`

⚠️ **Important:** Change the password after first login!

## 🔧 Customization

### Change Storage Size

Edit `04-pvc.yaml`:
```yaml
resources:
  requests:
    storage: 20Gi  # Change from 10Gi to 20Gi
```

### Change Admin Password

Edit `05-configmap.yaml`:
```yaml
users:
  - id: "admin"
    password: "your-secure-password"
```

### Change Port

Edit `07-service.yaml`:
```yaml
nodePort: 30808  # Change to different port
```

### Add Credentials

Edit `05-configmap.yaml` and update the credentials section with your GitHub and Docker Hub credentials.

## 🧹 Cleanup

### Remove Jenkins but keep PVC (data preserved)

```bash
kubectl delete deployment jenkins -n jenkins
kubectl delete service jenkins -n jenkins
```

### Remove everything including data

```bash
kubectl delete namespace jenkins
```

Or:
```bash
kubectl delete -f jenkins-k8s/base/
```

## 📝 Notes

### Docker Socket Mount

The deployment mounts `/var/run/docker.sock` from the host. This allows Jenkins to build Docker images using the host's Docker daemon.

**Security consideration:** This gives Jenkins significant permissions. In production, consider:
- Using Docker-in-Docker (DinD)
- Using Kaniko for building images
- Using Kubernetes plugin for containerized builds

### Resource Limits

Current limits:
- Memory: 1Gi request, 2Gi limit
- CPU: 500m request, 1 CPU limit

Adjust based on your workload in `06-deployment.yaml`.

### Persistence

Jenkins data is stored in a PersistentVolumeClaim. If you delete the PVC, all Jenkins configuration and build history will be lost!

## 🔗 Integration with ArgoCD

To manage Jenkins with ArgoCD:

1. Create an ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: jenkins
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/rinavillaruz/dota2-meta-lab.git
    targetRevision: main
    path: jenkins-k8s/base
  destination:
    server: https://kubernetes.default.svc
    namespace: jenkins
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

2. Apply:
```bash
kubectl apply -f argocd-apps/jenkins.yaml
```

## 📚 References

- [Jenkins Official Docs](https://www.jenkins.io/doc/)
- [Jenkins Configuration as Code](https://www.jenkins.io/projects/jcasc/)
- [Jenkins Kubernetes Plugin](https://plugins.jenkins.io/kubernetes/)