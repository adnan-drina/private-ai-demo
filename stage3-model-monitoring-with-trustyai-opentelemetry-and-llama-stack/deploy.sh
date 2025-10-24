#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 3: Model Monitoring with TrustyAI + OpenTelemetry + Llama Stack
#
# Deploys:
#   - TrustyAI LMEvalJobs (model quality evaluation)
#   - Grafana dashboards (performance + quality metrics)
#   - Prometheus ServiceMonitors (vLLM + Llama Stack)
#   - OpenTelemetry Collector
#   - Evaluation results notebook
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_PATH="../gitops-new/stage03-model-monitoring"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 3: Model Monitoring"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "📦 Deploying from: $GITOPS_PATH"
oc apply -k "$GITOPS_PATH"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  ./validate.sh                    - Check deployment status"
echo "  oc get lmevaljob                 - View evaluation jobs"
echo "  oc get route grafana-route       - Access Grafana dashboard"
