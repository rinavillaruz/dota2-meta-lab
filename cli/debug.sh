#!/bin/bash

echo "🔍 Checking Jenkins Secrets Setup"
echo "=================================="
echo ""

# Check if secrets exist
echo "1. Checking if secrets exist in jenkins namespace:"
echo ""

if kubectl get secret dockerhub-credentials -n jenkins &>/dev/null; then
    echo "✅ dockerhub-credentials exists"
    echo "   Keys:"
    kubectl get secret dockerhub-credentials -n jenkins -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || kubectl get secret dockerhub-credentials -n jenkins -o jsonpath='{.data}' | grep -o '"[^"]*"' | tr -d '"' | head -10
else
    echo "❌ dockerhub-credentials NOT FOUND"
fi
echo ""

if kubectl get secret jenkins-slack-webhook -n jenkins &>/dev/null; then
    echo "✅ jenkins-slack-webhook exists"
    echo "   Keys:"
    kubectl get secret jenkins-slack-webhook -n jenkins -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || kubectl get secret jenkins-slack-webhook -n jenkins -o jsonpath='{.data}' | grep -o '"[^"]*"' | tr -d '"' | head -10
else
    echo "❌ jenkins-slack-webhook NOT FOUND"
fi
echo ""

# Check if Jenkins pod is running
echo "2. Checking Jenkins pod:"
JENKINS_POD=$(kubectl get pod -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$JENKINS_POD" ]; then
    echo "✅ Jenkins pod: $JENKINS_POD"
    echo ""
    
    # Check if files are mounted
    echo "3. Checking if secret files are mounted in pod:"
    echo ""
    
    echo "Checking /run/secrets/dockerhub/:"
    if kubectl exec -n jenkins $JENKINS_POD -- ls -la /run/secrets/dockerhub/ 2>/dev/null; then
        echo "✅ dockerhub secrets mounted"
    else
        echo "❌ dockerhub secrets NOT mounted"
    fi
    echo ""
    
    echo "Checking /run/secrets/slack/:"
    if kubectl exec -n jenkins $JENKINS_POD -- ls -la /run/secrets/slack/ 2>/dev/null; then
        echo "✅ slack secrets mounted"
    else
        echo "❌ slack secrets NOT mounted"
    fi
    echo ""
    
    # Try to read the actual values
    echo "4. Testing secret file contents:"
    echo ""
    
    echo "Docker username:"
    kubectl exec -n jenkins $JENKINS_POD -- cat /run/secrets/dockerhub/username 2>/dev/null || echo "❌ Cannot read"
    echo ""
    
    echo "Slack webhook:"
    kubectl exec -n jenkins $JENKINS_POD -- cat /run/secrets/slack/webhook-url 2>/dev/null || echo "❌ Cannot read"
    echo ""
else
    echo "❌ No Jenkins pod found"
fi

echo "=================================="
echo "🏁 Verification Complete"