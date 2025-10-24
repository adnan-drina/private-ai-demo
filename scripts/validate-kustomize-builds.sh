#!/bin/bash
set -euo pipefail

##############################################################################
# Kustomize Build Validation Script
#
# Validates that all GitOps manifests build correctly without errors
# Run this before deploying to catch configuration issues early
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

test_build() {
    local path=$1
    local name=$2
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -n "  Testing: $name ... "
    if oc kustomize "$path" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "    Error building: $path"
        oc kustomize "$path" 2>&1 | head -5 | sed 's/^/    /'
        return 1
    fi
}

test_yaml() {
    local file=$1
    local name=$2
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -n "  Testing: $name ... "
    if oc apply --dry-run=client -f "$file" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "    Error in: $file"
        return 1
    fi
}

echo "════════════════════════════════════════════════════════════════"
echo "  Kustomize Build Validation"
echo "════════════════════════════════════════════════════════════════"
echo ""

cd "$PROJECT_ROOT"

# Stage 0
echo "📦 Stage 0: AI Platform - RHOAI"
echo "  ⚠️  Stage 0 GitOps not yet implemented (manual setup required)"
echo ""

# Stage 1
echo "📦 Stage 1: Model Serving"
test_build "gitops-new/stage01-model-serving" "Stage 1 (main)"
test_build "gitops-new/stage01-model-serving/base-namespace" "  ├─ base-namespace"
test_build "gitops-new/stage01-model-serving/base-secrets" "  ├─ base-secrets"
test_build "gitops-new/stage01-model-serving/vllm" "  ├─ vllm"
test_build "gitops-new/stage01-model-serving/model-loader" "  ├─ model-loader"
test_build "gitops-new/stage01-model-serving/minio" "  ├─ minio"
test_build "gitops-new/stage01-model-serving/benchmarking" "  ├─ benchmarking"
test_build "gitops-new/stage01-model-serving/workbench" "  └─ workbench"
echo ""

# Stage 2
echo "📦 Stage 2: Model Alignment"
test_build "gitops-new/stage02-model-alignment" "Stage 2 (main)"
test_build "gitops-new/stage02-model-alignment/milvus" "  ├─ milvus"
test_build "gitops-new/stage02-model-alignment/llama-stack" "  ├─ llama-stack"
test_build "gitops-new/stage02-model-alignment/docling" "  ├─ docling"
test_build "gitops-new/stage02-model-alignment/pipelines" "  ├─ pipelines"
test_build "gitops-new/stage02-model-alignment/notebooks" "  └─ notebooks"
echo ""

# Stage 3
echo "📦 Stage 3: Model Monitoring"
test_build "gitops-new/stage03-model-monitoring" "Stage 3 (main)"
test_build "gitops-new/stage03-model-monitoring/trustyai" "  ├─ trustyai"
test_build "gitops-new/stage03-model-monitoring/observability" "  ├─ observability"
test_build "gitops-new/stage03-model-monitoring/notebooks" "  └─ notebooks"
echo ""

# Stage 4
echo "📦 Stage 4: Model Integration"
test_build "gitops-new/stage04-model-integration" "Stage 4 (main)"
test_build "gitops-new/stage04-model-integration/postgresql" "  ├─ postgresql"
test_build "gitops-new/stage04-model-integration/mcp-servers" "  ├─ mcp-servers"
test_build "gitops-new/stage04-model-integration/acme-agent" "  ├─ acme-agent"
test_build "gitops-new/stage04-model-integration/notebooks" "  └─ notebooks"
echo ""

# ArgoCD
echo "📦 ArgoCD Applications & Projects"
for app in gitops-new/argocd/applications/*/app-*.yaml; do
    if [ -f "$app" ]; then
        test_yaml "$app" "$(basename $app)"
    fi
done

for proj in gitops-new/argocd/projects/appproject-*.yaml; do
    if [ -f "$proj" ]; then
        test_yaml "$proj" "$(basename $proj)"
    fi
done
echo ""

# Summary
echo "════════════════════════════════════════════════════════════════"
echo "  Validation Summary"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    echo ""
    echo "❌ Validation FAILED! Please fix the errors above."
    exit 1
else
    echo -e "${GREEN}Failed: 0${NC}"
    echo ""
    echo "✅ All Kustomize builds passed!"
    echo ""
    echo "Next steps:"
    echo "  1. Review: docs/VALIDATION-PLAN.md"
    echo "  2. Deploy to test environment"
    echo "  3. Run live validation for each stage"
fi

