#!/bin/bash

##############################################################################
# Red Hat AI Demo - Stage 1 Deployment Script
# 
# This script automates the deployment of Stage 1: Sovereign AI
# - Provisions GPU nodes
# - Deploys vLLM models (full + quantized)
# - Runs benchmarks and registers models
#
# Prerequisites:
# - oc CLI configured and logged in
# - Admin access to OpenShift cluster
# - HuggingFace token (in .env file)
# - OpenShift AI operator installed
# - NVIDIA GPU operator installed
##############################################################################

set -e  # Exit on error

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GITOPS_DIR="${PROJECT_ROOT}/gitops"

# Load environment variables from .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "🔐 Loading configuration from .env file..."
    # Export variables from .env, ignoring comments and empty lines
    set -a
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$' | sed 's/\r$//')
    set +a
    echo "✅ Configuration loaded"
else
    echo "⚠️  No .env file found."
    echo "   To configure automatically, copy env.template to .env and fill in your values:"
    echo "   cp env.template .env"
    echo ""
    echo "   Will prompt for required values..."
fi
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
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
    echo ""
}

wait_for_condition() {
    local resource=$1
    local namespace=$2
    local condition=$3
    local timeout=${4:-300}
    
    log_info "Waiting for $resource in $namespace (timeout: ${timeout}s)..."
    oc wait --for=condition=$condition $resource -n $namespace --timeout=${timeout}s
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check oc CLI
    if ! command -v oc &> /dev/null; then
        log_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi
    log_success "oc CLI found"
    
    # Check if logged in
    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift. Run 'oc login' first."
        exit 1
    fi
    log_success "Logged in as $(oc whoami)"
    
    # Check for admin access
    if ! oc auth can-i create machineset -n openshift-machine-api &> /dev/null; then
        log_warning "You may not have admin access. GPU provisioning might fail."
    else
        log_success "Admin access confirmed"
    fi
    
    # Check if OpenShift AI is installed
    if ! oc get datasciencecluster &> /dev/null; then
        log_warning "OpenShift AI may not be installed"
    else
        log_success "OpenShift AI detected"
    fi
    
    # Check if NVIDIA GPU Operator is installed
    if ! oc get namespace nvidia-gpu-operator &> /dev/null; then
        log_warning "NVIDIA GPU Operator may not be installed"
    else
        log_success "NVIDIA GPU Operator detected"
    fi
}

# Check and enable Model Registry component in DataScienceCluster
check_model_registry_operator() {
    print_header "Prerequisites: Model Registry Component"
    
    log_info "Checking Model Registry in DataScienceCluster..."
    
    # Check if Model Registry is already enabled
    REGISTRY_STATE=$(oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.modelregistry.managementState}' 2>/dev/null || echo "")
    
    if [ "$REGISTRY_STATE" = "Managed" ]; then
        log_success "Model Registry already enabled in DataScienceCluster"
        return 0
    fi
    
    if [ "$REGISTRY_STATE" = "Removed" ]; then
        log_info "Model Registry is currently disabled in DataScienceCluster"
    fi
    
    read -p "Enable Model Registry component for MLOps tracking? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "Skipping Model Registry enablement"
        log_warning "Model registration will be skipped later"
        return 0
    fi
    
    log_info "Enabling Model Registry in DataScienceCluster..."
    oc patch datasciencecluster default-dsc --type='json' -p='[{"op": "replace", "path": "/spec/components/modelregistry/managementState", "value": "Managed"}]'
    
    log_info "Waiting for Model Registry operator to deploy (this may take 2-3 minutes)..."
    sleep 20
    
    # Wait for CRD to be created
    for i in {1..30}; do
        if oc get crd modelregistries.modelregistry.opendatahub.io 2>/dev/null; then
            log_success "Model Registry component enabled and ready"
            return 0
        fi
        echo -n "."
        sleep 5
    done
    
    log_warning "Model Registry component enablement timed out"
    log_warning "Model registration may not work. Check: oc get datasciencecluster"
}

# Check and configure HuggingFace token
prompt_for_token() {
    print_header "HuggingFace Token"
    
    # Check if secret already exists
    if oc get secret huggingface-token -n private-ai-demo &> /dev/null; then
        log_success "HuggingFace token secret already exists"
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
        oc delete secret huggingface-token -n private-ai-demo
    fi
    
    # Check if HF_TOKEN is set from .env file
    if [ -n "$HF_TOKEN" ]; then
        log_success "HuggingFace token loaded from .env file"
        export HF_TOKEN
        return
    fi
    
    # Prompt for token if not in .env
    log_info "HuggingFace token not found in .env file, prompting..."
    read -sp "Enter your HuggingFace token: " HF_TOKEN
    echo
    
    if [ -z "$HF_TOKEN" ]; then
        log_error "HuggingFace token is required"
        log_error "Either:"
        log_error "  1. Add HF_TOKEN to .env file (cp env.template .env)"
        log_error "  2. Export HF_TOKEN environment variable"
        log_error "  3. Enter when prompted"
        exit 1
    fi
    
    export HF_TOKEN
    log_success "HuggingFace token configured"
}

# Provision GPU nodes
provision_gpu_nodes() {
    print_header "Step 1: Provisioning Dedicated GPU Nodes"
    
    log_info "This demo requires 2 dedicated GPU nodes:"
    log_info "  • 1x g6.4xlarge (1 GPU) for quantized model"
    log_info "  • 1x g6.12xlarge (4 GPUs) for full model"
    log_info ""
    log_info "Note: Pre-existing GPU nodes in the cluster will not be affected."
    
    log_info "Getting cluster information..."
    CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')
    AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')
    IAM_PROFILE=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.iamInstanceProfile.id}')
    ZONE=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.placement.availabilityZone}')
    
    log_info "Cluster ID: $CLUSTER_ID"
    log_info "Region: $REGION"
    log_info "Zone: $ZONE"
    log_info "AMI ID: $AMI_ID"
    
    export CLUSTER_NAME=$CLUSTER_ID AWS_REGION=$REGION AWS_ZONE=$ZONE AWS_AMI_ID=$AMI_ID AWS_IAM_PROFILE=$IAM_PROFILE
    
    # Step 1: Apply MachineConfigPool for GPU nodes
    log_info "Creating MachineConfigPool for GPU nodes..."
    oc apply -f "${GITOPS_DIR}/components/gpu-provisioning/machineconfig-pool-gpu.yaml"
    log_success "MachineConfigPool created"
    
    # Step 2: Apply MachineConfigs for GPU node OS configuration
    log_info "Applying GPU MachineConfigs (OS configuration)..."
    oc apply -f "${GITOPS_DIR}/components/gpu-provisioning/machineconfig-gpu-base.yaml"
    oc apply -f "${GITOPS_DIR}/components/gpu-provisioning/machineconfig-g6-4xlarge.yaml"
    oc apply -f "${GITOPS_DIR}/components/gpu-provisioning/machineconfig-g6-12xlarge.yaml"
    log_success "GPU MachineConfigs applied"
    
    log_info "Waiting for MachineConfigPool to be ready (this may take a few minutes)..."
    oc wait --for=condition=Updated mcp/worker-gpu --timeout=300s 2>/dev/null || log_warning "MCP not ready yet, continuing..."
    
    # Step 3: Deploy MachineSets (requires envsubst for cluster-specific values)
    # Note: Cannot use 'oc apply -k' here because MachineSets contain template variables
    # that need runtime substitution (CLUSTER_NAME, AWS_REGION, etc.)
    log_info "Creating MachineSet for g6.4xlarge (1x L4 GPU)..."
    envsubst < "${GITOPS_DIR}/components/gpu-provisioning/g6-4xlarge.yaml" | oc apply -f -
    log_success "g6.4xlarge MachineSet created"
    
    log_info "Creating MachineSet for g6.12xlarge (4x L4 GPU)..."
    envsubst < "${GITOPS_DIR}/components/gpu-provisioning/g6-12xlarge.yaml" | oc apply -f -
    log_success "g6.12xlarge MachineSet created"
    
    log_info "GPU nodes are provisioning (this takes 5-10 minutes)..."
    log_info "You can monitor progress with: oc get machines -n openshift-machine-api -w"
    log_info ""
    log_info "Waiting for dedicated GPU machines to be provisioned..."
    sleep 60  # Initial wait
    
    timeout=600  # 10 minutes
    elapsed=0
    while true; do
        READY_4X=$(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machineset=g6-4xlarge-gpu -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | wc -w)
        READY_12X=$(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machineset=g6-12xlarge-gpu -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | wc -w)
        
        if [ "$READY_4X" -ge 1 ] && [ "$READY_12X" -ge 1 ]; then
            log_success "Both dedicated GPU machines are ready!"
            log_info "  • g6.4xlarge: Ready"
            log_info "  • g6.12xlarge: Ready"
            break
        fi
        
        if [ $elapsed -ge $timeout ]; then
            log_warning "Timeout waiting for GPU machines after ${timeout}s"
            log_warning "Current status: g6.4xlarge=$READY_4X, g6.12xlarge=$READY_12X"
            log_warning "Machines may still be provisioning. Check: oc get machines -n openshift-machine-api"
            log_warning "Continuing with deployment..."
                break
            fi
        
        echo -n "."
        sleep 15
        elapsed=$((elapsed + 15))
    done
    echo ""
}

# Deploy base resources
deploy_base() {
    print_header "Step 2: Deploying Base Resources"
    
    log_info "Deploying namespace, RBAC, quotas..."
    oc apply -k "${GITOPS_DIR}/base/namespace"
    log_success "Base namespace resources deployed"
    
    # Create HuggingFace token secret
    if [ ! -z "$HF_TOKEN" ]; then
        log_info "Creating HuggingFace token secret..."
        oc create secret generic huggingface-token \
            --from-literal=HF_TOKEN="$HF_TOKEN" \
            -n private-ai-demo \
            --dry-run=client -o yaml | oc apply -f -
        log_success "HuggingFace token secret created"
    fi
    
    log_info "Deploying PVCs (storage for models)..."
    oc apply -f "${GITOPS_DIR}/base/vllm/pvc-mistral-24b-quantized.yaml"
    oc apply -f "${GITOPS_DIR}/base/vllm/pvc-mistral-24b.yaml"
    log_success "PVCs created"
    
    log_info "Waiting for PVCs to be bound..."
    oc wait --for=jsonpath='{.status.phase}'=Bound pvc/models-mistral-24b-quantized -n private-ai-demo --timeout=60s || true
    oc wait --for=jsonpath='{.status.phase}'=Bound pvc/models-mistral-24b -n private-ai-demo --timeout=60s || true
    log_success "PVCs are bound"
    
    # IMPORTANT: Do NOT deploy ServingRuntimes or InferenceServices here!
    # They must be deployed AFTER models are downloaded (see deploy_inference_services function)
    log_info "⚠️  ServingRuntimes and InferenceServices will be deployed AFTER model downloads complete"
}

# Download models
download_models() {
    print_header "Step 3: Downloading Models"
    
    log_info "Deploying model download jobs..."
    oc apply -k "${GITOPS_DIR}/components/model-loader"
    
    log_info "Model download started (this takes 15-30 minutes per model)..."
    log_info "You can monitor progress with:"
    echo "  oc logs job/download-mistral-24b-quantized -n private-ai-demo -f"
    echo "  oc logs job/download-mistral-24b -n private-ai-demo -f"
    
    read -p "Wait for model downloads to complete? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        log_info "Waiting for download jobs to complete..."
        
        # Wait for quantized model
        log_info "Downloading quantized model..."
        oc wait --for=condition=complete job/download-mistral-24b-quantized -n private-ai-demo --timeout=3600s || {
            log_error "Quantized model download failed or timed out"
            log_info "Check logs: oc logs job/download-mistral-24b-quantized -n private-ai-demo"
        }
        
        # Wait for full model
        log_info "Downloading full model..."
        oc wait --for=condition=complete job/download-mistral-24b -n private-ai-demo --timeout=3600s || {
            log_error "Full model download failed or timed out"
            log_info "Check logs: oc logs job/download-mistral-24b -n private-ai-demo"
        }
        
        log_success "Model downloads complete"
        
        log_info "Verifying model files..."
        oc exec -n private-ai-demo job/download-mistral-24b-quantized -- ls -lh /models/mistral-24b-quantized 2>/dev/null | tail -5 || log_warning "Could not verify quantized model"
        oc exec -n private-ai-demo job/download-mistral-24b -- ls -lh /models/mistral-24b 2>/dev/null | tail -5 || log_warning "Could not verify full model"
        log_success "Models are ready for serving"
    else
        log_warning "Skipping model download wait."
        log_warning "⚠️  WARNING: InferenceServices will FAIL if deployed before downloads complete!"
        log_warning "You must wait for downloads to finish before Step 4 (Deploy InferenceServices)."
    fi
}

# Deploy InferenceServices
deploy_inference_services() {
    print_header "Step 4: Deploying InferenceServices"
    
    # Safety check: Ensure models are downloaded before creating InferenceServices
    log_info "🔍 Verifying models are downloaded..."
    
    QUANTIZED_JOB_STATUS=$(oc get job download-mistral-24b-quantized -n private-ai-demo -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "NotFound")
    FULL_JOB_STATUS=$(oc get job download-mistral-24b -n private-ai-demo -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "NotFound")
    
    if [[ "$QUANTIZED_JOB_STATUS" != "True" ]] || [[ "$FULL_JOB_STATUS" != "True" ]]; then
        log_error "⚠️  Model downloads are NOT complete!"
        log_error "   Quantized model job status: $QUANTIZED_JOB_STATUS"
        log_error "   Full model job status: $FULL_JOB_STATUS"
        log_error ""
        log_error "InferenceServices will FAIL if models are not present."
        log_error "Wait for downloads to complete before creating InferenceServices."
        echo ""
        read -p "Do you want to proceed anyway? (yes/NO): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_warning "Skipping InferenceService deployment"
            log_info "Run this step manually when models are ready"
            return 0
        fi
    else
        log_success "✅ Both models are downloaded and ready"
    fi
    
    # Check if InferenceServices already exist and delete them if needed
    if oc get inferenceservice mistral-24b-quantized -n private-ai-demo &>/dev/null; then
        log_warning "InferenceServices already exist. Deleting to ensure clean deployment..."
        oc delete inferenceservice mistral-24b mistral-24b-quantized -n private-ai-demo --wait=false
        sleep 10
    fi
    
    log_info "Creating ServingRuntimes..."
    oc apply -f "${GITOPS_DIR}/base/vllm/servingruntime-mistral-24b-quantized.yaml"
    oc apply -f "${GITOPS_DIR}/base/vllm/servingruntime-mistral-24b.yaml"
    log_success "ServingRuntimes created"
    
    log_info "Creating InferenceServices..."
    oc apply -f "${GITOPS_DIR}/base/vllm/inferenceservice-mistral-24b-quantized.yaml"
    oc apply -f "${GITOPS_DIR}/base/vllm/inferenceservice-mistral-24b.yaml"
    log_success "InferenceServices created"
    
    log_info "InferenceServices are starting up (this takes 3-5 minutes)..."
    log_info "Knative Serving will create predictor pods and wait for them to be ready"
    
    # Wait for Knative Services to be created by KServe
    log_info "Waiting for Knative Services (ksvc) to be created..."
    sleep 10
    
    # Add topology connections to Knative Services
    # Note: InferenceServices create Knative Services (ksvc) which appear in topology
    # The annotation must be applied to the ksvc, not the InferenceService itself
    log_info "Adding topology connections to Knative Services..."
    if oc get ksvc mistral-24b-quantized-predictor -n private-ai-demo &>/dev/null; then
        oc patch ksvc mistral-24b-quantized-predictor -n private-ai-demo --type=merge \
            -p '{"metadata":{"annotations":{"app.openshift.io/connects-to":"[{\"apiVersion\":\"apps/v1\",\"kind\":\"Deployment\",\"name\":\"llama-stack\"}]"}}}' 2>/dev/null || true
    fi
    if oc get ksvc mistral-24b-predictor -n private-ai-demo &>/dev/null; then
        oc patch ksvc mistral-24b-predictor -n private-ai-demo --type=merge \
            -p '{"metadata":{"annotations":{"app.openshift.io/connects-to":"[{\"apiVersion\":\"apps/v1\",\"kind\":\"Deployment\",\"name\":\"llama-stack\"}]"}}}' 2>/dev/null || true
    fi
    log_success "Topology connections added"
    
    # Show status
    echo ""
    oc get inferenceservice -n private-ai-demo
}

# Run GuideLLM benchmarks
run_guidellm_benchmarks() {
    print_header "Step 5: Running GuideLLM Benchmarks"
    
    read -p "Do you want to run GuideLLM benchmark tests? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "Skipping benchmarks"
        return
    fi
    
    echo ""
    log_info "GuideLLM provides comprehensive performance metrics:"
    echo "  • Time To First Token (TTFT) - P50, P90, P95, P99"
    echo "  • Inter-Token Latency (ITL) - P50, P90, P95, P99"
    echo "  • Throughput - Tokens/second"
    echo "  • Load testing - Concurrency 1,2,4,8,16"
    echo "  • Cost analysis"
    echo ""
    
    # Get dynamic cluster URLs
    log_info "Getting InferenceService URLs..."
    QUANTIZED_URL=$(oc get inferenceservice mistral-24b-quantized -n private-ai-demo -o jsonpath='{.status.url}' 2>/dev/null || echo "")
    FULL_URL=$(oc get inferenceservice mistral-24b -n private-ai-demo -o jsonpath='{.status.url}' 2>/dev/null || echo "")
    
    if [ -z "$QUANTIZED_URL" ] || [ -z "$FULL_URL" ]; then
        log_error "InferenceService URLs not found. Make sure InferenceServices are ready."
        return
    fi
    
    log_info "Quantized URL: $QUANTIZED_URL"
    log_info "Full URL: $FULL_URL"
    echo ""
    
    # Create benchmark results PVCs (three-PVC pattern for AWS EBS ReadWriteOnce)
    log_info "Creating benchmark results PVCs..."
    oc apply -f "${GITOPS_DIR}/components/benchmarking/pvc-quantized-results.yaml" || true
    oc apply -f "${GITOPS_DIR}/components/benchmarking/pvc-full-results.yaml" || true
    oc apply -f "${GITOPS_DIR}/components/benchmarking/pvc-workbench-results.yaml" || true
    
    log_info "Waiting for PVCs to bind..."
    sleep 5
    
    # Deploy GuideLLM jobs (they use dynamic cluster domain discovery)
    log_info "Deploying GuideLLM benchmark jobs..."
    oc apply -f "${GITOPS_DIR}/components/benchmarking/configmap-publish-script.yaml"
    oc apply -f "${GITOPS_DIR}/components/benchmarking/job-guidellm-quantized.yaml"
    oc apply -f "${GITOPS_DIR}/components/benchmarking/job-guidellm-full.yaml"
    
    log_success "GuideLLM benchmark jobs deployed"
    echo ""
    log_info "📊 Monitoring Commands:"
    echo "   Quantized: oc logs job/guidellm-benchmark-quantized -n private-ai-demo -f"
    echo "   Full:      oc logs job/guidellm-benchmark-full -n private-ai-demo -f"
    echo ""
    
    read -p "Wait for benchmarks to complete? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        log_info "⏳ Waiting for benchmarks to complete (this may take 10-15 minutes)..."
        echo "   Both jobs run in parallel with 5-minute tests + tokenizer fetch time."
        echo ""
        
        # Wait for both jobs in parallel
        oc wait --for=condition=complete job/guidellm-benchmark-quantized -n private-ai-demo --timeout=1800s 2>&1 | sed 's/^/   [Quantized] /' &
        PID1=$!
        oc wait --for=condition=complete job/guidellm-benchmark-full -n private-ai-demo --timeout=1800s 2>&1 | sed 's/^/   [Full] /' &
        PID2=$!
        
        # Wait for both to complete
        wait $PID1 $PID2
        
        QUANT_STATUS=$(oc get job guidellm-benchmark-quantized -n private-ai-demo -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")
        FULL_STATUS=$(oc get job guidellm-benchmark-full -n private-ai-demo -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")
        
        echo ""
        if [[ "$QUANT_STATUS" == "True" ]] && [[ "$FULL_STATUS" == "True" ]]; then
            log_success "✅ Both benchmarks completed successfully!"
            echo ""
            
            # Copy results to shared PVC for workbench access
            log_info "📋 Copying results to shared PVC..."
            log_warning "Note: Temporarily stopping workbench to release shared PVC..."
            oc delete notebook rag-testing -n private-ai-demo 2>/dev/null || true
            sleep 10
            
            oc apply -f "${GITOPS_DIR}/components/benchmarking/job-copy-results.yaml"
            log_info "Waiting for copy job to complete..."
            oc wait --for=condition=complete job/copy-benchmark-results -n private-ai-demo --timeout=60s 2>/dev/null || true
            
            # Recreate workbench
            log_info "Recreating workbench..."
            oc apply -f "${GITOPS_DIR}/components/workbench/notebook.yaml"
            
            log_success "Results copied to shared PVC and workbench restored"
            echo ""
            echo "════════════════════════════════════════════════════════════════"
            echo "  ✅ BENCHMARKS COMPLETE"
            echo "════════════════════════════════════════════════════════════════"
            echo ""
            log_info "Results available in:"
            echo "  • JupyterLab workbench: /benchmark-results/"
            echo "  • Model Registry: Description field of each model version"
        else
            log_warning "⚠️  One or both benchmarks did not complete successfully"
            echo "   Quantized status: $QUANT_STATUS"
            echo "   Full status: $FULL_STATUS"
            echo ""
            echo "   Check logs:"
            echo "   oc logs job/guidellm-benchmark-quantized -n private-ai-demo"
            echo "   oc logs job/guidellm-benchmark-full -n private-ai-demo"
        fi
    else
        echo ""
        log_info "ℹ️  Benchmarks are running in the background"
    fi
    
    echo ""
    log_success "GuideLLM benchmarking initiated!"
    echo ""
    log_info "📁 Storage Architecture (Three-PVC Pattern):"
    echo "   • benchmark-quantized-results (RWO) - Quantized job writes here"
    echo "   • benchmark-full-results (RWO) - Full precision job writes here"
    echo "   • benchmark-workbench-results (RWO) - Shared storage for workbench"
    echo ""
    log_info "💡 To access results:"
    echo "   1. From JupyterLab workbench: Open 01-benchmark.ipynb"
    echo "   2. Results auto-mounted at: /opt/app-root/src/benchmark-results/"
    echo "   3. Model Registry: Check model version descriptions"
    echo ""
    log_info "ℹ️  Why three PVCs?"
    echo "   AWS EBS only supports ReadWriteOnce (RWO)"
    echo "   Jobs write to dedicated PVCs, then copy job moves to shared PVC"
    echo "   This enables parallel execution + workbench access"
    echo ""
}

# Deploy Model Registry infrastructure
deploy_model_registry() {
    print_header "Step 5.5: Deploy Model Registry"
    
    # Check if Model Registry component is enabled
    if ! oc get crd modelregistries.modelregistry.opendatahub.io 2>/dev/null; then
        log_warning "Model Registry component not enabled. Skipping Model Registry deployment."
        log_info "To enable: Re-run deploy.sh and enable Model Registry in prerequisites"
        return 0
    fi
    
    read -p "Deploy Model Registry instance for MLOps tracking? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "Skipping Model Registry deployment"
        return 0
    fi
    
    # Deploy MySQL backend to private-ai-demo namespace (rhoai-mlops pattern)
    log_info "Deploying MySQL backend to private-ai-demo namespace..."
    oc apply -k "${GITOPS_DIR}/components/model-registry-mysql"
    
    log_info "Waiting for MySQL to be ready (this may take 2-3 minutes)..."
    oc wait --for=condition=available deployment/private-ai-registry-db \
        -n private-ai-demo --timeout=300s || {
        log_warning "MySQL not ready yet, continuing anyway..."
    }
    
    # Create ModelRegistry CR and infrastructure in rhoai-model-registries namespace
    log_info "Deploying Model Registry to rhoai-model-registries namespace..."
    oc apply -k "${GITOPS_DIR}/components/model-registry-infrastructure"
    
    log_info "Model Registry will connect to MySQL via FQDN: private-ai-registry-db.private-ai-demo.svc.cluster.local"

    log_info "Waiting for Model Registry to be ready..."
    sleep 20
    
    # Ensure deployment has Service Mesh label for external route access
    log_info "Adding Service Mesh label for external route access..."
    oc patch deployment private-ai-model-registry -n rhoai-model-registries \
        -p '{"spec":{"template":{"metadata":{"labels":{"maistra.io/expose-route":"true"}}}}}' \
        2>/dev/null || log_warning "Deployment already has Service Mesh label or operator will add it"
    
    # Grant dashboard access to Model Registry (per RHOAI documentation)
    log_info "Granting dashboard service account access to Model Registry..."
    oc create rolebinding rhods-dashboard-model-registry-access \
        -n rhoai-model-registries \
        --role=registry-user-private-ai-model-registry \
        --serviceaccount=redhat-ods-applications:rhods-dashboard \
        2>/dev/null || log_info "Dashboard role binding already exists"
    
    # Wait for pods to be ready
    for i in {1..30}; do
        if oc get pods -n rhoai-model-registries 2>/dev/null | grep -q "private-ai-model-registry.*Running"; then
            break
        fi
        echo -n "."
        sleep 5
    done
    echo ""
    
    # Expose REST API port 8080 for job access (in addition to OAuth proxy port 8443)
    log_info "Exposing REST API port 8080 for job/ServiceAccount access..."
    oc patch svc private-ai-model-registry -n rhoai-model-registries \
        --type='json' \
        -p='[{"op": "add", "path": "/spec/ports/-", "value": {"name": "rest-api", "port": 8080, "protocol": "TCP", "targetPort": 8080}}]' \
        2>/dev/null || log_info "Port 8080 already exposed"
    
    # Get the OAuth proxy route (HTTPS)
    MR_ROUTE=$(oc get route -n rhoai-model-registries private-ai-model-registry-https -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    if [ -n "$MR_ROUTE" ]; then
        log_success "Model Registry ready: https://$MR_ROUTE"
        log_info "OAuth proxy enabled for dashboard integration"
        log_info "REST API available at: http://private-ai-model-registry.rhoai-model-registries.svc.cluster.local:8080"
    else
        log_warning "Model Registry route not found yet"
        log_info "Check with: oc get route -n rhoai-model-registries"
    fi
}

# Register models in Model Registry
register_models() {
    print_header "Step 6: Registering Models"
    
    # Check if Model Registry is deployed
    if ! oc get svc private-ai-model-registry -n rhoai-model-registries &>/dev/null; then
        log_warning "Model Registry not deployed, skipping registration"
        log_info "To enable: Deploy Model Registry in previous step"
        return 0
    fi
    
    log_info "Deploying SDK-based model registration job..."
    log_info "Using Model Registry Python SDK 0.2.10"
    log_info "REST API endpoint: http://private-ai-model-registry.rhoai-model-registries.svc.cluster.local:8080"
    
    # Delete existing jobs if present
    oc delete job register-models -n private-ai-demo 2>/dev/null || true
    oc delete job register-models-sdk -n private-ai-demo 2>/dev/null || true
    
    # Apply SDK-based registration job using Kustomize
    log_info "Applying model registration job via Kustomize..."
    oc apply -k "${GITOPS_DIR}/components/model-registry"
    
    log_info "Waiting for registration to complete..."
    oc wait --for=condition=complete job/register-models-sdk \
        -n private-ai-demo --timeout=180s 2>/dev/null || {
        log_warning "Registration not complete, check logs"
    }
    
    echo ""
    log_info "Registration logs:"
    oc logs job/register-models-sdk -n private-ai-demo -c register --tail=30 2>/dev/null || {
        log_warning "Could not get registration logs"
    }
    
    log_success "Model registration complete (SDK-based)"
    log_info "View models in OpenShift AI dashboard Model Registry section"
}

# Run TrustyAI LM-Eval evaluations
run_trustyai_evaluations() {
    print_header "Step 7: Running TrustyAI LM-Eval Evaluations"
    
    read -p "Do you want to run TrustyAI LM-Eval accuracy tests? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "Skipping evaluations"
        return
    fi
    
    echo ""
    log_info "TrustyAI LM-Eval provides model accuracy/quality metrics:"
    echo "  • ARC-Easy - Reasoning (grade-school science)"
    echo "  • HellaSwag - Commonsense Natural Language Inference"
    echo "  • GSM8K - Math reasoning (grade-school word problems)"
    echo "  • TruthfulQA MC2 - Truthfulness assessment"
    echo ""
    log_info "Each task uses 500 samples (0-shot evaluation)"
    log_info "Estimated time: Full model ~10 min, Quantized ~20 min"
    echo ""
    
    # Check TrustyAI operator configuration
    log_info "Checking TrustyAI operator configuration..."
    ALLOW_ONLINE=$(oc get configmap trustyai-service-operator-config \
        -n redhat-ods-applications \
        -o jsonpath='{.data.lmes-allow-online}' 2>/dev/null || echo "")
    
    if [ "$ALLOW_ONLINE" != "true" ]; then
        log_warning "TrustyAI operator not configured for online access"
        log_info "Configuring operator for online dataset/tokenizer downloads..."
        
        # Patch ConfigMap to prevent auto-reconciliation
        oc annotate configmap trustyai-service-operator-config \
            -n redhat-ods-applications \
            opendatahub.io/managed=false --overwrite 2>/dev/null || true
        
        # Enable online access and code execution
        oc patch configmap trustyai-service-operator-config \
            -n redhat-ods-applications \
            --type merge \
            -p '{"data":{"lmes-allow-online":"true","lmes-allow-code-execution":"true"}}' || {
            log_error "Failed to configure TrustyAI operator"
            log_info "Manual steps required - see docs/TRUSTYAI-CONTEXT.md"
            return
        }
        
        # Restart operator
        log_info "Restarting TrustyAI operator..."
        oc delete pod -n redhat-ods-applications \
            -l control-plane=trustyai-service-operator 2>/dev/null || true
        
        log_info "Waiting for operator to restart..."
        sleep 15
        log_success "TrustyAI operator configured"
    else
        log_success "TrustyAI operator already configured"
    fi
    
    echo ""
    log_info "Deploying LMEvalJob resources..."
    
    # Delete existing eval jobs if present
    oc delete lmevaljob --all -n private-ai-demo 2>/dev/null || true
    sleep 5
    
    # Deploy eval jobs via Kustomize
    oc apply -k "${GITOPS_DIR}/components/trustyai-eval-operator"
    
    log_info "LMEvalJobs deployed. Monitoring progress..."
    echo ""
    
    # Monitor eval jobs
    TIMEOUT=1800  # 30 minutes
    ELAPSED=0
    INTERVAL=30
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        # Get status of both jobs
        FULL_STATE=$(oc get lmevaljob mistral-24b-full-eval -n private-ai-demo \
            -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
        QUANT_STATE=$(oc get lmevaljob mistral-24b-quantized-eval -n private-ai-demo \
            -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
        
        echo "$(date +%H:%M:%S) - Full: $FULL_STATE | Quantized: $QUANT_STATE"
        
        # Check if both are complete
        if [ "$FULL_STATE" == "Complete" ] && [ "$QUANT_STATE" == "Complete" ]; then
            log_success "Both evaluations completed!"
            break
        fi
        
        # Check for failures
        if [ "$FULL_STATE" == "Failed" ] || [ "$QUANT_STATE" == "Failed" ]; then
            log_warning "One or more evaluations failed"
            break
        fi
        
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    echo ""
    if [ $ELAPSED -ge $TIMEOUT ]; then
        log_warning "Evaluation timeout reached (${TIMEOUT}s)"
        log_info "Jobs may still be running in background"
    fi
    
    # Display results summary
    echo ""
    log_info "Evaluation Results:"
    echo ""
    
    # Extract and display Full model results
    FULL_RESULTS=$(oc get lmevaljob mistral-24b-full-eval -n private-ai-demo \
        -o jsonpath='{.status.results}' 2>/dev/null || echo "")
    
    if [ -n "$FULL_RESULTS" ]; then
        log_success "Full Precision Model (4 GPUs):"
        echo "$FULL_RESULTS" | jq -r '.results | to_entries[] | "  • \(.key): \(.value.acc_norm // .value.acc // .value["exact_match,flexible-extract"] | (. * 100 | round / 100))%"' 2>/dev/null || \
            echo "  Results available in CR status"
    else
        log_warning "Full model results not yet available"
    fi
    
    echo ""
    
    # Extract and display Quantized model results
    QUANT_RESULTS=$(oc get lmevaljob mistral-24b-quantized-eval -n private-ai-demo \
        -o jsonpath='{.status.results}' 2>/dev/null || echo "")
    
    if [ -n "$QUANT_RESULTS" ]; then
        log_success "Quantized Model (1 GPU):"
        echo "$QUANT_RESULTS" | jq -r '.results | to_entries[] | "  • \(.key): \(.value.acc_norm // .value.acc // .value["exact_match,flexible-extract"] | (. * 100 | round / 100))%"' 2>/dev/null || \
            echo "  Results available in CR status"
    else
        log_warning "Quantized model results not yet available"
    fi
    
    echo ""
    log_info "Detailed results available in:"
    echo "  • LMEvalJob CRs: oc get lmevaljob -n private-ai-demo"
    echo "  • Pod logs: oc logs <pod> -n private-ai-demo"
    echo "  • Documentation: docs/TRUSTYAI-EVAL-RESULTS.md"
    echo ""
    
    log_success "TrustyAI evaluations completed"
}

# Verify deployment
verify_deployment() {
    print_header "Verification"
    
    log_info "Checking deployment status..."
    
    # Check GPU nodes
    GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)
    if [ "$GPU_NODES" -ge 2 ]; then
        log_success "GPU nodes: $GPU_NODES nodes ready"
    else
        log_warning "GPU nodes: Only $GPU_NODES found (expected 2+)"
    fi
    
    # Check namespace
    if oc get namespace private-ai-demo &> /dev/null; then
        log_success "Namespace: private-ai-demo exists"
    else
        log_error "Namespace: private-ai-demo not found"
    fi
    
    # Check InferenceServices
    READY_IS=$(oc get inferenceservice -n private-ai-demo -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
    TOTAL_IS=$(oc get inferenceservice -n private-ai-demo --no-headers 2>/dev/null | wc -l)
    if [ "$READY_IS" -eq "$TOTAL_IS" ] && [ "$TOTAL_IS" -gt 0 ]; then
        log_success "InferenceServices: $READY_IS/$TOTAL_IS ready"
    else
        log_warning "InferenceServices: $READY_IS/$TOTAL_IS ready"
    fi
    
    # Check Model Registry
    if oc get modelregistry private-ai-model-registry -n rhoai-model-registries &> /dev/null; then
        log_success "Model Registry: Deployed"
    else
        log_warning "Model Registry: Not found (optional component)"
    fi
    
    echo ""
    log_info "Deployment Summary:"
    echo "  ├─ GPU Nodes: $GPU_NODES"
    echo "  ├─ InferenceServices: $READY_IS/$TOTAL_IS ready"
    echo "  └─ Namespace: private-ai-demo"
    
    echo ""
    log_info "Access OpenShift AI Dashboard:"
    DASHBOARD_ROUTE=$(oc get route -n redhat-ods-applications -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "Not found")
    echo "  https://$DASHBOARD_ROUTE"
    
    echo ""
    log_info "Check InferenceService URLs:"
    oc get inferenceservice -n private-ai-demo
}

# Print next steps
print_next_steps() {
    print_header "Deployment Complete!"
    
    echo "Next steps:"
    echo ""
    echo "1. Access OpenShift AI Dashboard"
    DASHBOARD_ROUTE=$(oc get route -n redhat-ods-applications -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "Not found")
    echo "   https://$DASHBOARD_ROUTE"
    echo ""
    echo "2. Navigate to: Projects → private-ai-demo → Models"
    echo ""
    echo "3. Test inference endpoints:"
    echo "   oc get inferenceservice -n private-ai-demo"
    echo ""
    echo "4. View benchmark results:"
    echo "   oc logs job/vllm-model-benchmark -n private-ai-demo"
    echo ""
    echo "5. Check Model Registry:"
    echo "   oc get route -n model-registry"
    echo ""
    echo "For troubleshooting, see: stage1-sovereign-ai/README.md"
}

# Main execution
main() {
    print_header "Red Hat AI Demo - Stage 1 Deployment"
    
    log_info "This script will deploy Stage 1: Sovereign AI"
    log_info "Estimated time: 30-45 minutes"
    echo ""
    
    read -p "Continue with deployment? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_warning "Deployment cancelled"
        exit 0
    fi
    
    # Run deployment steps
    check_prerequisites
    check_model_registry_operator  # NEW: Check/install Model Registry Operator
    prompt_for_token
    provision_gpu_nodes
    deploy_base
    download_models
    deploy_inference_services
    run_guidellm_benchmarks
    deploy_model_registry          # NEW: Deploy Model Registry infrastructure
    register_models                # UPDATED: Now uses dynamic URLs
    run_trustyai_evaluations       # NEW: Run TrustyAI LM-Eval
    
    # Deploy Stage 1 demo notebook
    log_info "Deploying Stage 1 demo notebook..."
    if oc apply -f "${GITOPS_DIR}/components/workbench/configmap-notebook-01-stage1.yaml"; then
        log_success "Stage 1 notebook deployed"
        log_info "Notebook will be available in JupyterLab workbench as: 01-vllm-benchmark.ipynb"
        log_warn "Note: Restart the workbench pod to load the new notebook"
    else
        log_warn "Failed to deploy Stage 1 notebook (non-critical)"
    fi
    
    verify_deployment
    print_next_steps
}

# Run main function
main "$@"

