#!/bin/bash
# generate-github-kubeconfig-v2.sh
# Creates a kubeconfig file for GitHub Actions using ngrok URL

set -e

echo "🔐 Creating kubeconfig for GitHub Actions..."

# Find the project root (where .git directory is)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$PROJECT_ROOT" ]; then
    echo "⚠️  Not in a git repository. Using current directory as project root."
    PROJECT_ROOT=$(pwd)
fi

# Define config directory relative to project root
CONFIG_DIR="$PROJECT_ROOT/config"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"
echo "📁 Config directory: config/"

# Get ngrok URL
echo ""
echo "First, start ngrok in another terminal:"
echo "  ./cli/expose-k8s-with-ngrok.sh"
echo ""
read -p "Enter your ngrok URL (e.g., tcp://0.tcp.ngrok.io:12345): " NGROK_URL

# Extract host and port from ngrok URL
if [[ $NGROK_URL =~ tcp://([^:]+):([0-9]+) ]]; then
    NGROK_HOST="${BASH_REMATCH[1]}"
    NGROK_PORT="${BASH_REMATCH[2]}"
    NGROK_HTTPS="https://$NGROK_HOST:$NGROK_PORT"
else
    echo "❌ Invalid ngrok URL format"
    echo "Expected format: tcp://0.tcp.ngrok.io:12345"
    exit 1
fi

echo "📡 Using ngrok endpoint: $NGROK_HTTPS"

# Apply the RBAC configuration from YAML file
echo "📝 Creating service account and permissions..."
RBAC_FILE="$PROJECT_ROOT/k8s/github-actions-rbac.yaml"

if [ -f "$RBAC_FILE" ]; then
    kubectl apply -f "$RBAC_FILE"
    echo "✅ Applied k8s/github-actions-rbac.yaml"
elif [ -f "$PROJECT_ROOT/github-actions-rbac.yaml" ]; then
    kubectl apply -f "$PROJECT_ROOT/github-actions-rbac.yaml"
    echo "✅ Applied github-actions-rbac.yaml"
else
    echo "❌ github-actions-rbac.yaml not found!"
    echo "Please make sure it's in k8s/github-actions-rbac.yaml or project root"
    exit 1
fi

# Wait for token to be generated
echo "⏳ Waiting for token to be generated..."
sleep 3

# Get the service account token
echo "🎫 Retrieving service account token..."
SA_TOKEN=$(kubectl get secret github-actions-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)

if [ -z "$SA_TOKEN" ]; then
    echo "❌ Failed to retrieve token. Waiting a bit longer..."
    sleep 5
    SA_TOKEN=$(kubectl get secret github-actions-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
fi

# Get the cluster CA certificate
echo "🔐 Retrieving cluster certificate..."
CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Define output file path
KUBECONFIG_FILE="$CONFIG_DIR/github-actions-kubeconfig.yaml"

# Generate the kubeconfig
echo "📄 Generating kubeconfig..."
cat > "$KUBECONFIG_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CA_CERT
    server: $NGROK_HTTPS
  name: ngrok-cluster
contexts:
- context:
    cluster: ngrok-cluster
    user: github-actions
  name: github-actions-context
current-context: github-actions-context
users:
- name: github-actions
  user:
    token: $SA_TOKEN
EOF

echo ""
echo "✅ Kubeconfig created: config/github-actions-kubeconfig.yaml"
echo ""
echo "📋 Next steps:"
echo "1. Encode the kubeconfig to base64:"
echo "   cat config/github-actions-kubeconfig.yaml | base64 -w 0"
echo ""
echo "2. Add it as a GitHub secret:"
echo "   - Go to: GitHub Repo → Settings → Secrets → Actions"
echo "   - Name: KUBECONFIG"
echo "   - Value: <paste the base64 output>"
echo ""
echo "⚠️  IMPORTANT: Keep ngrok running during deployments!"
echo "   The ngrok URL in this config: $NGROK_HTTPS"
echo ""
echo "🧪 Test the kubeconfig locally (optional):"
echo "   export KUBECONFIG=config/github-actions-kubeconfig.yaml"
echo "   kubectl get nodes"
echo "   unset KUBECONFIG  # to reset back to default"