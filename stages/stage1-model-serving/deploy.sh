#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 1: Model Serving with vLLM
#
# Deploys:
#   - Namespace & Secrets (HuggingFace token)
#   - vLLM Runtime + InferenceServices (2 Mistral models)
#   - Model download jobs
#   - MinIO storage
#   - GuideLLM benchmarks + Model Registry integration
#   - Benchmark results notebook
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_PATH="../gitops-new/stage01-model-serving"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 1: Model Serving with vLLM"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "📦 Deploying from: $GITOPS_PATH"
oc apply -k "$GITOPS_PATH"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  ./validate.sh              - Check deployment status"
echo "  oc get inferenceservice    - View model endpoints"
