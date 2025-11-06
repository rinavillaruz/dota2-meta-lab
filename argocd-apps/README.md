# ArgoCD Application Definitions

This directory contains ArgoCD Application manifests for the Dota2 Meta Lab project.

## Applications

- `dota2-dev.yaml` - Development environment
- `dota2-prod.yaml` - Production environment

## How It Works (GitOps)

1. These YAML files define **what** ArgoCD should deploy
2. They point to the `deploy/helm/` directory in this repo
3. When you change `deploy/helm/values-dev.yaml` and push to Git
4. ArgoCD automatically detects the change and syncs your cluster
5. **Git is the source of truth** - your cluster always matches Git

## Usage

### Deploy an application to ArgoCD:
```bash
# Deploy development environment
kubectl apply -f argocd-apps/dota2-dev.yaml

# Deploy production environment
kubectl apply -f argocd-apps/dota2-prod.yaml

# Deploy both at once
kubectl apply -f argocd-apps/
```

### View in ArgoCD UI:
```bash
# Start port-forward (if not already running)
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Open http://localhost:8080 in your browser
```

### Manage via CLI:
```bash
# List applications
argocd app list

# Get application details
argocd app get dota2-dev

# Sync manually (force sync)
argocd app sync dota2-dev

# Watch sync status
argocd app sync dota2-dev --watch

# Delete application from ArgoCD (keeps resources running)
argocd app delete dota2-dev

# Delete application and all its resources
argocd app delete dota2-dev --cascade
```

## GitOps Workflow

### Scenario: Update ML API to 3 replicas
```bash
# 1. Edit the values file
vim deploy/helm/values-dev.yaml
# Change: mlApi.replicas: 3

# 2. Commit and push
git add deploy/helm/values-dev.yaml
git commit -m "Scale ML API to 3 replicas"
git push

# 3. ArgoCD automatically detects and syncs (within 3 minutes)
# Or sync manually:
argocd app sync dota2-dev

# 4. Verify
kubectl get pods -n ml-pipeline
```

## Restoring ArgoCD

If you reinstall ArgoCD and need to restore your applications:
```bash
# 1. Install ArgoCD
cd scripts
./install-argocd.sh

# 2. Restore all applications
kubectl apply -f argocd-apps/

# 3. ArgoCD will automatically sync them from Git
```

## Troubleshooting

### Application stuck syncing
```bash
# Check sync status
argocd app get dota2-dev

# View logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Force refresh
argocd app get dota2-dev --refresh
```

### Application out of sync
```bash
# See what's different
argocd app diff dota2-dev

# Sync to match Git
argocd app sync dota2-dev
```

### Delete and recreate application
```bash
# Delete from ArgoCD (keeps resources)
kubectl delete -f argocd-apps/dota2-dev.yaml

# Recreate
kubectl apply -f argocd-apps/dota2-dev.yaml
```

## Important Notes

- **These files are the source of truth** for your ArgoCD setup
- Keep them in Git so you can always recreate your deployment
- ArgoCD watches your `deploy/helm/` directory for changes
- Changes to Git → Auto-deployed to cluster (GitOps!)
- If you delete ArgoCD, just reapply these files to restore