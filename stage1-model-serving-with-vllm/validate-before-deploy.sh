#!/bin/bash

##############################################################################
# Stage 1: Pre-Deployment Validation Script
# 
# This script validates that all prerequisites are met before deploying Stage 1
# Run this before executing deploy.sh to catch issues early
#
# Usage: ./validate-before-deploy.sh
##############################################################################

set +e  # Don't exit on error, we want to report all issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GITOPS_DIR="${PROJECT_ROOT}/gitops"

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

print_header "Stage 1: Pre-Deployment Validation"

echo ""
log_info "Validating prerequisites before deployment..."
echo ""

# Check 1: CLI Tools
print_header "Check 1: CLI Tools"

check "  oc CLI installed" "command -v oc"
check "  oc CLI logged in" "oc whoami"
check "  Admin access (can create MachineSets)" \
    "oc auth can-i create machineset -n openshift-machine-api"

# Check 2: OpenShift AI
print_header "Check 2: OpenShift AI Platform"

check "  DataScienceCluster exists" "oc get datasciencecluster"
check "  KServe installed" "oc get crd inferenceservices.serving.kserve.io"
check "  ServiceMesh installed" "oc get crd servicemeshcontrolplanes.maistra.io"

# Check 3: NVIDIA GPU Operator
print_header "Check 3: NVIDIA GPU Operator"

check "  GPU Operator namespace exists" "oc get namespace nvidia-gpu-operator"
check "  GPU Operator CSV found" "oc get csv -n nvidia-gpu-operator"

# Check 4: GitOps Structure
print_header "Check 4: GitOps Structure"

check "  Base namespace configuration" "[ -d ${GITOPS_DIR}/base/namespace ]"
check "  Base vLLM configuration" "[ -d ${GITOPS_DIR}/base/vllm ]"
check "  GPU provisioning component" "[ -d ${GITOPS_DIR}/components/gpu-provisioning ]"
check "  Model loader component" "[ -d ${GITOPS_DIR}/components/model-loader ]"
check "  Benchmarking component" "[ -d ${GITOPS_DIR}/components/benchmarking ]"
check "  Model Registry infrastructure" "[ -d ${GITOPS_DIR}/components/model-registry-infrastructure ]"
check "  Model Registry operator" "[ -d ${GITOPS_DIR}/components/model-registry-operator ]"

# Check 5: Required Files
print_header "Check 5: Required Files"

check "  deploy.sh exists" "[ -f ${SCRIPT_DIR}/deploy.sh ]"
check "  deploy.sh is executable" "[ -x ${SCRIPT_DIR}/deploy.sh ]"
check "  cleanup.sh exists" "[ -f ${SCRIPT_DIR}/cleanup.sh ]"
check "  cleanup.sh is executable" "[ -x ${SCRIPT_DIR}/cleanup.sh ]"
check "  env.template exists" "[ -f ${SCRIPT_DIR}/env.template ]"

# Check 6: HuggingFace Token
print_header "Check 6: HuggingFace Token"

if [ -f "${SCRIPT_DIR}/.env" ]; then
    if grep -q "HF_TOKEN=" "${SCRIPT_DIR}/.env" 2>/dev/null; then
        log_success "  .env file with HF_TOKEN found"
    else
        log_warn "  .env file exists but HF_TOKEN not found"
        log_info "    deploy.sh will prompt for token"
    fi
else
    log_warn "  .env file not found (deploy.sh will prompt)"
fi

# Check 7: Cluster Resources
print_header "Check 7: Cluster Resources"

# Check if GPU nodes already exist
GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)
if [ "$GPU_NODES" -gt 0 ]; then
    log_info "  Found $GPU_NODES existing GPU nodes"
else
    log_info "  No GPU nodes found (will be provisioned by deploy.sh)"
fi

# Check if namespace already exists
if oc get namespace private-ai-demo &>/dev/null; then
    log_warn "  private-ai-demo namespace already exists"
    log_info "    Run cleanup.sh first for clean deployment"
else
    log_success "  private-ai-demo namespace does not exist (good)"
fi

# Check 8: AWS Credentials (if using AWS)
print_header "Check 8: Cloud Provider Configuration"

PLATFORM=$(oc get infrastructure cluster -o jsonpath='{.status.platform}' 2>/dev/null || echo "unknown")
log_info "  Platform: $PLATFORM"

if [ "$PLATFORM" = "AWS" ]; then
    # Check if we can get cluster info
    if oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' &>/dev/null; then
        log_success "  Can access cluster infrastructure details"
    else
        log_fail "  Cannot access cluster infrastructure details"
    fi
    
    # Check if MachineSet template exists
    EXISTING_MS=$(oc get machineset -n openshift-machine-api --no-headers 2>/dev/null | head -1 | awk '{print $1}')
    if [ -n "$EXISTING_MS" ]; then
        log_success "  Existing MachineSets found (can use as template)"
    else
        log_warn "  No existing MachineSets found"
    fi
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
    echo -e "${GREEN}✅ All critical checks passed!${NC}"
    echo ""
    echo "You can proceed with deployment:"
    echo "  cd stage1-sovereign-ai"
    echo "  ./deploy.sh"
    echo ""
    exit 0
else
    echo -e "${RED}❌ $FAILED critical checks failed!${NC}"
    echo ""
    echo "Please fix the issues above before deploying."
    echo ""
    
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}Note: $WARNINGS warnings found (non-critical)${NC}"
        echo ""
    fi
    
    exit 1
fi

