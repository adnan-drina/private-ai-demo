#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 4: Model Integration with MCP + Llama Stack
#
# Deploys:
#   - PostgreSQL database (equipment metadata)
#   - MCP Servers (database-mcp, slack-mcp)
#   - ACME Agent (Quarkus app) with Llama Stack integration
#   - Agent demonstration notebook
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_PATH="../gitops-new/stage04-model-integration"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 4: Model Integration with MCP + Llama Stack"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "📦 Deploying from: $GITOPS_PATH"
oc apply -k "$GITOPS_PATH"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  ./validate.sh                     - Check deployment status"
echo "  oc get route acme-agent           - Access ACME Agent UI"
echo "  curl <acme-agent>/api/calibrate   - Test agent endpoint"
