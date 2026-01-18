#!/bin/bash
set -e  # Exit on errors

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔄 Restarting development environment..."
echo ""

# Stop (keep data)
"$SCRIPT_DIR/stop-dev-k8s.sh" <<< "N"

echo ""
echo "Waiting 5 seconds..."
sleep 5

# Start
"$SCRIPT_DIR/start-dev-k8s.sh"

echo ""
echo "✅ Environment restarted!"