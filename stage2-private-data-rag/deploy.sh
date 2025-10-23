#!/bin/bash

##############################################################################
# Stage 2: Private Data Enhancement with RAG
# 
# This script deploys RAG components following Red Hat's official
# OpenShift AI RAG architecture with Llama Stack.
#
# Supports 3 Demo Scenarios:
#   1. Red Hat OpenShift AI Documentation
#   2. EU AI Act Regulation (Legal/Compliance)
#   3. ACME LithoOps Copilot (Manufacturing)
#
# Architecture:
#   - Milvus (vector database with IBM Granite embeddings)
#   - Llama Stack (RAG orchestration, reusing Stage 1 Mistral model)
#   - Docling (AI-powered document processing)
#   - Tekton Pipelines (automated document ingestion)
#   - JupyterLab Workbench (interactive demos)
#
# Reference:
#   https://docs.redhat.com/en/documentation/red_hat_openshift_ai_cloud_service/1/html/working_with_rag
##############################################################################

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "🔐 Loading configuration from .env file..."
    # Export variables from .env, ignoring comments and empty lines
    set -a
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$' | sed 's/\r$//')
    set +a
    echo "✅ Configuration loaded"
else
    echo "⚠️  No .env file found. Using defaults."
    echo "   To configure: cp env.template .env"
fi
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS_DIR="${PROJECT_ROOT}/gitops"
NAMESPACE="${PROJECT_NAME:-private-ai-demo}"
INFRA_NAMESPACE="ai-infrastructure"

echo "══════════════════════════════════════════════════════════════"
echo "  Stage 2: Private Data Enhancement with RAG"
echo "  Red Hat OpenShift AI + Llama Stack"
echo "══════════════════════════════════════════════════════════════"
echo ""

#============================================================================
# Helper Functions
#============================================================================

check_prerequisite() {
    local cmd=$1
    local name=$2
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Error: $name is required but not installed"
        exit 1
    fi
}

wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=${3:-300}
    
    echo "⏳ Waiting for $deployment to be ready..."
    if oc wait --for=condition=available deployment/"$deployment" -n "$namespace" --timeout="${timeout}s" &> /dev/null; then
        echo "✅ $deployment is ready"
    else
        echo "⚠️  $deployment not ready after ${timeout}s"
    fi
}

wait_for_pod_ready() {
    local app_label=$1
    local namespace=$2
    local timeout=${3:-300}
    
    echo "⏳ Waiting for pod with label app=$app_label to be ready..."
    if oc wait --for=condition=ready pod -l app="$app_label" -n "$namespace" --timeout="${timeout}s" &> /dev/null; then
        echo "✅ Pod is ready"
        return 0
    else
        echo "⚠️  Pod not ready after ${timeout}s"
        return 1
    fi
}

#============================================================================
# Prerequisites Check
#============================================================================

echo "🔍 Checking prerequisites..."
check_prerequisite "oc" "OpenShift CLI (oc)"
check_prerequisite "kubectl" "kubectl"

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo "❌ Error: Not logged in to OpenShift"
    echo "   Run: oc login <cluster-url>"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

#============================================================================
# Stage 1 Verification
#============================================================================

echo "🔍 Verifying Stage 1 deployment..."

# Check namespace
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    echo "❌ Error: Namespace $NAMESPACE not found"
    echo "   Please deploy Stage 1 first: cd ../stage1-sovereign-ai && ./deploy.sh"
    exit 1
fi
echo "✅ Namespace $NAMESPACE exists"

# Check InferenceServices exist
if ! oc get inferenceservice mistral-24b-quantized -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Error: Quantized Mistral model not found"
    echo "   Please deploy Stage 1 first (vLLM models)"
    exit 1
fi

# Check InferenceServices are READY
echo "⏳ Checking InferenceService readiness..."
QUANTIZED_READY=$(oc get inferenceservice mistral-24b-quantized -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

if [ "$QUANTIZED_READY" != "True" ]; then
    echo "❌ Error: Quantized model is not ready"
    echo "   Current status: $QUANTIZED_READY"
    echo "   Check with: oc get inferenceservice mistral-24b-quantized -n $NAMESPACE"
    exit 1
fi
echo "✅ Quantized model is READY"

# Get InferenceService URLs (CRITICAL for Llama Stack config)
echo "📡 Fetching InferenceService URLs..."
export MISTRAL_QUANTIZED_URL=$(oc get ksvc mistral-24b-quantized-predictor -n "$NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null)

if [ -z "$MISTRAL_QUANTIZED_URL" ]; then
    echo "❌ Error: Could not fetch Quantized model URL"
    echo "   Check Knative Service: oc get ksvc -n $NAMESPACE"
    exit 1
fi

echo "✅ Quantized Model URL: $MISTRAL_QUANTIZED_URL"

# Optional: Check Model Registry (not required for Stage 2)
if oc get modelregistry private-ai-model-registry -n rhoai-model-registries &> /dev/null 2>&1; then
    echo "✅ Model Registry operational (optional)"
else
    echo "ℹ️  Model Registry not found (optional for Stage 2)"
fi

echo ""
echo "✅ Stage 1 verification complete - All prerequisites met!"
echo ""

#============================================================================
# Check and Activate Llama Stack Operator
#============================================================================

# Function to wait for CRD to be available
wait_for_crd() {
    local crd_name=$1
    local timeout=${2:-120}
    local elapsed=0
    
    echo "⏳ Waiting for CRD $crd_name (max ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if oc get crd $crd_name &> /dev/null; then
            echo "✅ CRD $crd_name is available"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "   ${elapsed}s elapsed..."
    done
    
    echo "❌ Timeout waiting for CRD $crd_name"
    return 1
}

echo "🔍 Checking Llama Stack Operator status..."

# Check if operator is enabled in DSC
OPERATOR_STATE=$(oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.llamastackoperator.managementState}' 2>/dev/null || echo "NotFound")

if [ "$OPERATOR_STATE" != "Managed" ]; then
    echo "📦 Enabling Llama Stack operator in DataScienceCluster..."
    oc patch datasciencecluster default-dsc --type merge \
        --patch '{"spec":{"components":{"llamastackoperator":{"managementState":"Managed"}}}}'
    
    # Wait for CRD to be created
    if ! wait_for_crd "llamastackdistributions.llamastack.io" 120; then
        echo "❌ Failed to enable Llama Stack operator"
        exit 1
    fi
else
    echo "✅ Llama Stack operator already enabled"
    # Verify CRD exists
    if ! oc get crd llamastackdistributions.llamastack.io &> /dev/null; then
        echo "⚠️  CRD not found, waiting..."
        wait_for_crd "llamastackdistributions.llamastack.io" 60
    fi
fi

echo ""

#============================================================================
# Deploy Shared Infrastructure
#============================================================================

echo "══════════════════════════════════════════════════════════════"
echo "  Step 1: Deploy Shared Infrastructure"
echo "══════════════════════════════════════════════════════════════"
echo ""

# Create infrastructure namespace
if ! oc get namespace "$INFRA_NAMESPACE" &> /dev/null; then
    echo "📦 Creating infrastructure namespace..."
    oc create namespace "$INFRA_NAMESPACE"
    echo "✅ Namespace created"
fi

# Deploy Milvus
echo ""
echo "📦 Deploying Milvus vector database..."
oc apply -k ${GITOPS_DIR}/components/milvus

wait_for_deployment "milvus-standalone" "$INFRA_NAMESPACE" 300

# Deploy Docling operator
echo ""
echo "📦 Deploying Docling operator..."
oc apply -k ${GITOPS_DIR}/components/docling-operator

# Wait for Docling CRD to be available
if ! wait_for_crd "doclingserves.docling.github.io" 120; then
    echo "❌ Docling operator failed to install"
    exit 1
fi

echo "📦 Deploying Docling service..."
# Now apply the DoclingServe CR
oc apply -f ${GITOPS_DIR}/components/docling-operator/doclingserve-cr.yaml

wait_for_deployment "shared-docling-service" "$INFRA_NAMESPACE" 300

# Deploy Llama Stack with dynamic URL injection
echo ""
echo "📦 Deploying Llama Stack with cluster-specific configuration..."

# Create temporary directory for patched manifests
TMP_DIR=$(mktemp -d)
echo "   Using temp dir: $TMP_DIR"

# Copy ConfigMap and apply envsubst to inject dynamic URLs
echo "   Injecting InferenceService URL: $MISTRAL_QUANTIZED_URL"
cat ${GITOPS_DIR}/components/llama-stack/configmap.yaml | \
    envsubst > $TMP_DIR/configmap-patched.yaml

# Apply patched ConfigMap
oc apply -f $TMP_DIR/configmap-patched.yaml

# Apply other Llama Stack resources (without ConfigMap to avoid conflict)
echo "   Deploying Llama Stack resources..."
oc apply -f ${GITOPS_DIR}/components/llama-stack/pvc.yaml
oc apply -f ${GITOPS_DIR}/components/llama-stack/llamastack-distribution.yaml
oc apply -f ${GITOPS_DIR}/components/llama-stack/service.yaml
oc apply -f ${GITOPS_DIR}/components/llama-stack/route.yaml

# Cleanup temp dir
rm -rf $TMP_DIR

echo "⏳ Waiting for Llama Stack pod to be ready (this may take 2-3 minutes)..."
sleep 30
wait_for_pod_ready "llama-stack" "$NAMESPACE" 600

echo ""
echo "✅ Shared infrastructure deployed!"
echo ""

#============================================================================
# Enable Observability (Optional)
#============================================================================

read -p "Enable Observability (Prometheus + Grafana)? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  Step 1.5: Observability Setup (Optional)"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    
    # Enable OpenShift User Workload Monitoring (cluster-wide, one-time)
    echo "📊 Checking User Workload Monitoring status..."
    if ! oc get configmap cluster-monitoring-config -n openshift-monitoring &>/dev/null || \
       ! oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml 2>/dev/null | grep -q "enableUserWorkload: true"; then
        echo "   Enabling OpenShift User Workload Monitoring..."
        cat <<MONITORING_EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
MONITORING_EOF
        echo "   ✅ User Workload Monitoring enabled"
        
        echo "   ⏳ Waiting for monitoring stack to deploy (60 seconds)..."
        sleep 60
        
        # Verify monitoring pods
        echo "   Checking monitoring pods..."
        oc get pods -n openshift-user-workload-monitoring 2>/dev/null | head -5 || echo "   Pods are starting..."
    else
        echo "   ✅ User Workload Monitoring already enabled"
    fi
    
    echo ""
    echo "📊 ServiceMonitor for Llama Stack is already deployed via GitOps"
    echo "   Location: gitops/components/llama-stack/servicemonitor.yaml"
    echo "   ✅ Metrics collection is configured"
    
    echo ""
    
    # Deploy Grafana (optional)
    read -p "Deploy Grafana for visualization? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        echo "📊 Deploying Grafana..."
        
        # Create grafana-system namespace
        if ! oc get namespace grafana-system &>/dev/null; then
            echo "   Creating grafana-system namespace..."
            oc create namespace grafana-system
            echo "   ✅ Namespace created"
        else
            echo "   ✅ Namespace grafana-system already exists"
        fi
        
        # Deploy Grafana components using Kustomize
        echo "   Deploying Grafana with pre-configured dashboards..."
        oc apply -k ${GITOPS_DIR}/components/observability
        
        echo "   ⏳ Waiting for Grafana to be ready..."
        sleep 30
        
        # Wait for deployment
        if oc wait --for=condition=available deployment/grafana -n grafana-system --timeout=180s &>/dev/null; then
            GRAFANA_URL=$(oc get route grafana -n grafana-system -o jsonpath='{.spec.host}' 2>/dev/null)
            echo ""
            echo "   ════════════════════════════════════════════════════════════════"
            echo "   ✅ GRAFANA DEPLOYED SUCCESSFULLY!"
            echo "   ════════════════════════════════════════════════════════════════"
            echo ""
            echo "   🌐 URL: https://${GRAFANA_URL}"
            echo ""
            echo "   🔐 Login Credentials:"
            echo "      Username: admin"
            echo "      Password: admin123"
            echo ""
            echo "   📊 Dashboard: Llama Stack Overview"
            echo "      Navigate to: Dashboards → Browse → Llama Stack Overview"
            echo ""
            echo "   📖 Documentation:"
            echo "      Quick Start: docs/GRAFANA-QUICK-START.md"
            echo "      Setup Guide: docs/OBSERVABILITY-SETUP.md"
            echo ""
        else
            echo "   ⚠️  Grafana taking longer than expected"
            echo "   Check status: oc get pods -n grafana-system"
            echo "   View logs: oc logs -n grafana-system -l app=grafana"
        fi
    else
        echo ""
        echo "   ℹ️  Skipping Grafana deployment"
        echo "   Note: Metrics are still being collected by Prometheus"
        echo "   Access metrics via: OpenShift Console → Observe → Metrics"
    fi
    
    echo ""
    echo "✅ Observability setup complete!"
    echo ""
    echo "💡 Quick Access:"
    echo "   • Prometheus: OpenShift Console → Observe → Metrics"
    echo "   • Grafana: https://$(oc get route grafana -n grafana-system -o jsonpath='{.spec.host}' 2>/dev/null || echo 'not-deployed')"
    echo "   • ServiceMonitor: oc get servicemonitor llama-stack -n ${NAMESPACE}"
    echo ""
else
    echo ""
    echo "ℹ️  Skipping observability setup"
    echo "   You can enable it later by running the observability section of this script"
    echo "   or manually: oc apply -k gitops/components/observability"
    echo ""
fi

#============================================================================
# Deploy Common Tekton Tasks
#============================================================================

echo "══════════════════════════════════════════════════════════════"
echo "  Step 2: Deploy Tekton Pipeline Components"
echo "══════════════════════════════════════════════════════════════"
echo ""

echo "📦 Deploying common Tekton tasks..."
oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-docling-process-pure-async.yaml
oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-chunk-documents.yaml
oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-ingest-to-milvus.yaml

# Create PVC for RAG documents
if ! oc get pvc rag-documents -n "$NAMESPACE" &> /dev/null; then
    echo "📦 Creating PVC for RAG documents..."
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rag-documents
  namespace: $NAMESPACE
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF
    echo "✅ PVC created"
fi

echo "✅ Common pipeline components deployed!"
echo ""

#============================================================================
# Deploy JupyterLab Workbench
#============================================================================

echo "══════════════════════════════════════════════════════════════"
echo "  Step 3: Deploy JupyterLab Workbench"
echo "══════════════════════════════════════════════════════════════"
echo ""

echo "📦 Deploying workbench with all 3 demo notebooks..."

# First, generate notebooks with current cluster URLs
echo "   🔄 Generating notebooks with cluster-specific URLs..."
export VLLM_URL="${MISTRAL_QUANTIZED_URL}/v1"
export LLAMASTACK_URL="http://llamastack.${NAMESPACE}.svc.cluster.local:8321"

echo "   📡 vLLM URL: ${VLLM_URL}"
echo "   📡 Llama Stack URL: ${LLAMASTACK_URL}"

# Create temporary directory for generated notebooks
TMP_NOTEBOOKS_DIR=$(mktemp -d)
echo "   📂 Temp dir: ${TMP_NOTEBOOKS_DIR}"

# Generate notebook ConfigMaps with actual URLs using Python for proper JSON handling
for notebook_template in notebooks/templates/*.ipynb.template; do
    if [ -f "$notebook_template" ]; then
        notebook_name=$(basename "$notebook_template" .ipynb.template)
        echo "   ✏️  Generating ${notebook_name}.ipynb..."
        
        # Use Python to properly inject URLs into JSON without breaking structure
        python3 -c "
import json
import sys

with open('$notebook_template', 'r') as f:
    content = f.read()

# Replace placeholders
content = content.replace('\${VLLM_URL}', '$VLLM_URL')
content = content.replace('\${LLAMASTACK_URL}', '$LLAMASTACK_URL')

# Validate and write JSON
notebook = json.loads(content)
with open('${TMP_NOTEBOOKS_DIR}/${notebook_name}.ipynb', 'w') as f:
    json.dump(notebook, f, indent=2)
"
    fi
done

# Apply workbench components (excluding notebooks first)
echo "   📦 Deploying workbench base components..."
oc apply -f ${GITOPS_DIR}/components/workbench/serviceaccount.yaml
oc apply -f ${GITOPS_DIR}/components/workbench/rolebinding.yaml
oc apply -f ${GITOPS_DIR}/components/workbench/pvc.yaml
oc apply -f ${GITOPS_DIR}/components/workbench/notebook.yaml

# Generate and apply notebook ConfigMaps dynamically
echo "   📝 Creating ConfigMaps with generated notebooks..."
for notebook_file in ${TMP_NOTEBOOKS_DIR}/*.ipynb; do
    if [ -f "$notebook_file" ]; then
        notebook_name=$(basename "$notebook_file" .ipynb)
        configmap_name="notebook-${notebook_name}"
        
        echo "      Creating ConfigMap: ${configmap_name}..."
        oc create configmap "${configmap_name}" \
            --from-file=notebook.ipynb="${notebook_file}" \
            -n "${NAMESPACE}" \
            --dry-run=client -o yaml | \
            oc apply -f -
    fi
done

# Clean up temp directory
rm -rf "${TMP_NOTEBOOKS_DIR}"
echo "   ✅ Notebooks generated and deployed!"

echo "⏳ Waiting for workbench to be ready (this may take 2-3 minutes)..."
sleep 60

if oc wait --for=condition=ready pod -l statefulset.kubernetes.io/pod-name=rag-testing-0 -n "$NAMESPACE" --timeout=300s &> /dev/null; then
    echo "✅ Workbench is ready!"
else
    echo "⚠️  Workbench taking longer than expected, check: oc get pods -n $NAMESPACE"
fi

echo ""

#============================================================================
# Helper Functions for Document Upload and Pipeline Execution
#============================================================================

# Function to upload documents to PVC
upload_documents() {
    local scenario=$1
    local source_dir=$2
    
    echo "📤 Uploading documents for $scenario..."
    
    # Create temporary uploader pod
    cat <<UPLOAD_EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pvc-uploader-${scenario}
  namespace: ${NAMESPACE}
spec:
  containers:
  - name: uploader
    image: registry.redhat.io/ubi8/ubi:latest
    command: ["sleep", "3600"]
    volumeMounts:
    - name: documents
      mountPath: /workspace/documents
  volumes:
  - name: documents
    persistentVolumeClaim:
      claimName: rag-documents-pvc
UPLOAD_EOF
    
    # Wait for uploader pod
    echo "   Waiting for uploader pod..."
    oc wait --for=condition=Ready pod/pvc-uploader-${scenario} -n "${NAMESPACE}" --timeout=90s
    
    # Create directory
    oc exec -n "${NAMESPACE}" pvc-uploader-${scenario} -- mkdir -p /workspace/documents/${scenario}
    
    # Upload files
    for file in "${source_dir}"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            echo "   Uploading $filename..."
            oc cp "$file" "${NAMESPACE}/pvc-uploader-${scenario}:/workspace/documents/${scenario}/$filename"
        fi
    done
    
    # Verify upload
    echo "   Verifying upload..."
    oc exec -n "${NAMESPACE}" pvc-uploader-${scenario} -- ls -lh /workspace/documents/${scenario}/
    
    # Clean up uploader pod
    oc delete pod pvc-uploader-${scenario} -n "${NAMESPACE}" --wait=false
    
    echo "✅ Documents uploaded for $scenario"
}

# Function to trigger a pipeline
trigger_pipeline() {
    local pipeline_name=$1
    local scenario_name=$2
    local collection_name=$3
    
    echo "🚀 Triggering pipeline: $pipeline_name"
    
    cat <<PIPELINE_EOF | oc create -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: ${pipeline_name}-
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/part-of: llama-stack
    demo.redhat.com/scenario: ${scenario_name}
spec:
  pipelineRef:
    name: ${pipeline_name}
  params:
    - name: scenario-name
      value: "${scenario_name}"
    - name: collection-name
      value: "${collection_name}"
    - name: docling-service-url
      value: "http://shared-docling-service.${NAMESPACE}.svc.cluster.local:5000"
    - name: milvus-service-url
      value: "http://milvus-standalone.ai-infrastructure.svc.cluster.local:19530"
    - name: llamastack-service-url
      value: "http://llama-stack.${NAMESPACE}.svc.cluster.local:8000"
  workspaces:
    - name: documents
      persistentVolumeClaim:
        claimName: rag-documents-pvc
  timeouts:
    pipeline: "1h0m0s"
PIPELINE_EOF
    
    # Get the PipelineRun name
    sleep 2
    PIPELINERUN_NAME=$(oc get pipelinerun -n "${NAMESPACE}" -l demo.redhat.com/scenario=${scenario_name} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
    
    if [ -n "$PIPELINERUN_NAME" ]; then
        echo "   Started: $PIPELINERUN_NAME"
        echo "   Monitor with: oc get pipelinerun $PIPELINERUN_NAME -n ${NAMESPACE} -w"
    fi
}

#============================================================================
# Scenario Selection Menu
#============================================================================

echo "══════════════════════════════════════════════════════════════"
echo "  Step 4: Select Demo Scenarios to Deploy"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "Available Scenarios:"
echo "  1. Red Hat OpenShift AI Documentation"
echo "  2. EU AI Act Regulation (Legal/Compliance)"
echo "  3. ACME LithoOps Copilot (Manufacturing)"
echo "  A. All scenarios"
echo ""
read -p "Select scenarios to deploy (e.g., 1,2 or A for all): " scenario_choice

DEPLOY_REDHAT=false
DEPLOY_EU_AI_ACT=false
DEPLOY_ACME=false

case "$scenario_choice" in
    *A*|*a*|*all*|*ALL*)
        DEPLOY_REDHAT=true
        DEPLOY_EU_AI_ACT=true
        DEPLOY_ACME=true
        ;;
    *)
        [[ "$scenario_choice" =~ 1 ]] && DEPLOY_REDHAT=true
        [[ "$scenario_choice" =~ 2 ]] && DEPLOY_EU_AI_ACT=true
        [[ "$scenario_choice" =~ 3 ]] && DEPLOY_ACME=true
        ;;
esac

#============================================================================
# Document Upload and Pipeline Execution
#============================================================================

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Document Upload & Pipeline Execution"
echo "══════════════════════════════════════════════════════════════"
echo ""

# Scenario 1: Red Hat Documentation
if [ "$DEPLOY_REDHAT" = true ]; then
    echo "📋 Scenario 1: Red Hat Documentation"
    if [ -d "documents/scenario1" ]; then
        upload_documents "scenario2-redhat" "documents/scenario1"
        trigger_pipeline "redhat-document-ingestion" "scenario2-redhat" "redhat-docs"
    else
        echo "⚠️  Documents not found: documents/scenario1"
        echo "   Skipping Red Hat pipeline"
    fi
    echo ""
fi

# Scenario 2: EU AI Act
if [ "$DEPLOY_EU_AI_ACT" = true ]; then
    echo "📋 Scenario 2: EU AI Act Regulation"
    if [ -d "documents/scenario2-eu-ai-act" ]; then
        upload_documents "scenario2-eu-ai-act" "documents/scenario2-eu-ai-act"
        trigger_pipeline "rag-document-ingestion-simple" "scenario2-eu-ai-act" "eu-ai-act-docs"
    else
        echo "⚠️  Documents not found: documents/scenario2-eu-ai-act"
        echo "   Skipping EU AI Act pipeline"
    fi
    echo ""
fi

# Scenario 3: ACME Manufacturing
if [ "$DEPLOY_ACME" = true ]; then
    echo "📋 Scenario 3: ACME Manufacturing"
    if [ -d "documents/scenario2-acme/pdfs" ]; then
        # ACME has special path requirements: pipeline expects /workspace/documents/acme/pdfs
        # We need to upload to the correct location
        echo "   📂 ACME documents require special path structure"
        echo "   Source: documents/scenario2-acme/pdfs/"
        echo "   Target: /workspace/documents/acme/pdfs/"
        
        # Upload ACME PDFs to the correct location expected by pipeline
        upload_documents "acme" "documents/scenario2-acme/pdfs"
        
        # Trigger pipeline with scenario-name "acme" (not "scenario2-acme")
        trigger_pipeline "acme-document-ingestion" "acme" "acme-manufacturing"
    else
        echo "⚠️  Documents not found: documents/scenario2-acme/pdfs"
        echo "   Skipping ACME pipeline"
    fi
    echo ""
fi

echo "✅ Document upload and pipeline triggers complete"
echo ""
echo "📊 To monitor pipeline execution:"
echo "   oc get pipelinerun -n ${NAMESPACE}"
echo "   oc get pipelinerun -n ${NAMESPACE} -w  # Watch mode"
echo ""
echo "Note: Pipelines will run in background. Check status before using notebooks."
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ Stage 2 Deployment Complete!"
echo "══════════════════════════════════════════════════════════════"

# Skip the old scenario deployment sections below (wrapped to not execute)
if false; then
    # OLD CODE - keeping for reference but not executing

#============================================================================
# Scenario 1: Red Hat Documentation (OLD - REPLACED BY FUNCTIONS ABOVE)
#============================================================================

if [ "$DEPLOY_REDHAT" = true ]; then
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  Deploying Scenario 1: Red Hat OpenShift AI Documentation"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    
    # Upload Red Hat document to PVC
    echo "📤 Uploading Red Hat documentation to PVC..."
    
    # Create temporary pod
    cat <<EOF_OLD | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pvc-uploader-redhat
  namespace: $NAMESPACE
spec:
  containers:
  - name: uploader
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: documents
      mountPath: /workspace/documents
  volumes:
  - name: documents
    persistentVolumeClaim:
      claimName: rag-documents
EOF_OLD
    
    echo "⏳ Waiting for uploader pod..."
    sleep 15
    
    # Create directory and upload
    oc exec -n "$NAMESPACE" pvc-uploader-redhat -- mkdir -p /workspace/documents/scenario2-redhat
    oc cp stage2-private-data-rag/documents/scenario1/rhoai-rag-guide.pdf \
        "$NAMESPACE"/pvc-uploader-redhat:/workspace/documents/scenario2-redhat/rhoai-rag-guide.pdf
    
    echo "✅ Document uploaded"
    
    # Clean up uploader pod
    oc delete pod pvc-uploader-redhat -n "$NAMESPACE" --ignore-not-found=true
    
    # Deploy and run pipeline
    echo "📦 Deploying Red Hat ingestion pipeline..."
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/pipeline-redhat-ingestion.yaml
    
    echo "🚀 Starting Red Hat document ingestion..."
    cat <<EOF | oc apply -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: redhat-ingestion-$(date +%s)
  namespace: $NAMESPACE
spec:
  pipelineRef:
    name: redhat-document-ingestion
  workspaces:
  - name: documents
    persistentVolumeClaim:
      claimName: rag-documents
EOF
    
    echo "✅ Red Hat pipeline started"
    echo "   Monitor: oc get pipelinerun -n $NAMESPACE | grep redhat"
fi

#============================================================================
# Scenario 2: EU AI Act
#============================================================================

if [ "$DEPLOY_EU_AI_ACT" = true ]; then
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  Deploying Scenario 2: EU AI Act Regulation"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    
    echo "⚠️  Note: EU AI Act documents are already in the repository"
    echo "   Location: stage2-private-data-rag/documents/scenario2-eu-ai-act/"
    echo ""
    
    # These documents should already be in the repo, but we can optionally upload
    echo "📦 Deploying EU AI Act pipeline tasks..."
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-prepare-documents.yaml
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-extract-metadata.yaml
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/pipeline-rag-ingestion-simple.yaml
    
    echo "✅ EU AI Act pipeline ready"
    echo "   To run: Deploy via GitOps or manually trigger PipelineRun"
fi

#============================================================================
# Scenario 3: ACME LithoOps
#============================================================================

if [ "$DEPLOY_ACME" = true ]; then
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  Deploying Scenario 3: ACME LithoOps Copilot"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    
    echo "📦 Deploying ACME pipeline tasks..."
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-docling-process-acme.yaml
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-extract-acme-metadata.yaml
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-chunk-acme-documents.yaml
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/task-ingest-acme-to-milvus.yaml
    oc apply -f ${GITOPS_DIR}/components/docling-pipeline/pipeline-acme-ingestion.yaml
    
    echo "✅ ACME pipeline ready"
    echo "   To run: Deploy via GitOps or manually trigger PipelineRun"
fi

#============================================================================
# Deployment Complete
#============================================================================

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ Stage 2 Deployment Complete!"
echo "══════════════════════════════════════════════════════════════"
echo ""

# Show deployed scenarios
echo "📊 Deployed Scenarios:"
[ "$DEPLOY_REDHAT" = true ] && echo "  ✅ Scenario 1: Red Hat Documentation"
[ "$DEPLOY_EU_AI_ACT" = true ] && echo "  ✅ Scenario 2: EU AI Act Regulation"
[ "$DEPLOY_ACME" = true ] && echo "  ✅ Scenario 3: ACME LithoOps Copilot"
echo ""

echo "🎯 Components Deployed:"
echo "  ✅ Milvus vector database (768-dim IBM Granite embeddings)"
echo "  ✅ Docling service (AI-powered PDF processing)"
echo "  ✅ Llama Stack (RAG orchestration)"
echo "  ✅ Tekton pipelines (document ingestion)"
echo "  ✅ JupyterLab workbench (all 3 demo notebooks)"
echo ""

echo "📓 Access Workbench:"
WORKBENCH_URL=$(oc get route rag-testing -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$WORKBENCH_URL" ]; then
    echo "  🌐 https://$WORKBENCH_URL"
    echo ""
    echo "  Available Notebooks:"
    [ "$DEPLOY_REDHAT" = true ] && echo "  📔 02-rag-demo-redhat.ipynb"
    [ "$DEPLOY_EU_AI_ACT" = true ] && echo "  📔 03-rag-demo-eu-ai-act.ipynb"
    [ "$DEPLOY_ACME" = true ] && echo "  📔 04-rag-demo-acme-litho.ipynb"
else
    echo "  ⚠️  Route not found - check: oc get route -n $NAMESPACE"
fi

echo ""
echo "📊 Pipeline Status:"
echo "  oc get pipelinerun -n $NAMESPACE"
echo ""

echo "🔧 Llama Stack Service:"
echo "  Internal: http://llama-stack-service.$NAMESPACE.svc:8321"
echo "  Health: oc exec -n $NAMESPACE -l app=llama-stack -- curl -s http://localhost:8321/health"
echo ""

echo "📚 Documentation:"
echo "  📖 Main README: stage2-private-data-rag/README.md"
[ "$DEPLOY_REDHAT" = true ] && echo "  📖 Scenario 1: stage2-private-data-rag/README-redhat.md"
[ "$DEPLOY_EU_AI_ACT" = true ] && echo "  📖 Scenario 2: stage2-private-data-rag/README-eu-ai-act.md"
[ "$DEPLOY_ACME" = true ] && echo "  📖 Scenario 3: stage2-private-data-rag/README-acme.md"
echo "  📖 GitOps: gitops/components/{milvus,llama-stack,docling-pipeline}/"
echo ""

echo "🔗 References:"
echo "  • Red Hat RAG Guide: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_cloud_service/1/html/working_with_rag"
echo "  • Llama Stack Demos: https://github.com/opendatahub-io/llama-stack-demos"
echo "  • Docling: https://github.com/DS4SD/docling"
echo ""

echo "══════════════════════════════════════════════════════════════"
fi
