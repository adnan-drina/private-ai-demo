#!/bin/bash

##############################################################################
# Stage 1: Post-Deployment Validation Script
# 
# This script validates that Stage 1 deployed successfully
# Run this after executing deploy.sh to verify the deployment
#
# Usage: ./validate-after-deploy.sh
##############################################################################

set +e  # Don't exit on error, we want to report all issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="private-ai-demo"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS=0
PASSED=0
FAILED=0
WARNINGS=0

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}✗${NC} $1"; ((FAILED++)); }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; ((WARNINGS++)); }

check() {
    ((CHECKS++))
    local description="$1"
    local command="$2"
    
    if eval "$command" &>/dev/null; then
        log_success "$description"
        return 0
    else
        log_fail "$description"
        return 1
    fi
}

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
}

print_header "Stage 1: Post-Deployment Validation"

echo ""
log_info "Validating Stage 1 deployment..."
echo ""

# Check 1: Namespace
print_header "Check 1: Namespace"

check "  private-ai-demo namespace exists" "oc get namespace $NAMESPACE"

# Check 2: GPU Nodes
print_header "Check 2: GPU Nodes"

GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)
((CHECKS++))
if [ "$GPU_NODES" -ge 2 ]; then
    log_success "  GPU nodes: $GPU_NODES nodes ready"
    ((PASSED++))
else
    log_fail "  GPU nodes: Only $GPU_NODES found (expected 2+)"
    ((FAILED++))
fi

# Check specific GPU node types
check "  g6.4xlarge node exists" \
    "oc get nodes -l node.kubernetes.io/instance-type=g6.4xlarge --no-headers | grep -q ."
check "  g6.12xlarge node exists" \
    "oc get nodes -l node.kubernetes.io/instance-type=g6.12xlarge --no-headers | grep -q ."

# Check 3: InferenceServices
print_header "Check 3: InferenceServices"

check "  mistral-24b InferenceService exists" \
    "oc get inferenceservice mistral-24b -n $NAMESPACE"
check "  mistral-24b-quantized InferenceService exists" \
    "oc get inferenceservice mistral-24b-quantized -n $NAMESPACE"

# Check InferenceServices are READY
READY_IS=$(oc get inferenceservice -n $NAMESPACE -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
TOTAL_IS=$(oc get inferenceservice -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
((CHECKS++))
if [ "$READY_IS" -eq "$TOTAL_IS" ] && [ "$TOTAL_IS" -gt 0 ]; then
    log_success "  InferenceServices READY: $READY_IS/$TOTAL_IS"
    ((PASSED++))
else
    log_fail "  InferenceServices READY: $READY_IS/$TOTAL_IS"
    ((FAILED++))
fi

# Check 4: Model Downloads
print_header "Check 4: Model Downloads"

check "  download-mistral-24b job exists" \
    "oc get job download-mistral-24b -n $NAMESPACE"
check "  download-mistral-24b-quantized job exists" \
    "oc get job download-mistral-24b-quantized -n $NAMESPACE"

# Check if jobs completed
COMPLETED_JOBS=$(oc get jobs -n $NAMESPACE -o jsonpath='{range .items[?(@.metadata.name=="download-mistral-24b")]}{.status.conditions[?(@.type=="Complete")].status}{end}' 2>/dev/null)
((CHECKS++))
if [ "$COMPLETED_JOBS" = "True" ]; then
    log_success "  download-mistral-24b job completed"
    ((PASSED++))
else
    log_warn "  download-mistral-24b job may not be complete"
    ((WARNINGS++))
fi

# Check 5: PVCs
print_header "Check 5: Persistent Volume Claims"

check "  mistral-24b-pvc exists and bound" \
    "oc get pvc mistral-24b-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q Bound"
check "  mistral-24b-quantized-pvc exists and bound" \
    "oc get pvc mistral-24b-quantized-pvc -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q Bound"

# Check 6: Routes/URLs
print_header "Check 6: Routes and URLs"

QUANTIZED_URL=$(oc get inferenceservice mistral-24b-quantized -n $NAMESPACE -o jsonpath='{.status.url}' 2>/dev/null)
FULL_URL=$(oc get inferenceservice mistral-24b -n $NAMESPACE -o jsonpath='{.status.url}' 2>/dev/null)

((CHECKS++))
if [ -n "$QUANTIZED_URL" ]; then
    log_success "  Quantized model URL: $QUANTIZED_URL"
    ((PASSED++))
else
    log_fail "  Quantized model URL not found"
    ((FAILED++))
fi

((CHECKS++))
if [ -n "$FULL_URL" ]; then
    log_success "  Full model URL: $FULL_URL"
    ((PASSED++))
else
    log_fail "  Full model URL not found"
    ((FAILED++))
fi

# Check 7: Benchmarks
print_header "Check 7: Benchmarks"

if oc get job vllm-model-benchmark -n $NAMESPACE &>/dev/null; then
    check "  Benchmark job exists" "true"
    
    BENCH_STATUS=$(oc get job vllm-model-benchmark -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    ((CHECKS++))
    if [ "$BENCH_STATUS" = "True" ]; then
        log_success "  Benchmark job completed"
        ((PASSED++))
    else
        log_warn "  Benchmark job may not be complete"
        ((WARNINGS++))
    fi
else
    log_warn "  Benchmark job not found (may not have been run)"
    ((WARNINGS++))
fi

# Check 8: Model Registry (Optional)
print_header "Check 8: Model Registry (Optional)"

if oc get namespace model-registry &>/dev/null; then
    log_info "  Model Registry detected, checking..."
    
    check "    MySQL deployment exists" \
        "oc get deployment mysql -n model-registry"
    check "    ModelRegistry CR exists" \
        "oc get modelregistry -n model-registry"
    check "    Model Registry route exists" \
        "oc get route -n model-registry"
    
    if oc get job register-models -n $NAMESPACE &>/dev/null; then
        check "    Model registration job exists" "true"
    else
        log_warn "    Model registration job not found"
        ((WARNINGS++))
    fi
else
    log_info "  Model Registry not deployed (optional component)"
fi

# Check 9: Pod Health
print_header "Check 9: Pod Health"

# Check for any CrashLoopBackOff pods
CRASH_PODS=$(oc get pods -n $NAMESPACE --field-selector=status.phase==Failed 2>/dev/null | grep -v "NAME" | wc -l)
((CHECKS++))
if [ "$CRASH_PODS" -eq 0 ]; then
    log_success "  No failed pods"
    ((PASSED++))
else
    log_fail "  Found $CRASH_PODS failed pods"
    ((FAILED++))
fi

# Summary
print_header "Validation Summary"

echo ""
echo "  Total Checks: $CHECKS"
echo "  Passed: ${GREEN}$PASSED${NC}"
echo "  Failed: ${RED}$FAILED${NC}"
echo "  Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ Stage 1 deployment is healthy!${NC}"
    echo ""
    
    if [ -n "$QUANTIZED_URL" ]; then
        echo "Quantized Model: $QUANTIZED_URL"
    fi
    if [ -n "$FULL_URL" ]; then
        echo "Full Model: $FULL_URL"
    fi
    
    echo ""
    echo "Next steps:"
    echo "  • Test inference endpoints"
    echo "  • View benchmark results: oc logs job/vllm-model-benchmark -n $NAMESPACE"
    echo "  • Deploy Stage 2: cd ../stage2-private-data-rag && ./deploy.sh"
    echo ""
    exit 0
else
    echo -e "${RED}❌ $FAILED checks failed!${NC}"
    echo ""
    echo "Please investigate the issues above."
    echo ""
    
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}Note: $WARNINGS warnings found (non-critical)${NC}"
        echo ""
    fi
    
    echo "Troubleshooting:"
    echo "  • Check pod logs: oc logs <pod-name> -n $NAMESPACE"
    echo "  • Check events: oc get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    echo "  • Check InferenceServices: oc describe inferenceservice -n $NAMESPACE"
    echo ""
    exit 1
fi

