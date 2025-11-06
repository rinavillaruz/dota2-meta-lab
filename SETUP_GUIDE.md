# Dota 2 Meta Lab - Complete Setup Guide

## Overview

This guide walks you through setting up a complete CI/CD pipeline for the Dota 2 Meta Tracker application.

## Architecture

```
Developer → Git Push → Jenkins (CI) → Docker Build → Docker Registry
                                    ↓
                              Update Git Repo
                                    ↓
                              ArgoCD (CD) → Kubernetes Cluster
                                    ↓
                         Running Application (API + Training Jobs)
```

## Part 1: Install Jenkins

### Step 1: Deploy Jenkins to Kubernetes

```bash
cd scripts
chmod +x install-jenkins.sh
./install-jenkins.sh
```

This will:
- Create `jenkins` namespace
- Deploy Jenkins with persistent storage
- Expose Jenkins on NodePort 30808
- Configure Jenkins with Configuration as Code (JCasC)

### Step 2: Access Jenkins

Open your browser: **http://localhost:30808**

**Credentials:**
- Username: `admin`
- Password: `admin`

⚠️ **Change the password immediately after first login!**

### Step 3: Install Required Plugins

Jenkins → Manage Jenkins → Plugins → Available Plugins

Install these:
- ✅ Docker Pipeline
- ✅ Kubernetes Plugin
- ✅ Git Plugin
- ✅ Pipeline Plugin
- ✅ Credentials Plugin

### Step 4: Configure Credentials

Jenkins → Manage Jenkins → Credentials

Add these credentials:

#### GitHub Credentials
- ID: `github-credentials`
- Type: Username with password
- Username: Your GitHub username
- Password: Your GitHub Personal Access Token

To create a GitHub token:
1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Generate new token with `repo` scope

#### Docker Hub Credentials
- ID: `docker-hub-credentials`
- Type: Username with password
- Username: Your Docker Hub username
- Password: Your Docker Hub password/token

---

## Part 2: Set Up Your Project

### Step 1: Project Structure

Your project should look like this:

```
dota2-meta-lab/
├── .git/
├── ci/
│   ├── Jenkinsfile            # CI/CD pipeline definition
├── build
│   ├── Dockerfile             # Multi-stage Docker build             
│   ├── requirements.txt       # Python dependencies
├── fetch_opendota_data.py     # Data fetching script
├── train_model.py             # Model training script
├── src/                       # Source code
│   ├── __init__.py
│   ├── data/
│   ├── models/
│   └── api/
├── api/                       # API server
│   ├── __init__.py
│   └── app.py
├── tests/                     # Unit tests
│   └── test_*.py
├── helm/                      # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   └── templates/
└── argocd-apps/              # ArgoCD application definitions
    └── dota2-dev.yaml
```

### Step 2: Add Files to Your Repository

```bash
# Copy the files we created
cp /path/to/ci/Jenkinsfile ./
cp /path/to/build/Dockerfile ./
cp /path/to/build/requirements.txt ./
cp /path/to/fetch_opendota_data.py ./
cp /path/to/train_model.py ./

# Create directory structure
mkdir -p src/data src/models src/api api tests

# Commit and push
git add .
git commit -m "ci: add Jenkins pipeline and Python scripts"
git push
```

### Step 3: Create Jenkins Pipeline

1. Go to Jenkins → New Item
2. Name: `dota2-meta-lab`
3. Type: Pipeline
4. Configure:
   - **Pipeline Definition:** Pipeline script from SCM
   - **SCM:** Git
   - **Repository URL:** https://github.com/rinavillaruz/dota2-meta-lab.git
   - **Credentials:** Select your GitHub credentials
   - **Branch:** */main
   - **Script Path:** ci/Jenkinsfile

5. Save

---

## Part 3: Build and Deploy

### Step 1: Trigger a Build

Jenkins → dota2-meta-lab → Build Now

The pipeline will:
1. ✅ Checkout code from Git
2. ✅ Run tests
3. ✅ Build Docker image
4. ✅ Push image to registry
5. ✅ Update Helm values with new image tag
6. ✅ Trigger ArgoCD sync
7. ✅ Verify deployment

### Step 2: Monitor Deployment

**Jenkins Console:**
```
http://localhost:30808/job/dota2-meta-lab/
```

**ArgoCD UI:**
```
http://localhost:30080/applications/dota2-dev
```

**Kubernetes Pods:**
```bash
kubectl get pods -n data
kubectl logs -n data -l app=ml-api -f
```

---

## Part 4: Develop Dota 2 Meta Tracker

### Step 1: Fetch OpenDota Data

```bash
# Run locally
python fetch_opendota_data.py

# Or run in Kubernetes
kubectl run opendota-fetcher --rm -it \
  --image=python:3.11 \
  --restart=Never \
  -- bash -c "pip install requests && python fetch_opendota_data.py"
```

This fetches:
- ✅ Hero data
- ✅ Hero statistics
- ✅ Pro match data
- ✅ High MMR match data

### Step 2: Train Model

```bash
# Run locally
python train_model.py

# Or deploy training job via ArgoCD
kubectl apply -f deploy/helm/templates/ml-training-job.yaml
```

The model will:
- ✅ Load match data
- ✅ Extract features (hero picks, team composition)
- ✅ Train neural network
- ✅ Evaluate performance
- ✅ Save model to /models

### Step 3: Serve Predictions via API

Create `api/app.py`:

```python
from flask import Flask, request, jsonify
import tensorflow as tf
import numpy as np

app = Flask(__name__)

# Load model
model = tf.keras.models.load_model('/models/dota2_meta_model')

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/predict', methods=['POST'])
def predict():
    data = request.json
    # Extract features from request
    features = extract_features(data)
    # Make prediction
    prediction = model.predict(features)
    return jsonify({
        "win_probability": float(prediction[0][0])
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

---

## Part 5: GitOps Workflow

### Development Workflow

```bash
# 1. Make changes to your code
vim src/models/predictor.py

# 2. Test locally
python -m pytest tests/

# 3. Commit and push
git add .
git commit -m "feat: improve prediction accuracy"
git push

# 4. Jenkins automatically:
#    - Runs tests
#    - Builds Docker image
#    - Pushes to registry
#    - Updates Git with new image tag

# 5. ArgoCD automatically:
#    - Detects Git changes
#    - Syncs to Kubernetes
#    - Deploys new version

# 6. Verify deployment
kubectl get pods -n data
argocd app get dota2-dev
```

---

## Part 6: Monitoring and Debugging

### View Logs

```bash
# Application logs
kubectl logs -n data -l app=ml-api -f

# Training job logs
kubectl logs -n ml-pipeline -l job-name=model-training -f

# Jenkins logs
kubectl logs -n jenkins -l app=jenkins -f
```

### Check Status

```bash
# ArgoCD application status
argocd app get dota2-dev

# Kubernetes resources
kubectl get all -n data

# Jenkins pipeline status
curl http://localhost:30808/job/dota2-meta-lab/lastBuild/api/json
```

### Troubleshooting

**Jenkins build fails:**
```bash
# Check Jenkins logs
kubectl logs -n jenkins -l app=jenkins

# Verify credentials
# Jenkins → Manage Jenkins → Credentials
```

**Docker push fails:**
```bash
# Verify Docker Hub credentials
# Test manually: docker login
```

**ArgoCD not syncing:**
```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Manual sync
argocd app sync dota2-dev
```

---

## Next Steps

✅ **You now have:**
- Complete CI/CD pipeline
- Automated testing and deployment
- GitOps workflow with ArgoCD
- Data fetching from OpenDota API
- TensorFlow model training
- Kubernetes-native deployment

🚀 **What to build next:**
1. Improve model accuracy
2. Add real-time predictions API
3. Create web dashboard
4. Add monitoring (Prometheus/Grafana)
5. Implement A/B testing
6. Scale horizontally

---

## Useful Commands

```bash
# Jenkins
kubectl get pods -n jenkins
kubectl logs -n jenkins -l app=jenkins -f
http://localhost:30808

# ArgoCD
argocd app list
argocd app get dota2-dev
argocd app sync dota2-dev
http://localhost:30080

# Application
kubectl get all -n data
kubectl logs -n data -l app=ml-api -f
kubectl port-forward -n data svc/ml-api 8080:80

# Training
kubectl get jobs -n ml-pipeline
kubectl logs -n ml-pipeline -l job-name=model-training -f
```

---

## Resources

- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OpenDota API](https://docs.opendota.com/)
- [TensorFlow Documentation](https://www.tensorflow.org/api_docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

---

**Happy coding! 🎮🤖**