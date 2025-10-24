#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 2: Model Alignment with RAG + Llama Stack
#
# Deploys:
#   - Milvus vector database
#   - Llama Stack orchestrator (connects to vLLM + Milvus)
#   - Docling + Granite embedding model
#   - Tekton document ingestion pipelines (3 use cases)
#   - RAG demonstration notebooks
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_PATH="../gitops-new/stage02-model-alignment"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2: Model Alignment with RAG + Llama Stack"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "📦 Deploying from: $GITOPS_PATH"
oc apply -k "$GITOPS_PATH"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  ./validate.sh              - Check deployment status"
echo "  tkn pr list                - View pipeline runs"
echo "  oc logs -f <pipeline-pod>  - Monitor document ingestion"
