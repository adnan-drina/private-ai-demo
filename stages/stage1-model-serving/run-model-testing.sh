#!/bin/bash
set -euo pipefail

##############################################################################
# Run Model Testing Pipeline
# 
# Starts the Tekton testing pipeline to run lm-eval and GuideLLM benchmarks
# against a deployed InferenceService.
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
  quantized  - Test quantized model (must be deployed)
  full       - Test full precision model (must be deployed)

Examples:
  $0 quantized    # Test quantized model
  $0 full         # Test full precision model

Prerequisites:
  - InferenceService must be READY
  - Testing pipeline v2 must be deployed

The pipeline will:
  1. Run lm-eval (perplexity, accuracy metrics)
  2. Run GuideLLM benchmarks (TTFT, throughput, latency)
  3. Publish results to Model Registry

Results can be checked with:
  ./check-testing-results.sh

EOF
  exit 1
}

[ $# -eq 0 ] && usage

MODEL_TYPE="$1"

case "$MODEL_TYPE" in
  quantized)
    PIPELINERUN_FILE="gitops/stage01-model-serving/serving/pipelines/active/03-pipelineruns/pipelinerun-test-mistral-quantized-v2.yaml"
    MODEL_NAME="Mistral 24B Quantized"
    ISVC_NAME="mistral-24b-quantized"
    ;;
  full)
    PIPELINERUN_FILE="gitops/stage01-model-serving/serving/pipelines/active/03-pipelineruns/pipelinerun-test-mistral-full-v2.yaml"
    MODEL_NAME="Mistral 24B Full"
    ISVC_NAME="mistral-24b"
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
echo "  1. run-lm-eval       - Language model evaluation (perplexity, accuracy)"
echo "  2. run-guidellm      - Performance benchmarks (TTFT, throughput, latency)"
echo "  3. publish-results   - Upload results to Model Registry"
echo ""
echo "Expected duration: ~15-30 minutes"
echo ""
echo "───────────────────────────────────────────────────────────────────────────────"
echo "Monitoring Options:"
echo "───────────────────────────────────────────────────────────────────────────────"
echo ""
echo "1. Watch all PipelineRuns:"
echo -e "   ${YELLOW}oc get pipelineruns -n $NAMESPACE -w${NC}"
echo ""
echo "2. Stream logs with tkn CLI:"
echo -e "   ${YELLOW}tkn pipelinerun logs $PR_NAME -n $NAMESPACE -f${NC}"
echo ""
echo "3. Check status:"
echo -e "   ${YELLOW}oc get pipelinerun $PR_NAME -n $NAMESPACE${NC}"
echo ""
echo "4. Check results after completion:"
echo -e "   ${YELLOW}./check-testing-results.sh${NC}"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

