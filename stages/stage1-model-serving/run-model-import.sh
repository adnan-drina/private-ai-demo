#!/bin/bash
set -euo pipefail

##############################################################################
# Run Model Import Pipeline
# 
# Starts the Tekton pipeline to download a model from HuggingFace,
# upload to MinIO, build runtime image, and register in Model Registry.
##############################################################################

NAMESPACE="private-ai-demo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
  cat << EOF
Usage: $0 [quantized|full]

Runs the model import pipeline for Mistral 24B model.

Options:
  quantized  - Run pipeline for quantized model (W4A16, ~20GB)
  full       - Run pipeline for full precision model (FP16, ~48GB)

Examples:
  $0 quantized    # Import quantized model
  $0 full         # Import full precision model

The pipeline will:
  1. Download model from HuggingFace
  2. Upload to MinIO S3 storage
  3. Build vLLM runtime image and push to Quay.io
  4. Register model in Model Registry

EOF
  exit 1
}

[ $# -eq 0 ] && usage

MODEL_TYPE="$1"

case "$MODEL_TYPE" in
  quantized)
    PIPELINERUN_FILE="gitops/stage01-model-serving/serving/pipelines/active/03-pipelineruns/pipelinerun-mistral-quantized.yaml"
    MODEL_NAME="Mistral 24B Quantized (W4A16)"
    ;;
  full)
    PIPELINERUN_FILE="gitops/stage01-model-serving/serving/pipelines/active/03-pipelineruns/pipelinerun-mistral-full.yaml"
    MODEL_NAME="Mistral 24B Full Precision (FP16)"
    ;;
  *)
    echo -e "${RED}Error: Invalid model type '$MODEL_TYPE'${NC}"
    echo ""
    usage
    ;;
esac

echo "═══════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}Starting Model Import Pipeline${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "Model: ${GREEN}$MODEL_NAME${NC}"
echo "Namespace: $NAMESPACE"
echo ""

# Check if file exists
if [ ! -f "$PIPELINERUN_FILE" ]; then
  echo -e "${RED}Error: PipelineRun file not found: $PIPELINERUN_FILE${NC}"
  exit 1
fi

# Create the PipelineRun
echo "Creating PipelineRun..."
oc create -f "$PIPELINERUN_FILE" -n "$NAMESPACE"

# Get the PipelineRun name
PR_NAME=$(oc get pipelinerun -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d/ -f2)

echo ""
echo -e "${GREEN}✓ Pipeline started: $PR_NAME${NC}"
echo ""
echo "───────────────────────────────────────────────────────────────────────────────"
echo "Monitoring Options:"
echo "───────────────────────────────────────────────────────────────────────────────"
echo ""
echo "1. Use the monitoring script:"
echo -e "   ${YELLOW}./monitor-pipeline.sh -n $NAMESPACE -r $PR_NAME${NC}"
echo ""
echo "2. Watch all PipelineRuns:"
echo -e "   ${YELLOW}oc get pipelineruns -n $NAMESPACE -w${NC}"
echo ""
echo "3. Stream logs with tkn CLI:"
echo -e "   ${YELLOW}tkn pipelinerun logs $PR_NAME -n $NAMESPACE -f${NC}"
echo ""
echo "4. Check status:"
echo -e "   ${YELLOW}oc get pipelinerun $PR_NAME -n $NAMESPACE${NC}"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Offer to start monitoring
read -p "Start monitoring now? [Y/n] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
  echo ""
  exec ./monitor-pipeline.sh -n "$NAMESPACE" -r "$PR_NAME"
fi

