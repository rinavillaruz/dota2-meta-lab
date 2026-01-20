#!/bin/bash
# expose-k8s-with-ngrok.sh
# This script exposes your Kubernetes API server via ngrok

set -e

echo "🔍 Finding your Kubernetes API server..."

# Get the API server endpoint from your current context
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "Current API server: $API_SERVER"

# Extract the port (usually 6443 for Kind, or 6444)
if [[ $API_SERVER == *"127.0.0.1:6444"* ]]; then
    PORT="6444"
elif [[ $API_SERVER == *"127.0.0.1:6443"* ]]; then
    PORT="6443"
else
    echo "⚠️  Unexpected API server format: $API_SERVER"
    read -p "Enter the port number: " PORT
fi

echo "📡 Port detected: $PORT"

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "❌ ngrok not found. Installing..."
    
    # Download and install ngrok
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | \
        sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null && \
        echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | \
        sudo tee /etc/apt/sources.list.d/ngrok.list && \
        sudo apt update && sudo apt install ngrok
    
    echo "✅ ngrok installed"
fi

# Check if ngrok is authenticated
if ! ngrok config check &> /dev/null; then
    echo ""
    echo "⚠️  ngrok is not authenticated!"
    echo "Please get your authtoken from: https://dashboard.ngrok.com/get-started/your-authtoken"
    read -p "Enter your ngrok authtoken: " NGROK_TOKEN
    ngrok config add-authtoken $NGROK_TOKEN
fi

echo ""
echo "🚀 Starting ngrok tunnel..."
echo "================================"
echo "This will expose: localhost:$PORT"
echo "Press Ctrl+C to stop the tunnel"
echo "================================"
echo ""

# Start ngrok (this will run in foreground)
ngrok tcp $PORT