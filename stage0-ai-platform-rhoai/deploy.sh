#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 0: AI Platform - RHOAI
#
# Deploys:
#   - OpenShift AI operator (2.24)
#   - DataScienceCluster CR (enable Model Registry)
#   - GPU Operator
#   - GPU MachineSets (g6.4xlarge, g6.12xlarge)
#   - Model Registry + MySQL
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_PATH="../gitops-new/stage00-ai-platform-rhoai"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 0: AI Platform - RHOAI"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "📦 Deploying from: $GITOPS_PATH"
oc apply -k "$GITOPS_PATH"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  ./validate.sh                        - Check deployment status"
echo "  oc get datasciencecluster            - Verify RHOAI installation"
echo "  oc get machinesets -n openshift-machine-api  - Check GPU nodes"
