#!/bin/bash

##############################################################################
# Stage 2 Cleanup Script
# 
# This script removes all Stage 2 components while preserving Stage 1.
# It handles stuck resources and namespace termination issues.
#
# What it removes:
#   - Llama Stack distribution
#   - Workbench (JupyterLab)
#   - Tekton pipelines, tasks, and runs
#   - Milvus vector database
#   - Docling operator and service
#   - ai-infrastructure namespace
#
# What it preserves:
#   - Stage 1 vLLM models
#   - Model Registry
#   - GPU nodes and MachineSets
#   - private-ai-demo namespace (used by Stage 1)
##############################################################################

set -e

# Namespaces
NAMESPACE="private-ai-demo"
INFRA_NAMESPACE="ai-infrastructure"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

echo "══════════════════════════════════════════════════════════════"
echo "  Stage 2 Cleanup - Preserve Stage 1"
echo "══════════════════════════════════════════════════════════════"
echo ""

log_warning "This will remove all Stage 2 components (RAG infrastructure)"
log_info "Stage 1 components (vLLM models, Model Registry) will be preserved"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

#============================================================================
# Stage 2 Components in private-ai-demo namespace
#============================================================================

echo ""
log_info "Removing Stage 2 components from $NAMESPACE namespace..."

# Remove Workbench
log_info "Deleting JupyterLab Workbench..."
oc delete notebook --all -n $NAMESPACE --ignore-not-found=true --wait=false
oc delete pvc -l app=rag-testing -n $NAMESPACE --ignore-not-found=true

# Remove Llama Stack
log_info "Deleting Llama Stack distribution..."
oc delete llamastackdistribution --all -n $NAMESPACE --ignore-not-found=true --wait=false
oc delete pvc -l app=llama-stack -n $NAMESPACE --ignore-not-found=true
oc delete configmap llamastack-config -n $NAMESPACE --ignore-not-found=true

# Remove Tekton Pipelines
log_info "Deleting Tekton pipelines and runs..."
oc delete pipelinerun --all -n $NAMESPACE --ignore-not-found=true --wait=false
oc delete pipeline --all -n $NAMESPACE --ignore-not-found=true
oc delete task --all -n $NAMESPACE --ignore-not-found=true
oc delete pvc rag-documents -n $NAMESPACE --ignore-not-found=true

log_success "Stage 2 components removed from $NAMESPACE"

#============================================================================
# Shared Infrastructure Namespace
#============================================================================

if oc get namespace $INFRA_NAMESPACE &> /dev/null; then
    echo ""
    log_info "Removing shared infrastructure namespace: $INFRA_NAMESPACE..."
    
    # Delete Milvus
    log_info "Deleting Milvus vector database..."
    oc delete deployment milvus-standalone -n $INFRA_NAMESPACE --ignore-not-found=true --wait=false
    oc delete service milvus-standalone -n $INFRA_NAMESPACE --ignore-not-found=true
    oc delete pvc milvus-pvc -n $INFRA_NAMESPACE --ignore-not-found=true
    
    # Delete Docling
    log_info "Deleting Docling service..."
    oc delete doclingserve --all -n $INFRA_NAMESPACE --ignore-not-found=true --wait=false
    oc delete deployment shared-docling-service -n $INFRA_NAMESPACE --ignore-not-found=true --wait=false
    oc delete service shared-docling-service -n $INFRA_NAMESPACE --ignore-not-found=true
    
    # Delete namespace
    log_info "Deleting $INFRA_NAMESPACE namespace..."
    oc delete namespace $INFRA_NAMESPACE --wait=false &> /dev/null || true
    
    # Monitor namespace deletion (with timeout)
    log_info "Waiting for namespace deletion (max 60 seconds)..."
    TIMEOUT=60
    ELAPSED=0
    while oc get namespace $INFRA_NAMESPACE &> /dev/null; do
        if [ $ELAPSED -ge $TIMEOUT ]; then
            log_warning "Namespace deletion taking longer than expected"
            log_info "Checking for stuck resources..."
            
            # Remove finalizers from stuck resources
            for resource_type in deployment pvc service doclingserve; do
                RESOURCES=$(oc get $resource_type -n $INFRA_NAMESPACE -o name 2>/dev/null || true)
                if [ ! -z "$RESOURCES" ]; then
                    log_info "Removing finalizers from $resource_type..."
                    echo "$RESOURCES" | while read resource; do
                        oc patch $resource -n $INFRA_NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                    done
                fi
            done
            
            # Remove namespace finalizers
            log_info "Removing namespace finalizers..."
            oc patch namespace $INFRA_NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    
    if ! oc get namespace $INFRA_NAMESPACE &> /dev/null; then
        log_success "$INFRA_NAMESPACE namespace deleted"
    else
        log_warning "$INFRA_NAMESPACE namespace may still be terminating"
        log_info "Check status with: oc get namespace $INFRA_NAMESPACE"
    fi
else
    log_info "$INFRA_NAMESPACE namespace not found (already deleted)"
fi

#============================================================================
# Verify Stage 1 Still Intact
#============================================================================

echo ""
log_info "Verifying Stage 1 components are still intact..."

# Check vLLM models
if oc get inferenceservice mistral-24b-quantized -n $NAMESPACE &> /dev/null; then
    log_success "✓ vLLM models preserved"
else
    log_warning "⚠ vLLM models not found (may have been deployed separately)"
fi

# Check Model Registry
if oc get modelregistry private-ai-model-registry -n rhoai-model-registries &> /dev/null 2>&1; then
    log_success "✓ Model Registry preserved"
else
    log_info "ℹ Model Registry not found (optional)"
fi

# Check namespace
if oc get namespace $NAMESPACE &> /dev/null; then
    log_success "✓ $NAMESPACE namespace preserved"
fi

#============================================================================
# Cleanup Complete
#============================================================================

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ Stage 2 Cleanup Complete!"
echo "══════════════════════════════════════════════════════════════"
echo ""

log_success "Stage 2 components removed:"
echo "  ✓ Llama Stack distribution"
echo "  ✓ JupyterLab Workbench"
echo "  ✓ Tekton pipelines"
echo "  ✓ Milvus vector database"
echo "  ✓ Docling service"
echo "  ✓ ai-infrastructure namespace"
echo ""

log_success "Stage 1 components preserved:"
echo "  ✓ vLLM inference services"
echo "  ✓ Model Registry (if deployed)"
echo "  ✓ GPU nodes"
echo "  ✓ private-ai-demo namespace"
echo ""

log_info "To redeploy Stage 2:"
echo "  cd stage2-private-data-rag"
echo "  ./deploy.sh"
echo ""

log_info "To cleanup Stage 1 as well:"
echo "  cd ../stage1-sovereign-ai"
echo "  ./cleanup.sh"
echo ""
