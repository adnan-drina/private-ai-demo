#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 1: Model Serving - Validation Script
# 
# Validates the deployment of Stage 1 components:
# - InferenceServices (vLLM)
# - Model Registry integration
# - MinIO storage
# - Tekton pipelines
##############################################################################

NAMESPACE="private-ai-demo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}Stage 1: Model Serving - Validation${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Function to check component status
check_component() {
  local name="$1"
  local command="$2"
  echo -n "Checking $name... "
  if eval "$command" &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    return 0
  else
    echo -e "${RED}✗${NC}"
    return 1
  fi
}

FAILURES=0

# ============================================================================
# 1. Namespace
# ============================================================================
echo -e "${YELLOW}1. Namespace${NC}"
if check_component "private-ai-demo namespace" "oc get project $NAMESPACE"; then
  echo ""
else
  echo -e "   ${RED}Namespace not found - run ./deploy.sh first${NC}"
  echo ""
  exit 1
fi

# ============================================================================
# 2. InferenceServices
# ============================================================================
echo -e "${YELLOW}2. InferenceServices${NC}"
echo ""

QUANT_READY=$(oc get isvc mistral-24b-quantized -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
FULL_READY=$(oc get isvc mistral-24b -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")

echo -n "  • Quantized model (1×L4, S3): "
if [ "$QUANT_READY" = "True" ]; then
  echo -e "${GREEN}READY${NC}"
  QUANT_URL=$(oc get isvc mistral-24b-quantized -n "$NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null)
  echo "    URL: $QUANT_URL"
else
  echo -e "${RED}NOT READY ($QUANT_READY)${NC}"
  FAILURES=$((FAILURES + 1))
fi

echo ""
echo -n "  • Full model (4×L4, PVC): "
if [ "$FULL_READY" = "True" ]; then
  echo -e "${GREEN}READY${NC}"
  FULL_URL=$(oc get isvc mistral-24b -n "$NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null)
  echo "    URL: $FULL_URL"
else
  echo -e "${RED}NOT READY ($FULL_READY)${NC}"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# ============================================================================
# 3. Model Storage
# ============================================================================
echo -e "${YELLOW}3. Model Storage${NC}"
echo ""

# Check MinIO
echo -n "  • MinIO (model-storage ns): "
if oc get deployment minio -n model-storage &>/dev/null; then
  MINIO_READY=$(oc get deployment minio -n model-storage -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  echo -e "${GREEN}READY ($MINIO_READY replica)${NC}"
else
  echo -e "${RED}NOT FOUND${NC}"
  FAILURES=$((FAILURES + 1))
fi

# Check PVC for full model
echo -n "  • PVC for full model: "
if oc get pvc mistral-24b-pvc -n "$NAMESPACE" &>/dev/null; then
  PVC_STATUS=$(oc get pvc mistral-24b-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
  PVC_SIZE=$(oc get pvc mistral-24b-pvc -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
  if [ "$PVC_STATUS" = "Bound" ]; then
    echo -e "${GREEN}Bound ($PVC_SIZE)${NC}"
  else
    echo -e "${YELLOW}$PVC_STATUS${NC}"
  fi
else
  echo -e "${RED}NOT FOUND${NC}"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# ============================================================================
# 4. Model Registry
# ============================================================================
echo -e "${YELLOW}4. Model Registry${NC}"
echo ""

echo -n "  • Model Registry: "
if oc get modelregistry private-ai-model-registry -n rhoai-model-registries &>/dev/null; then
  MR_STATUS=$(oc get modelregistry private-ai-model-registry -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
  if [ "$MR_STATUS" = "True" ]; then
    echo -e "${GREEN}Available${NC}"
  else
    echo -e "${YELLOW}$MR_STATUS${NC}"
  fi
else
  echo -e "${RED}NOT FOUND${NC}"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# ============================================================================
# 5. Tekton Pipelines
# ============================================================================
echo -e "${YELLOW}5. Tekton Pipelines${NC}"
echo ""

echo -n "  • model-import pipeline: "
if oc get pipeline model-import -n "$NAMESPACE" &>/dev/null; then
  echo -e "${GREEN}Deployed${NC}"
else
  echo -e "${RED}NOT FOUND${NC}"
  FAILURES=$((FAILURES + 1))
fi

echo -n "  • model-testing-v2 pipeline: "
if oc get pipeline model-testing-v2 -n "$NAMESPACE" &>/dev/null; then
  echo -e "${GREEN}Deployed${NC}"
else
  echo -e "${YELLOW}NOT FOUND (optional)${NC}"
fi

# Check latest PipelineRuns
LATEST_QUANT_PR=$(oc get pipelinerun -n "$NAMESPACE" -l model=mistral-quantized --sort-by=.metadata.creationTimestamp -o name 2>/dev/null | tail -1 | cut -d/ -f2)
LATEST_FULL_PR=$(oc get pipelinerun -n "$NAMESPACE" -l model=mistral-full --sort-by=.metadata.creationTimestamp -o name 2>/dev/null | tail -1 | cut -d/ -f2)

if [ -n "$LATEST_QUANT_PR" ]; then
  QUANT_PR_STATUS=$(oc get pipelinerun "$LATEST_QUANT_PR" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
  echo "    • Latest quantized import: $LATEST_QUANT_PR ($QUANT_PR_STATUS)"
fi

if [ -n "$LATEST_FULL_PR" ]; then
  FULL_PR_STATUS=$(oc get pipelinerun "$LATEST_FULL_PR" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null)
  echo "    • Latest full import: $LATEST_FULL_PR ($FULL_PR_STATUS)"
fi
echo ""

# ============================================================================
# 6. GPU Resources
# ============================================================================
echo -e "${YELLOW}6. GPU Resources${NC}"
echo ""

GPU_USED=$(oc get resourcequota ai-workload-quota -n "$NAMESPACE" -o jsonpath='{.status.used.requests\.nvidia\.com/gpu}' 2>/dev/null || echo "0")
GPU_LIMIT=$(oc get resourcequota ai-workload-quota -n "$NAMESPACE" -o jsonpath='{.spec.hard.requests\.nvidia\.com/gpu}' 2>/dev/null || echo "8")

echo "  • GPU Quota: $GPU_USED / $GPU_LIMIT used"
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "═══════════════════════════════════════════════════════════════════════════════"
if [ $FAILURES -eq 0 ]; then
  echo -e "${GREEN}✓ Validation Successful${NC}"
  echo ""
  echo "Stage 1 is deployed and ready!"
  echo ""
  echo "Next steps:"
  echo "  • Test endpoints:"
  echo "    curl $QUANT_URL/v1/models"
  echo "    curl $FULL_URL/v1/models"
  echo ""
  echo "  • Run testing pipeline:"
  echo "    ./run-model-testing.sh [quantized|full]"
  echo ""
  exit 0
else
  echo -e "${RED}✗ Validation Failed ($FAILURES issues)${NC}"
  echo ""
  echo "Please review the errors above and run ./deploy.sh if needed."
  echo ""
  exit 1
fi

