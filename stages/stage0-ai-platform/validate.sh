#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 0: AI Platform - Validation Script
#
# Validates OpenShift AI 2.25 installation and prerequisites
##############################################################################

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    FAIL=$((FAIL + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARN=$((WARN + 1))
}

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

print_header "Stage 0: AI Platform Validation"

# ========================================================================
# 1. Node Feature Discovery
# ========================================================================
echo "1️⃣  Node Feature Discovery Operator"
if oc get subscription nfd -n openshift-nfd &>/dev/null; then
    CSV_PHASE=$(oc get csv -n openshift-nfd -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$CSV_PHASE" = "Succeeded" ]; then
        check_pass "NFD Operator installed and ready"
    else
        check_warn "NFD Operator found but not ready (phase: $CSV_PHASE)"
    fi
else
    check_fail "NFD Operator not found"
fi
echo ""

# ========================================================================
# 2. NVIDIA GPU Operator
# ========================================================================
echo "2️⃣  NVIDIA GPU Operator"
if oc get subscription gpu-operator-certified -n nvidia-gpu-operator &>/dev/null; then
    CSV_PHASE=$(oc get csv -n nvidia-gpu-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$CSV_PHASE" = "Succeeded" ]; then
        check_pass "GPU Operator installed and ready"
    else
        check_warn "GPU Operator found but not ready (phase: $CSV_PHASE)"
    fi
else
    check_fail "GPU Operator not found"
fi
echo ""

# ========================================================================
# 3. GPU MachineSets
# ========================================================================
echo "3️⃣  GPU MachineSets"
if oc get machinesets -n openshift-machine-api | grep -q "g6-4xlarge"; then
    REPLICAS=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[?(@.metadata.name contains "g6-4xlarge")].spec.replicas}' 2>/dev/null || echo "0")
    check_pass "g6.4xlarge MachineSet exists (replicas: $REPLICAS)"
else
    check_fail "g6.4xlarge MachineSet not found"
fi

if oc get machinesets -n openshift-machine-api | grep -q "g6-12xlarge"; then
    REPLICAS=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[?(@.metadata.name contains "g6-12xlarge")].spec.replicas}' 2>/dev/null || echo "0")
    check_pass "g6.12xlarge MachineSet exists (replicas: $REPLICAS)"
else
    check_fail "g6.12xlarge MachineSet not found"
fi
echo ""

# ========================================================================
# 4. GPU Machines
# ========================================================================
echo "4️⃣  GPU Machines"
GPU_MACHINES=$(oc get machines -n openshift-machine-api | grep -c "gpu" || echo "0")
if [ "$GPU_MACHINES" -ge 2 ]; then
    check_pass "GPU machines provisioned: $GPU_MACHINES"
    
    # Check machine phases
    RUNNING=$(oc get machines -n openshift-machine-api | grep gpu | grep -c "Running" || echo "0")
    PROVISIONED=$(oc get machines -n openshift-machine-api | grep gpu | grep -c "Provisioned" || echo "0")
    PROVISIONING=$(oc get machines -n openshift-machine-api | grep gpu | grep -c "Provisioning" || echo "0")
    
    echo "     Running: $RUNNING, Provisioned: $PROVISIONED, Provisioning: $PROVISIONING"
    
    if [ "$RUNNING" -ge 2 ]; then
        check_pass "All GPU machines in Running state"
    elif [ "$((RUNNING + PROVISIONED))" -ge 2 ]; then
        check_warn "GPU machines provisioned but not all running yet"
    else
        check_warn "GPU machines still provisioning"
    fi
else
    check_fail "Expected 2 GPU machines, found: $GPU_MACHINES"
fi
echo ""

# ========================================================================
# 5. GPU Nodes
# ========================================================================
echo "5️⃣  GPU Nodes"
GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$GPU_NODES" -ge 2 ]; then
    check_pass "GPU nodes ready: $GPU_NODES"
    
    # Show node details
    echo ""
    echo "     GPU Node Details:"
    oc get nodes -l nvidia.com/gpu.present=true -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,INSTANCE:.metadata.labels.node\.kubernetes\.io/instance-type,GPU:.metadata.labels.nvidia\.com/gpu\.count 2>/dev/null | sed 's/^/     /'
else
    check_warn "GPU nodes not ready yet (found: $GPU_NODES, expected: 2)"
    echo "     Tip: GPU nodes may take 10-15 minutes to provision"
fi
echo ""

# ========================================================================
# 6. OpenShift AI Operator
# ========================================================================
echo "6️⃣  Red Hat OpenShift AI Operator"
if oc get subscription rhods-operator -n redhat-ods-operator &>/dev/null; then
    CSV_NAME=$(oc get csv -n redhat-ods-operator -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift AI")].metadata.name}' 2>/dev/null || echo "not-found")
    CSV_PHASE=$(oc get csv -n redhat-ods-operator -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift AI")].status.phase}' 2>/dev/null || echo "Unknown")
    CSV_VERSION=$(oc get csv -n redhat-ods-operator -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift AI")].spec.version}' 2>/dev/null || echo "unknown")
    
    if [ "$CSV_PHASE" = "Succeeded" ]; then
        check_pass "OpenShift AI Operator ready (version: $CSV_VERSION)"
    else
        check_warn "OpenShift AI Operator found but not ready (phase: $CSV_PHASE)"
    fi
else
    check_fail "OpenShift AI Operator not found"
fi
echo ""

# ========================================================================
# 7. DataScienceCluster
# ========================================================================
echo "7️⃣  DataScienceCluster"
if oc get datasciencecluster default-dsc &>/dev/null; then
    DSC_PHASE=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    if [ "$DSC_PHASE" = "Ready" ]; then
        check_pass "DataScienceCluster ready"
    else
        check_warn "DataScienceCluster found but not ready (phase: $DSC_PHASE)"
    fi
    
    # Check key components
    echo ""
    echo "     Component Status:"
    for component in dashboard workbenches datasciencepipelines modelregistry kserve modelmeshserving trustyai; do
        STATUS=$(oc get datasciencecluster default-dsc -o jsonpath="{.status.conditions[?(@.type=='${component^}Available')].status}" 2>/dev/null || echo "Unknown")
        MANAGEMENT=$(oc get datasciencecluster default-dsc -o jsonpath="{.spec.components.${component}.managementState}" 2>/dev/null || echo "Unknown")
        
        if [ "$MANAGEMENT" = "Managed" ]; then
            if [ "$STATUS" = "True" ]; then
                echo -e "     ${GREEN}✓${NC} $component (Managed, Available)"
            else
                echo -e "     ${YELLOW}⚠${NC} $component (Managed, Status: $STATUS)"
            fi
        else
            echo -e "     ${BLUE}○${NC} $component ($MANAGEMENT)"
        fi
    done
else
    check_fail "DataScienceCluster not found"
fi
echo ""

# ========================================================================
# 8. Model Registry
# ========================================================================
echo "8️⃣  Model Registry"
if oc get project rhoai-model-registries &>/dev/null; then
    check_pass "Model Registry namespace exists"
    
    # Check for Model Registry deployment
    if oc get deployment -n rhoai-model-registries &>/dev/null; then
        DEPLOYMENTS=$(oc get deployment -n rhoai-model-registries --no-headers 2>/dev/null | wc -l || echo "0")
        check_pass "Model Registry deployments found: $DEPLOYMENTS"
        
        # Check specific deployments
        for deploy in model-registry-db model-registry-dora; do
            if oc get deployment "$deploy" -n rhoai-model-registries &>/dev/null; then
                READY=$(oc get deployment "$deploy" -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
                if [ "$READY" = "True" ]; then
                    echo -e "     ${GREEN}✓${NC} $deploy ready"
                else
                    echo -e "     ${YELLOW}⚠${NC} $deploy not ready yet"
                fi
            fi
        done
    else
        check_warn "Model Registry deployments not found yet"
    fi
    
    # Check route
    if oc get route -n rhoai-model-registries &>/dev/null; then
        ROUTE=$(oc get route -n rhoai-model-registries -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "not-found")
        check_pass "Model Registry route: https://$ROUTE"
    else
        check_warn "Model Registry route not found yet"
    fi
else
    check_fail "Model Registry namespace not found"
fi
echo ""

# ========================================================================
# 9. OpenShift AI Dashboard
# ========================================================================
echo "9️⃣  OpenShift AI Dashboard"
if oc get route rhods-dashboard -n redhat-ods-applications &>/dev/null; then
    DASHBOARD_URL=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-found")
    check_pass "Dashboard route: https://$DASHBOARD_URL"
else
    check_warn "Dashboard route not found yet"
fi
echo ""

# ========================================================================
# Summary
# ========================================================================
print_header "Validation Summary"

echo "Results:"
echo -e "  ${GREEN}✓${NC} Passed: $PASS"
echo -e "  ${YELLOW}⚠${NC} Warnings: $WARN"
echo -e "  ${RED}✗${NC} Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
    echo "✅ All checks passed! Stage 0 is ready."
    echo ""
    echo "📖 Next Steps:"
    echo "  • Proceed to Stage 1: Model Serving"
    echo "  • cd ../stage1-model-serving-with-vllm"
    exit 0
elif [ $FAIL -eq 0 ]; then
    echo "⚠️  Validation passed with warnings."
    echo ""
    echo "📋 Common issues:"
    echo "  • GPU nodes may still be provisioning (10-15 min)"
    echo "  • DataScienceCluster components may be initializing (5-10 min)"
    echo "  • Model Registry may be deploying (2-5 min)"
    echo ""
    echo "💡 Tip: Wait a few minutes and run ./validate.sh again"
    exit 0
else
    echo "❌ Validation failed. Please review the errors above."
    echo ""
    echo "🔧 Troubleshooting:"
    echo "  • Check operator logs: oc logs -n <namespace> <pod>"
    echo "  • Review DataScienceCluster: oc describe datasciencecluster default-dsc"
    echo "  • Check events: oc get events -n <namespace> --sort-by='.lastTimestamp'"
    exit 1
fi
