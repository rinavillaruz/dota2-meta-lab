# 🎮 Dota2 Meta Lab Platform

[![Deploy to Environment](https://github.com/rinavillaruz/dota2-meta-lab/actions/workflows/deploy.yaml/badge.svg)](https://github.com/rinavillaruz/dota2-meta-lab/actions/workflows/deploy.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=flat&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)

An enterprise-grade MLOps platform for Dota 2 match prediction, meta analysis, and data-driven insights. Built with production-ready infrastructure patterns including automated CI/CD, multi-environment deployments, and comprehensive observability.

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Dota2 Meta Lab Platform                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Data Fetcher │  │  ML Trainer  │  │  API Service │          │
│  │   (Python)   │  │  (PyTorch)   │  │   (FastAPI)  │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                   │
│         └──────────────────┼──────────────────┘                  │
│                            │                                      │
│         ┌──────────────────┴──────────────────┐                 │
│         │                                      │                  │
│  ┌──────▼───────┐                    ┌────────▼────────┐        │
│  │   MongoDB    │                    │     Redis       │        │
│  │  (Database)  │                    │    (Cache)      │        │
│  └──────────────┘                    └─────────────────┘        │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Features

### Core Platform
- **🔄 Automated Data Pipeline** - Real-time Dota 2 match data fetching and processing
- **🤖 ML Training Pipeline** - Automated model training and versioning with MLflow
- **⚡ REST API** - FastAPI-based inference service with async support
- **📊 Interactive Analysis** - Jupyter notebooks for data exploration

### DevOps & Infrastructure
- **☸️ Kubernetes Native** - Helm charts for declarative deployments
- **🔀 Multi-Environment** - Separate dev, staging, and production environments
- **🔄 GitOps Workflows** - Automated CI/CD with GitHub Actions and Jenkins
- **📦 Container Registry** - Multi-stage Docker builds optimized for production
- **🔍 Observability** - Comprehensive monitoring and alerting setup

### Production Ready
- **🛡️ High Availability** - Replicated services with auto-scaling
- **💾 Persistent Storage** - StatefulSets for databases with backup strategies
- **🔐 Security** - RBAC, secrets management, and network policies
- **📈 Scalability** - Horizontal pod autoscaling based on metrics

---

## 🏗️ Infrastructure

### Technology Stack

| Layer | Technology |
|-------|-----------|
| **Orchestration** | Kubernetes (Kind for local, EKS/GKE for cloud) |
| **Package Manager** | Helm 3 |
| **Container Runtime** | Docker with BuildKit |
| **CI/CD** | GitHub Actions (dev/staging), Jenkins (production) |
| **Database** | MongoDB 7.0 |
| **Cache** | Redis 7.2 |
| **ML Framework** | PyTorch, Scikit-learn |
| **API Framework** | FastAPI |
| **Monitoring** | Prometheus + Grafana (optional) |

### Kubernetes Architecture

```yaml
Namespaces:
  - data              # Production workloads
  - data-dev          # Development environment  
  - data-staging      # Staging environment

Services:
  - dota2-fetcher     # Data ingestion service
  - dota2-trainer     # ML training jobs
  - dota2-api         # REST API service
  - mongodb           # Primary database
  - redis             # Caching layer
  - jupyter           # Analysis notebooks (dev only)
```

---

## 📦 Deployment

### Environments

| Environment | Branch | Namespace | Trigger | Approval |
|-------------|--------|-----------|---------|----------|
| **Development** | `dev` | `data-dev` | Auto on push | ❌ None |
| **Staging** | `staging` | `data-staging` | Auto on push | ❌ None |
| **Production** | `main` | `data` | Jenkins | ✅ Manual |

### Deployment Status

- **Dev:** ![Dev Status](https://img.shields.io/badge/dev-active-success)
- **Staging:** ![Staging Status](https://img.shields.io/badge/staging-active-success)
- **Production:** ![Production Status](https://img.shields.io/badge/production-stable-blue)

### Quick Deploy

#### Using GitHub Actions (Dev/Staging)
```bash
# Deploy to dev
git push origin dev

# Deploy to staging
git push origin staging
```

#### Using Jenkins (Production)
```bash
# Trigger via push to main
git push origin main

# Or manually via Jenkins UI
# Requires manual approval before deployment
```

#### Manual Helm Deployment
```bash
# Deploy to specific environment
helm upgrade --install dota2-meta-lab-dev ./deploy/helm \
  -f ./deploy/helm/values-dev.yaml \
  --set image.tag=dev-latest \
  -n data-dev \
  --create-namespace

# Check deployment status
kubectl get pods -n data-dev
kubectl get svc -n data-dev
```

---

## 🛠️ Local Development

### Prerequisites

- Docker Desktop or Kind
- kubectl
- Helm 3
- Python 3.11+
- Git

### Setup Local Kubernetes Cluster

```bash
# Create Kind cluster with custom config
kind create cluster --config=infra/kind-config.yaml --name=dota2-dev

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

### Deploy to Local Cluster

```bash
# Clone repository
git clone https://github.com/rinavillaruz/dota2-meta-lab.git
cd dota2-meta-lab

# Deploy with Helm
helm install dota2-meta-lab ./deploy/helm \
  -f ./deploy/helm/values-dev.yaml \
  -n data-dev \
  --create-namespace

# Wait for pods to be ready
kubectl wait --for=condition=ready pod \
  -l app=dota2-meta-lab \
  -n data-dev \
  --timeout=300s

# Check deployment
kubectl get all -n data-dev
```

### Access Services Locally

```bash
# API Service (if using NodePort)
curl http://localhost:30080/health

# Jupyter Notebook (dev only)
kubectl port-forward svc/jupyter 8888:8888 -n data-dev
# Open: http://localhost:8888

# MongoDB (for debugging)
kubectl port-forward svc/mongodb 27017:27017 -n data-dev

# Redis (for debugging)
kubectl port-forward svc/redis 6379:6379 -n data-dev
```

---

## 🔧 Configuration

### Environment Variables

Create a `.env` file for local development:

```bash
# API Configuration
API_HOST=0.0.0.0
API_PORT=8000
LOG_LEVEL=INFO

# Database
MONGODB_URI=mongodb://mongodb:27017
MONGODB_DATABASE=dota2_meta_lab

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Dota 2 API
STEAM_API_KEY=your_steam_api_key_here
OPENDOTA_API_KEY=your_opendota_key_here

# ML Training
MODEL_PATH=/models
MLFLOW_TRACKING_URI=http://mlflow:5000
```

### Kubernetes Secrets

```bash
# Create MongoDB credentials
kubectl create secret generic mongodb-secret \
  --from-literal=username=admin \
  --from-literal=password=your-secure-password \
  -n data-dev

# Create Docker registry credentials (for private images)
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=docker.io \
  --docker-username=your-username \
  --docker-password=your-token \
  -n data-dev
```

---

## 📊 Monitoring & Observability

### Slack Notifications

The platform sends automated notifications to Slack:

| Channel | Purpose | Trigger |
|---------|---------|---------|
| `#github-deployments` | Dev/Staging deployments | GitHub Actions |
| `#jenkins-builds` | Production builds | Jenkins CI |

Notifications include:
- ✅ Deployment status (success/failure)
- ⏱️ Build duration
- 🏷️ Image tags (current & previous)
- 🔄 Rollback commands
- 📊 Monitoring dashboard links
- 👤 Author and commit information

### Health Checks

```bash
# API health endpoint
curl http://api-service:8000/health

# MongoDB connection
kubectl exec -it mongodb-0 -n data-dev -- mongosh --eval "db.adminCommand('ping')"

# Redis connection
kubectl exec -it redis-0 -n data-dev -- redis-cli ping
```

### Logs

```bash
# View API logs
kubectl logs -f deployment/dota2-api -n data-dev

# View fetcher logs
kubectl logs -f deployment/dota2-fetcher -n data-dev

# View all logs in namespace
kubectl logs -f -l app=dota2-meta-lab -n data-dev --all-containers
```

---

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow (Dev/Staging)

**Triggers:** Push to `dev` or `staging` branches

**Pipeline Steps:**
1. 🔍 Checkout code
2. 🔐 Docker Hub login
3. 🐳 Build multi-stage Docker images (parallel)
   - Data Fetcher
   - ML Trainer
   - API Service
4. 📤 Push images with version tags + `:latest`
5. ⚓ Deploy to Kubernetes with Helm
6. 📢 Send Slack notification

**Image Tagging Strategy:**
```
Format: {env}-{run_number}-{git_sha}
Example: dev-42-a3f9c2d1
Also tagged as: dev-latest
```

### Jenkins Pipeline (Production)

**Triggers:** Push to `main` branch

**Pipeline Steps:**
1. 📦 Initialize build metadata
2. 🔔 Notify build start
3. 📥 Checkout code
4. 🧪 Run tests (pytest, flake8)
5. 🔐 Docker Hub login
6. 🐳 Build images (parallel)
7. 📤 Push with version + `:latest` tags
8. ⏸️ **Manual approval required**
9. 🚀 Deploy to production
10. ✅ Verify deployment
11. 📢 Send success/failure notification

---

## 🔐 Security

### Best Practices Implemented

- ✅ **Secrets Management** - Using Kubernetes Secrets, never in code
- ✅ **RBAC** - Role-based access control for service accounts
- ✅ **Network Policies** - Restricted pod-to-pod communication
- ✅ **Image Scanning** - Vulnerability scanning in CI/CD
- ✅ **Non-root Containers** - Running as non-privileged users
- ✅ **Resource Limits** - Memory and CPU constraints
- ✅ **TLS/SSL** - Encrypted communication (production)

### Security Checklist

```bash
# Scan Docker images for vulnerabilities
docker scan rinavillaruz/dota2-api:latest

# Check pod security policies
kubectl get psp

# Audit RBAC permissions
kubectl auth can-i --list --as=system:serviceaccount:data-dev:default

# Review secrets (never expose values!)
kubectl get secrets -n data-dev
```

---

## 🧪 Testing

### Run Tests Locally

```bash
# Install dependencies
pip install -r build/requirements.txt
pip install -r build/requirements-dev.txt

# Run unit tests
pytest tests/unit/ -v

# Run integration tests
pytest tests/integration/ -v

# Run with coverage
pytest --cov=src --cov-report=html

# Linting
flake8 src/
black src/ --check
mypy src/
```

### Test in Kubernetes

```bash
# Deploy test environment
helm install dota2-test ./deploy/helm \
  -f ./deploy/helm/values-dev.yaml \
  --set image.tag=test \
  -n data-test \
  --create-namespace

# Run integration tests against cluster
pytest tests/integration/ --kube-context=kind-dota2-dev
```

---

## 📚 Documentation

### API Documentation

Once deployed, API documentation is available at:
- **Swagger UI:** `http://api-service:8000/docs`
- **ReDoc:** `http://api-service:8000/redoc`

### Project Structure

```
dota2-meta-lab/
│
├── 📂 argocd-apps/              # ArgoCD Application manifests for GitOps
│   ├── dota2-dev.yaml           # Dev environment ArgoCD app
│   ├── dota2-staging.yaml       # Staging environment ArgoCD app
│   └── dota2-prod.yaml          # Production environment ArgoCD app
│
├── 📂 build/                    # Docker build context and dependencies
│   ├── Dockerfile               # Production multi-stage Dockerfile
│   ├── Dockerfile.dev           # Development optimized Dockerfile
│   ├── Dockerfile.jupyter       # Jupyter notebook environment
│   ├── requirements.txt         # Python production dependencies
│   └── .dockerignore           # Docker build exclusions
│
├── 📂 ci/                       # Continuous Integration configuration
│   └── Jenkinsfile             # Jenkins pipeline definition (production)
│
├── 📂 cli/                      # Command-line automation scripts
│   ├── setup-complete-cicd.sh  # Complete CI/CD infrastructure setup
│   ├── install-jenkins.sh      # Jenkins installation to K8s
│   ├── install-argocd.sh       # ArgoCD installation to K8s
│   ├── uninstall-argocd.sh     # ArgoCD cleanup
│   ├── argocd-login.sh         # ArgoCD authentication helper
│   ├── deploy-with-helm.sh     # Direct Helm deployment
│   ├── deploy-with-argocd.sh   # GitOps deployment via ArgoCD
│   ├── setup-secrets.sh        # Kubernetes secrets provisioning
│   ├── destroy-cluster.sh      # Cluster teardown and cleanup
│   └── debug.sh                # Troubleshooting utilities
│
├── 📂 deploy/                   # Deployment configurations
│   └── helm/                   # Helm chart for Kubernetes deployment
│       ├── Chart.yaml          # Helm chart metadata
│       ├── values.yaml         # Default configuration values
│       ├── values-dev.yaml     # Development overrides
│       ├── values-staging.yaml # Staging overrides
│       ├── values-production.yaml # Production overrides
│       ├── .helmignore         # Helm packaging exclusions
│       │
│       └── templates/          # Kubernetes resource templates
│           ├── _helpers.tpl               # Template helper functions
│           ├── storage-class.yaml         # Dynamic storage provisioner
│           ├── pvc-models.yaml            # Persistent volume for ML models
│           ├── pvc-ml-training.yaml       # Training data storage
│           ├── mongodb-statefulset.yaml   # MongoDB database cluster
│           ├── mongodb-service.yaml       # MongoDB service endpoint
│           ├── redis-deployment.yaml      # Redis cache deployment
│           ├── redis-service.yaml         # Redis service endpoint
│           ├── ml-api-deployment.yaml     # FastAPI inference service
│           ├── ml-api-service.yaml        # API service endpoint
│           ├── ml-training-job.yaml       # Kubernetes Job for ML training
│           └── jupyter.yaml               # Jupyter notebook for analysis
│
├── 📂 jenkins-k8s/              # Jenkins Kubernetes deployment (Kustomize)
│   ├── Dockerfile              # Custom Jenkins image with plugins
│   ├── base/                   # Base Kustomize configuration
│   │   ├── 00-namespace.yaml         # Jenkins namespace
│   │   ├── 01-serviceaccount.yaml    # Jenkins service account
│   │   ├── 02-clusterrole.yaml       # Jenkins permissions
│   │   ├── 03-clusterrolebinding.yaml # Role binding
│   │   ├── 04-pvc.yaml               # Jenkins data persistence
│   │   ├── 05-configmap.yaml         # Jenkins configuration
│   │   ├── 06-deployment.yaml        # Jenkins controller
│   │   ├── 07-rbac.yaml              # Additional RBAC rules
│   │   ├── 08-service.yaml           # Jenkins service
│   │   └── 08-init-configmap.yaml    # Jenkins initialization
│   │
│   └── overlays/               # Environment-specific customizations
│       └── dev/                # Development overlay
│
├── 📂 k8s/                      # Kubernetes cluster configurations
│   ├── ha/                     # High-availability cluster config
│   │   └── kind-ha-cluster.yaml     # Kind HA cluster definition
│   │
│   └── dev-tools/              # Development utilities
│       └── jupyter.yaml        # Standalone Jupyter deployment
│
├── 📂 scripts/                  # Python data pipeline scripts
│   ├── fetch_data.py           # Dota 2 API data fetcher
│   ├── analyze_data.py         # Data analysis and preprocessing
│   ├── train_model.py          # ML model training script
│   └── store_database.py       # Database storage utilities
│
├── 📂 src/                      # Application source code
│   ├── api/                    # FastAPI REST API
│   │   ├── __init__.py
│   │   └── app.py              # FastAPI application entry point
│   │
│   ├── data/                   # Data ingestion modules
│   │   ├── __init__.py
│   │   ├── data_loader.py      # Data loading utilities
│   │   └── open_dota_fetcher.py # OpenDota API client
│   │
│   ├── models/                 # Machine learning models
│   │   ├── __init__.py
│   │   ├── dota2_model.py      # ML model implementation
│   │   └── feature_engineering.py # Feature extraction
│   │
│   └── utils/                  # Shared utilities
│       ├── config.py           # Configuration management
│       └── logger.py           # Logging utilities
│
└── 📄 README.md                 # Project documentation
```

---

## 🤝 Contributing

### Development Workflow

1. **Create feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes and test locally**
   ```bash
   # Run tests
   pytest
   
   # Check code style
   black src/
   flake8 src/
   ```

3. **Commit with conventional commits**
   ```bash
   git commit -m "feat: add hero win rate prediction endpoint"
   ```

4. **Push and create PR to `dev` branch**
   ```bash
   git push origin feature/your-feature-name
   ```

5. **After review, merge to `dev`** → Auto-deploys to dev environment

6. **When stable, merge `dev` → `staging`** → Auto-deploys to staging

7. **After validation, merge `staging` → `main`** → Triggers production build (manual approval required)

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```bash
feat(api): add hero matchup prediction endpoint
fix(fetcher): handle rate limit errors gracefully
docs: update deployment instructions for production
chore(deps): upgrade FastAPI to 0.104.0
```

---

## 🗺️ Roadmap

### Current (Q1 2026)
- ✅ Core MLOps platform
- ✅ Multi-environment deployments
- ✅ Automated CI/CD pipelines
- ✅ Slack notifications

### Next (Q2 2026)
- 🔄 Model versioning with MLflow
- 🔄 A/B testing framework
- 🔄 Advanced monitoring (Prometheus + Grafana)
- 🔄 Automated model retraining

### Future (Q3-Q4 2026)
- 📊 Real-time prediction dashboard
- 🎮 In-game prediction API
- 🧠 Advanced hero recommendation system
- 📈 Meta trend analysis and forecasting
- 🌐 Public API with rate limiting

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👥 Team

**Maintainer:** Rina Villaruz ([@rinavillaruz](https://github.com/rinavillaruz))

---

## 🙏 Acknowledgments

- OpenDota API for Dota 2 match data
- Kubernetes community for excellent documentation
- Helm community for chart best practices
- FastAPI for the amazing web framework

---

## 📞 Support

- 🐛 **Bug Reports:** [GitHub Issues](https://github.com/rinavillaruz/dota2-meta-lab/issues)
- 💬 **Discussions:** [GitHub Discussions](https://github.com/rinavillaruz/dota2-meta-lab/discussions)

---

<div align="center">

**Built with ❤️ for the Dota 2 community**

⭐ Star this repo if you find it useful!

</div>