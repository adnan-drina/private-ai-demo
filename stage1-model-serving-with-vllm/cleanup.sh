#!/bin/bash

##############################################################################
# Red Hat AI Demo - Stage 1 Cleanup Script
# 
# This script removes all Stage 1 resources to prepare for clean redeployment
#
# WARNING: This will delete:
# - private-ai-demo namespace (all InferenceServices, PVCs, Jobs)
# - GPU MachineSets (removes GPU nodes)
# - MachineConfigs
# - MachineConfigPool
##############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
}

# Function to remove finalizers from stuck resources
remove_finalizers() {
    local namespace=$1
    
    log_info "Checking for resources with finalizers in namespace: $namespace"
    
    # Remove finalizers from InferenceServices (modelregistry.opendatahub.io/finalizer)
    if oc get inferenceservices -n $namespace &>/dev/null; then
        STUCK_ISVCS=$(oc get inferenceservices -n $namespace -o name 2>/dev/null)
        if [ -n "$STUCK_ISVCS" ]; then
            log_info "Removing finalizers from InferenceServices..."
            echo "$STUCK_ISVCS" | while read isvc; do
                oc patch $isvc -n $namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            done
            log_success "InferenceService finalizers removed"
        fi
    fi
    
    # Remove finalizers from PVCs (kubernetes.io/pvc-protection)
    if oc get pvc -n $namespace &>/dev/null; then
        STUCK_PVCS=$(oc get pvc -n $namespace -o name 2>/dev/null | grep -v "Terminating" || true)
        if [ -n "$STUCK_PVCS" ]; then
            log_info "Removing finalizers from PVCs..."
            echo "$STUCK_PVCS" | while read pvc; do
                oc patch $pvc -n $namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            done
            log_success "PVC finalizers removed"
        fi
    fi
    
    # Remove finalizers from Pods
    STUCK_PODS=$(oc get pods -n $namespace -o name 2>/dev/null | grep -v "Terminating" || true)
    if [ -n "$STUCK_PODS" ]; then
        log_info "Force deleting stuck pods..."
        echo "$STUCK_PODS" | while read pod; do
            oc delete $pod -n $namespace --force --grace-period=0 2>/dev/null || true
        done
        log_success "Stuck pods deleted"
    fi
}

# Function to check if namespace is stuck and force deletion
force_namespace_deletion() {
    local namespace=$1
    local max_wait=60  # Wait up to 60 seconds
    local elapsed=0
    
    while oc get namespace $namespace &> /dev/null; do
        # Check if namespace is stuck in Terminating
        PHASE=$(oc get namespace $namespace -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [ "$PHASE" = "Terminating" ]; then
            log_warning "Namespace stuck in Terminating status. Checking for finalizers..."
            
            # Check for resources with finalizers
            REMAINING=$(oc get namespace $namespace -o jsonpath='{.status.conditions[?(@.type=="NamespaceContentRemaining")].message}' 2>/dev/null)
            FINALIZERS=$(oc get namespace $namespace -o jsonpath='{.status.conditions[?(@.type=="NamespaceFinalizersRemaining")].message}' 2>/dev/null)
            
            if [ -n "$REMAINING" ]; then
                log_info "Remaining resources: $REMAINING"
            fi
            
            if [ -n "$FINALIZERS" ]; then
                log_info "Finalizers blocking deletion: $FINALIZERS"
            fi
            
            # Remove finalizers from stuck resources
            remove_finalizers $namespace
            
            # Give resources a moment to finish deleting
            sleep 5
            
            # If still stuck, remove namespace finalizers
            if oc get namespace $namespace -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Terminating"; then
                log_warning "Removing finalizers from namespace itself..."
                oc patch namespace $namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                log_success "Namespace finalizers removed"
                sleep 3
            fi
        fi
        
        # Check if we've exceeded max wait time
        if [ $elapsed -ge $max_wait ]; then
            log_warning "Namespace still exists after ${max_wait}s, but finalizers have been removed"
            break
        fi
        
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo ""
}

print_header "Red Hat AI Demo - Stage 1 Cleanup"

log_warning "This will DELETE all Stage 1 resources:"
echo "  • private-ai-demo namespace"
echo "  • All InferenceServices and pods"
echo "  • All PVCs and models"
echo "  • GPU MachineSets (VMs will be terminated)"
echo "  • MachineConfigs"
echo "  • MachineConfigPool"
echo ""

read -p "Are you sure you want to proceed? (yes/NO): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

# Step 1: Delete namespace
print_header "Step 1: Deleting Namespace"

if oc get namespace private-ai-demo &> /dev/null; then
    log_info "Deleting private-ai-demo namespace..."
    oc delete namespace private-ai-demo --wait=false
    log_success "Namespace deletion initiated"
    
    log_info "Monitoring namespace deletion (auto-removing finalizers if stuck)..."
    force_namespace_deletion private-ai-demo
    
    if oc get namespace private-ai-demo &> /dev/null; then
        log_warning "Namespace still exists but should finish deleting shortly"
    else
        log_success "Namespace removed"
    fi
else
    log_info "Namespace private-ai-demo not found (already deleted)"
fi

# Step 2: Delete GPU MachineSets
print_header "Step 2: Deleting GPU MachineSets"

if oc get machineset g6-4xlarge-gpu -n openshift-machine-api &> /dev/null; then
    log_info "Deleting g6-4xlarge-gpu MachineSet..."
    oc delete machineset g6-4xlarge-gpu -n openshift-machine-api
    log_success "g6-4xlarge-gpu MachineSet deleted"
else
    log_info "g6-4xlarge-gpu MachineSet not found"
fi

if oc get machineset g6-12xlarge-gpu -n openshift-machine-api &> /dev/null; then
    log_info "Deleting g6-12xlarge-gpu MachineSet..."
    oc delete machineset g6-12xlarge-gpu -n openshift-machine-api
    log_success "g6-12xlarge-gpu MachineSet deleted"
else
    log_info "g6-12xlarge-gpu MachineSet not found"
fi

log_info "Waiting for GPU machines to be terminated..."
sleep 10

while oc get machines -n openshift-machine-api 2>/dev/null | grep -q "g6.*gpu"; do
    echo -n "."
    sleep 5
done
echo ""
log_success "GPU machines terminated"

# Step 3: Delete MachineConfigs
print_header "Step 3: Deleting MachineConfigs"

for mc in 99-worker-gpu-base 99-worker-gpu-g6-4xlarge 99-worker-gpu-g6-12xlarge; do
    if oc get machineconfig $mc &> /dev/null; then
        log_info "Deleting MachineConfig: $mc..."
        oc delete machineconfig $mc
        log_success "$mc deleted"
    else
        log_info "MachineConfig $mc not found"
    fi
done

# Step 4: Delete MachineConfigPool
print_header "Step 4: Deleting MachineConfigPool"

if oc get machineconfigpool worker-gpu &> /dev/null; then
    log_info "Deleting MachineConfigPool: worker-gpu..."
    oc delete machineconfigpool worker-gpu
    log_success "worker-gpu MachineConfigPool deleted"
else
    log_info "MachineConfigPool worker-gpu not found"
fi

# Step 5: Clean up Model Registry (if deployed)
print_header "Step 5: Cleaning Model Registry (if deployed)"

# Check for rhoai-model-registries namespace (new location)
if oc get namespace rhoai-model-registries &>/dev/null; then
    log_info "Model Registry detected in rhoai-model-registries namespace. Cleaning up..."
    
    # Delete Model Registry instance
    if oc get modelregistry private-ai-model-registry -n rhoai-model-registries &>/dev/null; then
        log_info "Deleting ModelRegistry instance..."
        oc delete modelregistry private-ai-model-registry -n rhoai-model-registries 2>/dev/null || true
        log_success "ModelRegistry instance deleted"
    fi
    
    # Delete Model Registry namespace
    log_info "Deleting rhoai-model-registries namespace..."
    oc delete namespace rhoai-model-registries --wait=false 2>/dev/null || true
    
    # Handle stuck namespace with finalizers
    if oc get namespace rhoai-model-registries -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Terminating"; then
        log_info "Monitoring Model Registry namespace deletion..."
        force_namespace_deletion rhoai-model-registries
    fi
    
    log_success "Model Registry cleanup complete"
elif oc get namespace model-registry &>/dev/null; then
    # Legacy location
    log_info "Model Registry detected in model-registry namespace (legacy). Cleaning up..."
    oc delete namespace model-registry --wait=false 2>/dev/null || true
    force_namespace_deletion model-registry
else
    log_info "Model Registry not deployed (skipping)"
fi

# Step 6: Verify cleanup
print_header "Verification"

echo ""
log_info "Checking for remaining resources..."

# Check namespace
if oc get namespace private-ai-demo &> /dev/null; then
    log_warning "Namespace private-ai-demo still exists (may be finalizing)"
else
    log_success "Namespace: Removed"
fi

# Check MachineSets
GPU_MACHINESETS=$(oc get machineset -n openshift-machine-api 2>/dev/null | grep -c "g6.*gpu" || echo "0")
if [ "$GPU_MACHINESETS" -eq 0 ]; then
    log_success "GPU MachineSets: Removed"
else
    log_warning "GPU MachineSets: $GPU_MACHINESETS still exist"
fi

# Check Machines
GPU_MACHINES=$(oc get machines -n openshift-machine-api 2>/dev/null | grep -c "g6.*gpu" || echo "0")
if [ "$GPU_MACHINES" -eq 0 ]; then
    log_success "GPU Machines: Removed"
else
    log_warning "GPU Machines: $GPU_MACHINES still terminating"
fi

# Check Nodes
GPU_NODES=$(oc get nodes 2>/dev/null | grep -c "g6" || echo "0")
if [ "$GPU_NODES" -eq 0 ]; then
    log_success "GPU Nodes: Removed"
else
    log_warning "GPU Nodes: $GPU_NODES still present"
fi

# Check MachineConfigs
MC_COUNT=$(oc get machineconfig 2>/dev/null | grep -c "99-worker-gpu" || echo "0")
if [ "$MC_COUNT" -eq 0 ]; then
    log_success "MachineConfigs: Removed"
else
    log_warning "MachineConfigs: $MC_COUNT still exist"
fi

# Check MachineConfigPool
if oc get machineconfigpool worker-gpu &> /dev/null; then
    log_warning "MachineConfigPool: worker-gpu still exists"
else
    log_success "MachineConfigPool: Removed"
fi

print_header "Cleanup Complete!"

echo ""
log_info "Summary:"
echo "  ├─ Namespace: Removed"
echo "  ├─ GPU MachineSets: Removed"
echo "  ├─ GPU Machines: Removed"
echo "  ├─ MachineConfigs: Removed"
echo "  ├─ MachineConfigPool: Removed"
echo "  └─ Model Registry: Removed (if deployed)"

echo ""
log_success "Stage 1 resources have been cleaned up"
log_info "You can now run a fresh deployment with:"
echo "  cd stage1-sovereign-ai"
echo "  ./deploy.sh"

echo ""

