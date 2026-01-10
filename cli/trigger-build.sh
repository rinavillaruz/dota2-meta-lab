#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
JENKINS_URL="http://localhost:30808"
JENKINS_USER="admin"
JOB_NAME="dota2-meta-lab"

# Get parameters
ENVIRONMENT=${1:-dev}
RUN_TESTS=${2:-false}

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    echo -e "${RED}❌ Invalid environment: $ENVIRONMENT${NC}"
    echo "Usage: $0 [dev|staging|production] [true|false]"
    exit 1
fi

echo "🚀 Triggering Jenkins Build"
echo "============================"
echo "Environment: $ENVIRONMENT"
echo "Run Tests: $RUN_TESTS"
echo ""

# Get Jenkins password
echo "Getting Jenkins credentials..."
JENKINS_PASSWORD=$(kubectl get secret jenkins-admin-credentials -n jenkins -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$JENKINS_PASSWORD" ]; then
    echo -e "${RED}❌ Could not retrieve Jenkins password${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Credentials retrieved${NC}"

# Get crumb using JSON API
echo "Getting CSRF token..."
CRUMB_JSON=$(curl -s "${JENKINS_URL}/crumbIssuer/api/json" \
  --user "${JENKINS_USER}:${JENKINS_PASSWORD}")

CRUMB_FIELD=$(echo "$CRUMB_JSON" | grep -o '"crumbRequestField":"[^"]*"' | cut -d'"' -f4)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)

if [ -z "$CRUMB_FIELD" ] || [ -z "$CRUMB_VALUE" ]; then
    echo -e "${RED}❌ Could not retrieve CSRF token${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Token retrieved${NC}"
echo ""

# Trigger build with proper headers
echo "Triggering build..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "${JENKINS_URL}/job/${JOB_NAME}/buildWithParameters" \
  --user "${JENKINS_USER}:${JENKINS_PASSWORD}" \
  -H "${CRUMB_FIELD}: ${CRUMB_VALUE}" \
  --data-urlencode "ENVIRONMENT=${ENVIRONMENT}" \
  --data-urlencode "RUN_TESTS=${RUN_TESTS}")

# Check if successful
if [ "$HTTP_CODE" = "201" ]; then
    echo -e "${GREEN}✅ Build triggered successfully!${NC}"
    echo ""
    
    # Wait for build to start
    sleep 3
    
    # Get last build number
    BUILD_NUMBER=$(curl -s "${JENKINS_URL}/job/${JOB_NAME}/lastBuild/buildNumber" \
      --user "${JENKINS_USER}:${JENKINS_PASSWORD}")
    
    if [ -n "$BUILD_NUMBER" ]; then
        echo -e "${BLUE}📊 Build #${BUILD_NUMBER} started${NC}"
        echo ""
        echo "View in Jenkins:"
        echo "  ${JENKINS_URL}/job/${JOB_NAME}/${BUILD_NUMBER}/"
        echo ""
        echo "Console output:"
        echo "  ${JENKINS_URL}/job/${JOB_NAME}/${BUILD_NUMBER}/console"
    fi
elif [ "$HTTP_CODE" = "403" ]; then
    echo -e "${RED}❌ Build trigger failed (HTTP 403 - Forbidden)${NC}"
    echo ""
    echo "Let's try disabling CSRF protection..."
    echo "Run this command to disable CSRF:"
    echo ""
    echo "  kubectl exec -n jenkins \$(kubectl get pods -n jenkins -l app=jenkins -o name) -- \\"
    echo "    java -jar /var/jenkins_home/war/WEB-INF/jenkins-cli.jar -s http://localhost:8080/ \\"
    echo "    groovy = <<< 'Jenkins.instance.setCrumbIssuer(null)'"
    echo ""
    echo "Or use Jenkins UI: ${JENKINS_URL}/job/${JOB_NAME}/"
    exit 1
else
    echo -e "${RED}❌ Build trigger failed (HTTP ${HTTP_CODE})${NC}"
    exit 1
fi