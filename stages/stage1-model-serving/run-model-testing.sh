#!/bin/bash
set -euo pipefail

##############################################################################
# Run Model Testing Pipeline
# 
# Starts the Tekton testing pipeline to run lm-eval benchmarks
# against a deployed InferenceService and publish results to Model Registry.
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

Runs the model testing pipeline against a deployed InferenceService.

Options:
  quantized  - Test quantized model (must be READY)
  full       - Test full precision model (must be READY)

Examples:
  $0 quantized    # Test quantized model
  $0 full         # Test full precision model

Prerequisites:
  - InferenceService must be READY
  - Testing pipeline must be deployed

The pipeline will:
  1. Run lm-eval (evaluation benchmarks)
  2. Publish results to Model Registry

Check results in Model Registry dashboard after completion.

EOF
  exit 1
}

[ $# -eq 0 ] && usage

MODEL_TYPE="$1"

case "$MODEL_TYPE" in
  quantized)
    PIPELINERUN_FILE="../../gitops/stage01-model-serving/serving/pipelines/active/03-pipelineruns/pipelinerun-test-mistral-quantized-v2.yaml"
    MODEL_NAME="Mistral 24B Quantized"
    ISVC_NAME="mistral-24b-quantized"
    PIPELINE_NAME="model-testing-v2"
    ;;
  full)
    PIPELINERUN_FILE="../../gitops/stage01-model-serving/serving/pipelines/active/03-pipelineruns/pipelinerun-test-mistral-full-v2.yaml"
    MODEL_NAME="Mistral 24B Full"
    ISVC_NAME="mistral-24b"
    PIPELINE_NAME="model-testing-v2"
    ;;
  *)
    echo -e "${RED}Error: Invalid model type '$MODEL_TYPE'${NC}"
    echo ""
    usage
    ;;
esac

echo "═══════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}Starting Model Testing Pipeline${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "Model: ${GREEN}$MODEL_NAME${NC}"
echo "InferenceService: $ISVC_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Check if InferenceService is ready
echo "Checking InferenceService status..."
ISVC_READY=$(oc get isvc "$ISVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")

if [ "$ISVC_READY" != "True" ]; then
  echo -e "${RED}Error: InferenceService '$ISVC_NAME' is not READY${NC}"
  echo ""
  echo "Current status:"
  oc get isvc "$ISVC_NAME" -n "$NAMESPACE" 2>/dev/null || echo "InferenceService not found"
  echo ""
  exit 1
fi

echo -e "${GREEN}✓ InferenceService is READY${NC}"
echo ""

# Check if pipeline exists
echo "Checking testing pipeline..."
if ! oc get pipeline "$PIPELINE_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo -e "${RED}Error: Testing pipeline not deployed${NC}"
  echo ""
  echo "Deploy it first:"
  echo -e "  ${YELLOW}oc apply -k gitops/stage01-model-serving/serving/pipelines${NC}"
  echo ""
  exit 1
fi

echo -e "${GREEN}✓ Testing pipeline ($PIPELINE_NAME) is deployed${NC}"
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
echo -e "${GREEN}✓ Testing pipeline started: $PR_NAME${NC}"
echo ""
echo "───────────────────────────────────────────────────────────────────────────────"
echo "Pipeline Tasks:"
echo "───────────────────────────────────────────────────────────────────────────────"
echo ""
echo "  1. run-lm-eval       - Language model evaluation (hellaswag)"
echo "  2. publish-results   - Upload results to Model Registry"
echo ""
echo "Expected duration: ~10-15 minutes (100 samples)"
echo ""
echo "───────────────────────────────────────────────────────────────────────────────"
echo "Monitoring:"
echo "───────────────────────────────────────────────────────────────────────────────"
echo ""
echo "Watch pipeline status:"
echo -e "  ${YELLOW}oc get pipelinerun $PR_NAME -n $NAMESPACE -w${NC}"
echo ""
echo "Stream logs:"
echo -e "  ${YELLOW}tkn pipelinerun logs $PR_NAME -n $NAMESPACE -f${NC}"
echo ""
echo "Check results after completion:"
echo "  • Model Registry dashboard"
echo "  • Custom properties for the model version"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

