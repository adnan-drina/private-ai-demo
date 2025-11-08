#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 2: Model Alignment with RAG + Llama Stack (KFP v2)
# ENHANCED VERSION - Fully Automated Deployment
#
# Deploys:
#   - Milvus vector database
#   - Llama Stack orchestrator (connects to vLLM + Milvus)
#   - Docling document processing
#   - KFP v2 (Data Science Pipelines Application - DSPA)
#
# Prerequisites:
#   - Stage 0 and Stage 1 deployed
#   - MinIO running in model-storage namespace
#   - vLLM InferenceServices running
#   - .env file with MinIO credentials
#
# Automated:
#   - Operator activation (LlamaStack, Docling)
#   - Dynamic vLLM URL detection
#   - Cluster-specific configuration
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GITOPS_PATH="${PROJECT_ROOT}/gitops/stage02-model-alignment"
ENV_FILE="${PROJECT_ROOT}/.env"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2: Model Alignment with RAG + KFP v2 (Enhanced)"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Load environment variables from project root
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ ERROR: .env file not found at $ENV_FILE"
    echo "   Please create .env at project root with:"
    echo "     PROJECT_NAME=private-ai-demo"
    echo "     MINIO_ENDPOINT=minio.model-storage.svc.cluster.local:9000"
    echo "     MINIO_ACCESS_KEY=<from stage00>"
    echo "     MINIO_SECRET_KEY=<from stage00>"
    echo "     MINIO_KFP_BUCKET=kfp-artifacts"
    echo ""
    echo "   Get MinIO credentials from stage00:"
    echo "   oc get secret minio-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d"
    echo "   oc get secret minio-credentials -n model-storage -o jsonpath='{.data.secretkey}' | base64 -d"
    exit 1
fi

echo "📄 Loading configuration from .env (project root)..."
# shellcheck source=/dev/null
source "$ENV_FILE"

# Set defaults if not provided
PROJECT_NAME="${PROJECT_NAME:-private-ai-demo}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-minio.model-storage.svc.cluster.local:9000}"
MINIO_KFP_BUCKET="${MINIO_KFP_BUCKET:-kfp-artifacts}"

# Validate required variables
if [ -z "${MINIO_ACCESS_KEY:-}" ] || [ -z "${MINIO_SECRET_KEY:-}" ]; then
    echo "❌ ERROR: MINIO_ACCESS_KEY and MINIO_SECRET_KEY must be set in .env"
    echo "   Get them from stage00 secret:"
    echo "   oc get secret minio-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d"
    echo "   oc get secret minio-credentials -n model-storage -o jsonpath='{.data.secretkey}' | base64 -d"
    exit 1
fi

echo "✅ Configuration loaded"
echo "   Project: $PROJECT_NAME"
echo "   MinIO: $MINIO_ENDPOINT"
echo "   KFP Bucket: $MINIO_KFP_BUCKET"
echo ""

# NEW: Step -2: Verify Prerequisites
echo "══════════════════════════════════════════════════════════════════"
echo "Step -2: Verify Prerequisites"
echo "══════════════════════════════════════════════════════════════════"
echo ""

echo "🔍 Checking Stage 0 (MinIO)..."
if ! oc get deployment minio -n model-storage &>/dev/null; then
    echo "❌ ERROR: MinIO not found in model-storage namespace"
    echo "   Please deploy Stage 0 first"
    exit 1
fi
echo "   ✅ MinIO found"

echo "🔍 Checking MinIO credentials secret..."
if ! oc get secret minio-credentials -n model-storage &>/dev/null; then
    echo "❌ ERROR: minio-credentials secret not found in model-storage namespace"
    echo "   Please ensure Stage 0 is properly deployed"
    exit 1
fi
echo "   ✅ MinIO credentials secret exists"

echo "🔍 Checking Stage 1 (vLLM InferenceServices)..."
if ! oc get isvc mistral-24b-quantized -n "${PROJECT_NAME}" &>/dev/null; then
    echo "⚠️  WARNING: mistral-24b-quantized InferenceService not found"
    echo "   Stage 1 may not be deployed. LlamaStack will not have inference providers."
    VLLM_MISSING=true
else
    echo "   ✅ Quantized vLLM found"
    VLLM_MISSING=false
fi

if ! oc get isvc mistral-24b -n "${PROJECT_NAME}" &>/dev/null; then
    echo "⚠️  WARNING: mistral-24b (full) InferenceService not found"
    echo "   Full precision model not available."
else
    echo "   ✅ Full vLLM found"
fi

echo ""
echo "✅ Prerequisites verified"
echo ""

# NEW: Step -1: Ensure Operators are Installed and Activated
echo "══════════════════════════════════════════════════════════════════"
echo "Step -1: Ensure Required Operators are Active"
echo "══════════════════════════════════════════════════════════════════"
echo ""

echo "🔧 Checking RHOAI / OpenDataHub operator..."
if ! oc get crd datascienceclusters.datasciencecluster.opendatahub.io &>/dev/null; then
    echo "❌ ERROR: RHOAI / OpenDataHub operator not installed"
    echo "   Please install Red Hat OpenShift AI 2.25+ first"
    exit 1
fi
echo "   ✅ RHOAI operator found"

echo "🔧 Checking LlamaStack Operator..."
if ! oc get crd llamastackdistributions.llamastack.opendatahub.io &>/dev/null; then
    echo "⚠️  LlamaStack CRD not found. Attempting to activate operator..."
    
    # Try to activate LlamaStack operator in DataScienceCluster
    if oc get datasciencecluster default-dsc &>/dev/null; then
        echo "   Activating LlamaStack operator in DataScienceCluster..."
        oc patch datasciencecluster default-dsc --type merge \
          --patch '{"spec":{"components":{"llamastack":{"managementState":"Managed"}}}}' 2>&1 || true
        
        echo "   Waiting for operator to be ready (max 60 seconds)..."
        for i in {1..12}; do
            if oc get crd llamastackdistributions.llamastack.opendatahub.io &>/dev/null; then
                echo "   ✅ LlamaStack operator activated!"
                break
            fi
            if [ $i -eq 12 ]; then
                echo "❌ ERROR: LlamaStack operator did not become ready"
                echo "   Please enable it manually in RHOAI dashboard or wait longer"
                exit 1
            fi
            sleep 5
        done
    else
        echo "❌ ERROR: DataScienceCluster not found"
        echo "   Cannot activate LlamaStack operator automatically"
        echo "   Please activate it manually in RHOAI dashboard"
        exit 1
    fi
else
    echo "   ✅ LlamaStack operator already active"
fi

echo "🔧 Checking Docling Operator..."
if ! oc get crd doclingserves.docling.io &>/dev/null; then
    echo "⚠️  Docling CRD not found. Attempting to install operator..."
    
    # Try to install Docling operator
    echo "   Installing Docling operator from GitHub..."
    
    # Create temporary files for operator installation
    TEMP_DIR=$(mktemp -d)
    
    # Install via OLM if available
    if oc get crd subscriptions.operators.coreos.com &>/dev/null; then
        # Create namespace for operator if needed
        oc create namespace docling-operator-system --dry-run=client -o yaml | oc apply -f - 2>&1 || true
        
        echo "   ⚠️  Docling operator requires manual installation via OperatorHub"
        echo "   Please install 'Docling Operator' from OperatorHub in OpenShift Console"
        echo "   Or follow: https://github.com/docling-project/docling-operator"
        echo ""
        echo "   Continuing without Docling operator (DoclingServe won't deploy)..."
        DOCLING_MISSING=true
    else
        echo "❌ ERROR: OLM not available, cannot install operators"
        exit 1
    fi
    
    rm -rf "$TEMP_DIR"
else
    echo "   ✅ Docling operator already installed"
    DOCLING_MISSING=false
fi

echo "🔧 Checking Data Science Pipelines (KFP) Operator..."
if ! oc get crd datasciencepipelinesapplications.opendatahub.io &>/dev/null; then
    echo "❌ ERROR: DSPA CRD not found"
    echo "   KFP operator not installed or not ready"
    echo "   This is included in RHOAI, please ensure RHOAI is fully deployed"
    exit 1
fi
echo "   ✅ DSPA operator found"

echo ""
echo "✅ Operators verified"
echo ""

# Step 0: Ensure Red Hat registry pull secret available in namespace
echo "──────────────────────────────────────────────────────────────────"
echo "Step 0: Ensure Red Hat registry pull secret in namespace ($PROJECT_NAME)"
echo "──────────────────────────────────────────────────────────────────"
echo ""

if oc get secret pull-secret -n openshift-config >/dev/null 2>&1; then
  echo "🔐 Copying cluster pull-secret to namespace as redhat-pull-secret"
  DATA=$(oc get secret pull-secret -n openshift-config -o jsonpath='{.data\.\.dockerconfigjson}' || true)
  if [ -n "$DATA" ]; then
    TMP=$(mktemp)
    echo "$DATA" | base64 -d > "$TMP"
    oc create secret generic redhat-pull-secret \
      -n "$PROJECT_NAME" \
      --type=kubernetes.io/dockerconfigjson \
      --from-file=.dockerconfigjson="$TMP" \
      --dry-run=client -o yaml | oc apply -f -
    rm -f "$TMP"
    echo "✅ redhat-pull-secret ensured"
  else
    echo "⚠️  Could not read .dockerconfigjson from openshift-config/pull-secret"
  fi
else
  echo "⚠️  Global pull-secret not found; ensure registry.redhat.io credentials are configured cluster-wide"
fi


# Step 1: Create MinIO bucket for KFP artifacts
echo "──────────────────────────────────────────────────────────────────"
echo "Step 1: Create MinIO bucket for KFP artifacts"
echo "──────────────────────────────────────────────────────────────────"
echo ""

# Check if mc (MinIO client) is available
if ! command -v mc &> /dev/null; then
    echo "⚠️  MinIO client (mc) not found. Skipping bucket creation."
    echo "   Install mc from: https://min.io/docs/minio/linux/reference/minio-mc.html"
    echo "   Or create bucket manually in MinIO console"
else
    echo "🪣 Setting up MinIO alias..."
    mc alias set minio-local "http://${MINIO_ENDPOINT}" \
        "${MINIO_ACCESS_KEY}" \
        "${MINIO_SECRET_KEY}" \
        --api S3v4 2>/dev/null || true
    
    echo "🪣 Creating bucket: $MINIO_KFP_BUCKET"
    mc mb "minio-local/${MINIO_KFP_BUCKET}" --ignore-existing 2>/dev/null || \
        echo "   Bucket already exists or accessible"
    
    echo "✅ MinIO bucket ready"
fi

echo ""

# Step 2: Create MinIO credentials secrets
echo "──────────────────────────────────────────────────────────────────"
echo "Step 2: Create MinIO credentials secrets"
echo "──────────────────────────────────────────────────────────────────"
echo ""

echo "🔐 Creating secret: dspa-minio-credentials (for KFP artifacts)"
oc create secret generic dspa-minio-credentials \
    -n "${PROJECT_NAME}" \
    --from-literal=accesskey="${MINIO_ACCESS_KEY}" \
    --from-literal=secretkey="${MINIO_SECRET_KEY}" \
    --dry-run=client -o yaml | oc apply -f -

echo ""
echo "🔐 Creating secret: llama-files-credentials (for LlamaStack Files API)"
# Copy credentials from model-storage namespace (source of truth)
ACCESS=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' 2>/dev/null | base64 -d || echo "${MINIO_ACCESS_KEY}")
SECRET=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' 2>/dev/null | base64 -d || echo "${MINIO_SECRET_KEY}")

oc -n "${PROJECT_NAME}" create secret generic llama-files-credentials \
  --from-literal=accesskey="$ACCESS" \
  --from-literal=secretkey="$SECRET" \
  --dry-run=client -o yaml | oc apply -f -

echo "✅ Secrets created"
echo ""

# Step 3: Configure SCC permissions for LlamaStack
echo "──────────────────────────────────────────────────────────────────"
echo "Step 3: Configure SCC permissions for LlamaStack"
echo "──────────────────────────────────────────────────────────────────"
echo ""

echo "🔐 Granting anyuid SCC to llama-stack ServiceAccount..."
echo "   Note: Required for LlamaStack components (Operator sets fsGroup: 0)"
oc adm policy add-scc-to-user anyuid -z llama-stack -n "${PROJECT_NAME}" 2>&1 || echo "   Already granted"

echo "🔐 Granting anyuid SCC to rag-workload-sa (for workbench/notebooks)..."
oc adm policy add-scc-to-user anyuid -z rag-workload-sa -n "${PROJECT_NAME}" 2>&1 || echo "   Already granted"

echo "✅ SCC configured"
echo ""

# Step 4: Enable Service Mesh sidecar injection
echo "──────────────────────────────────────────────────────────────────"
echo "Step 4: Enable Service Mesh sidecar injection"
echo "──────────────────────────────────────────────────────────────────"
echo ""

echo "🌐 Enabling Istio sidecar injection for LlamaStack → vLLM connectivity..."
echo "   Note: Required for LlamaStack to connect to Knative-based InferenceServices"
oc label namespace "${PROJECT_NAME}" istio.io/rev=data-science-smcp --overwrite 2>&1 || echo "   Already labeled"

echo "✅ Service Mesh injection enabled"
echo ""

# NEW: Step 4.5: Detect vLLM URLs and Patch ConfigMap
if [ "${VLLM_MISSING}" != "true" ]; then
    echo "══════════════════════════════════════════════════════════════════"
    echo "Step 4.5: Auto-detect vLLM URLs and Patch ConfigMap"
    echo "══════════════════════════════════════════════════════════════════"
    echo ""
    
    echo "🔍 Detecting vLLM InferenceService URLs..."
    
    # Get quantized vLLM URL
    QUANTIZED_URL=$(oc get isvc mistral-24b-quantized -n "${PROJECT_NAME}" -o jsonpath='{.status.url}' 2>/dev/null || echo "")
    if [ -n "$QUANTIZED_URL" ]; then
        echo "   ✅ Quantized vLLM: $QUANTIZED_URL"
    else
        echo "   ⚠️  Could not detect quantized vLLM URL"
        QUANTIZED_URL="https://mistral-24b-quantized-${PROJECT_NAME}.apps.example.com/v1"
    fi
    
    # Get full vLLM URL
    FULL_URL=$(oc get isvc mistral-24b -n "${PROJECT_NAME}" -o jsonpath='{.status.url}' 2>/dev/null || echo "")
    if [ -n "$FULL_URL" ]; then
        echo "   ✅ Full vLLM: $FULL_URL"
    else
        echo "   ⚠️  Could not detect full vLLM URL"
        FULL_URL="https://mistral-24b-${PROJECT_NAME}.apps.example.com/v1"
    fi
    
    echo ""
    echo "📝 Patching LlamaStack ConfigMap with detected URLs..."
    
    # Read current ConfigMap
    CONFIGMAP_FILE="${GITOPS_PATH}/llama-stack/configmap.yaml"
    
    if [ -f "$CONFIGMAP_FILE" ]; then
        # Create a temporary patched version
        TEMP_CONFIGMAP=$(mktemp)
        
        # Replace URLs in ConfigMap using sed
        # This updates the inference provider URLs
        sed -e "s|url: \"https://mistral-24b-quantized-[^\"]*\"|url: \"${QUANTIZED_URL}\"|g" \
            -e "s|url: \"https://mistral-24b-private-ai-demo[^\"]*\"|url: \"${FULL_URL}\"|g" \
            "$CONFIGMAP_FILE" > "$TEMP_CONFIGMAP"
        
        # Show the diff
        echo "   Changes to ConfigMap:"
        diff -u "$CONFIGMAP_FILE" "$TEMP_CONFIGMAP" | grep "^[+-].*url:" || echo "   No URL changes needed"
        
        # Apply the patched ConfigMap
        mv "$TEMP_CONFIGMAP" "$CONFIGMAP_FILE"
        
        echo "   ✅ ConfigMap patched with cluster-specific URLs"
    else
        echo "   ⚠️  ConfigMap file not found: $CONFIGMAP_FILE"
    fi
    
    echo ""
    echo "✅ vLLM URLs configured"
    echo ""
fi

# Step 5: Deploy GitOps resources
echo "──────────────────────────────────────────────────────────────────"
echo "Step 5: Deploy GitOps resources"
echo "──────────────────────────────────────────────────────────────────"
echo ""

echo "📦 Deploying from: $GITOPS_PATH"
oc apply -k "$GITOPS_PATH"

echo ""
echo "✅ Deployment complete!"
echo ""

# Step 6: Compile and Upload KFP Pipeline
echo "──────────────────────────────────────────────────────────────────"
echo "Step 6: Compile and Upload KFP v2 Pipeline"
echo "──────────────────────────────────────────────────────────────────"
echo ""

PIPELINE_SOURCE="${SCRIPT_DIR}/kfp/pipeline.py"
PIPELINE_OUTPUT="${PROJECT_ROOT}/artifacts/docling-rag-pipeline.yaml"
PIPELINE_NAME="docling-rag-pipeline"
VENV_PATH="${PROJECT_ROOT}/.venv-kfp"
KFP_HELPERS="${SCRIPT_DIR}/kfp/kfp-api-helpers.sh"

if [ -f "$PIPELINE_SOURCE" ]; then
    echo "📦 Compiling RAG ingestion pipeline..."
    
    # Create/activate virtual environment
    if [ ! -d "$VENV_PATH" ]; then
        echo "   Creating Python virtual environment..."
        python3 -m venv "$VENV_PATH"
    fi
    
    echo "   Installing KFP SDK..."
    "$VENV_PATH/bin/pip" install -q --upgrade pip
    "$VENV_PATH/bin/pip" install -q kfp
    
    # Create artifacts directory
    mkdir -p "${PROJECT_ROOT}/artifacts"
    
    echo "   Compiling pipeline..."
    "$VENV_PATH/bin/python3" "$PIPELINE_SOURCE"
    
    if [ -f "$PIPELINE_OUTPUT" ]; then
        PIPELINE_SIZE=$(du -h "$PIPELINE_OUTPUT" | cut -f1)
        echo "✅ Pipeline compiled: $PIPELINE_OUTPUT ($PIPELINE_SIZE)"
        
        # Upload pipeline to DSPA (idempotent)
        echo ""
        echo "📤 Uploading pipeline to DSPA..."
        
        # Check if jq is available
        if ! command -v jq &> /dev/null; then
            echo "⚠️  jq not found. Skipping automatic upload."
            echo "   Install jq: https://stedolan.github.io/jq/"
            echo "   Or upload manually via RHOAI Dashboard"
        else
            # Source KFP API helpers
            if [ -f "$KFP_HELPERS" ]; then
                # shellcheck source=/dev/null
                source "$KFP_HELPERS"
                
                # Ensure pipeline is imported
                if ensure_pipeline_imported "$PIPELINE_OUTPUT" "$PIPELINE_NAME"; then
                    echo ""
                    echo "Pipeline is ready in DSPA!"
                    echo "   Pipeline ID: $PIPELINE_ID"
                    echo "   Version ID: $PIPELINE_VERSION_ID"
                else
                    echo "⚠️  Automatic upload failed. You can upload manually via dashboard."
                fi
            else
                echo "⚠️  KFP helpers not found: $KFP_HELPERS"
                echo "   Skipping automatic upload"
            fi
        fi
    else
        echo "⚠️  Pipeline compilation may have failed"
        echo "   Check: $PIPELINE_SOURCE"
    fi
else
    echo "⚠️  Pipeline source not found: $PIPELINE_SOURCE"
    echo "   Skipping pipeline compilation"
fi

echo ""

# Step 7: Verification instructions
echo "══════════════════════════════════════════════════════════════════"
echo "📋 Verification & Next Steps"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "1. Verify Stage 2 components:"
echo "   oc get llamastackdistribution llama-stack -n $PROJECT_NAME"
if [ "${DOCLING_MISSING}" != "true" ]; then
    echo "   oc get doclingserve docling -n $PROJECT_NAME"
else
    echo "   ⚠️  Docling operator not installed - DoclingServe will not deploy"
fi
echo "   oc get deployment milvus-standalone -n $PROJECT_NAME"
echo "   oc get dspa -n $PROJECT_NAME"
echo ""
echo "2. Check LlamaStack has istio sidecar (2/2 containers):"
echo "   oc get pods -l app=llama-stack -n $PROJECT_NAME"
echo "   # Should show: llama-stack-xxx  2/2  Running"
echo "   # (llamastack + istio-proxy containers)"
echo ""
echo "3. Verify LlamaStack can connect to vLLM:"
echo "   oc logs -l app=llama-stack -c llamastack -n $PROJECT_NAME --tail=50"
echo "   # Should show successful vLLM registration, no connection errors"
echo ""
echo "4. Access LlamaStack API:"
echo "   oc get route llamastack -n $PROJECT_NAME"
echo ""

if [ "${DOCLING_MISSING}" != "true" ]; then
    echo "5. Monitor Docling startup (takes ~10 minutes for first start):"
    echo "   oc get pods -l app=docling -n $PROJECT_NAME -w"
    echo ""
fi

echo "6. Pipeline Status:"
if [ -n "${PIPELINE_ID:-}" ]; then
echo "   ✅ Pipeline automatically uploaded to DSPA"
echo "   📖 View in RHOAI Dashboard:"
echo "      https://rhods-dashboard-redhat-ods-applications.apps.$(oc get dns cluster -o jsonpath='{.spec.baseDomain}' 2>/dev/null || echo '<cluster-domain>')"
echo "      → Data Science Projects → $PROJECT_NAME → Pipelines"
else
echo "   ⚠️  Pipeline not uploaded (jq may be missing)"
echo "   📖 Upload manually via RHOAI Dashboard"
fi
echo ""

echo "7. Run RAG ingestion pipelines:"
echo "   cd ${SCRIPT_DIR}"
echo "   ./run-batch-redhat.sh     # Scenario 1"
echo "   ./run-batch-acme.sh        # Scenario 2"
echo "   ./run-batch-euaiact.sh     # Scenario 3"
echo ""

echo "══════════════════════════════════════════════════════════════════"
echo "✅ ENHANCED DEPLOYMENT COMPLETE"
echo "══════════════════════════════════════════════════════════════════"
echo ""

if [ "${VLLM_MISSING}" == "true" ]; then
    echo "⚠️  WARNING: vLLM InferenceServices not found"
    echo "   LlamaStack will not have inference providers until Stage 1 is deployed"
    echo ""
fi

if [ "${DOCLING_MISSING:-false}" == "true" ]; then
    echo "⚠️  WARNING: Docling operator not installed"
    echo "   Please install manually from OperatorHub:"
    echo "   OpenShift Console → Operators → OperatorHub → Search 'Docling'"
    echo ""
fi

echo "Automated Features:"
echo "  ✅ Operator activation (LlamaStack)"
echo "  ✅ Dynamic vLLM URL detection"
echo "  ✅ Cluster-specific configuration"
echo "  ✅ Prerequisites verification"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Step 8: Upload Sample Documents to MinIO
# ──────────────────────────────────────────────────────────────────────────────

echo "══════════════════════════════════════════════════════════════════"
echo "Step 8: Upload Sample Documents to MinIO"
echo "══════════════════════════════════════════════════════════════════"
echo ""

# Check if MinIO has documents already
echo "Checking MinIO for existing documents..."
MINIO_KEY=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d 2>/dev/null || echo "")
MINIO_SECRET=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d 2>/dev/null || echo "")

if [ -z "$MINIO_KEY" ] || [ -z "$MINIO_SECRET" ]; then
    echo "⚠️  WARNING: Could not retrieve MinIO credentials"
    echo "   Skipping document upload. Upload manually later:"
    echo "   ./upload-to-minio.sh <local-file> s3://llama-files/<path>"
    echo ""
else
    # Quick check if llama-files bucket has content
    BUCKET_CHECK=$(oc -n private-ai-demo run mc-quick-check --rm -i --restart=Never \
        --image=quay.io/minio/mc --env=HOME=/tmp \
        --env=AK="$MINIO_KEY" --env=SK="$MINIO_SECRET" \
        --env=ENDPOINT="http://minio.model-storage.svc:9000" \
        -- bash -c '
            mc alias set minio "$ENDPOINT" "$AK" "$SK" --api S3v4 >/dev/null 2>&1
            mc ls minio/llama-files/ 2>/dev/null | wc -l
        ' 2>/dev/null || echo "0")
    
    if [ "$BUCKET_CHECK" -gt 0 ]; then
        echo "✅ MinIO llama-files bucket has content ($BUCKET_CHECK items)"
        echo "   Skipping document upload to avoid duplicates."
        echo ""
        echo "   To re-upload documents, use:"
        echo "   ./upload-to-minio.sh <local-file> s3://llama-files/<scenario>/<filename>"
        echo ""
    else
        echo "ℹ️  MinIO llama-files bucket is empty or doesn't exist"
        echo ""
        echo "Sample Documents Setup:"
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        echo "For RAG ingestion demos, you need to upload PDF documents to MinIO."
        echo ""
        echo "Recommended structure:"
        echo "  • Scenario 1 (Red Hat): s3://llama-files/scenario1-red-hat/*.pdf"
        echo "  • Scenario 2 (ACME):    s3://llama-files/scenario2-acme/*.pdf"
        echo "  • Scenario 3 (EU AI):   s3://llama-files/scenario3-eu-ai/*.pdf"
        echo ""
        echo "To upload documents, use:"
        echo "  ./upload-to-minio.sh <local-pdf> s3://llama-files/<scenario>/<filename>"
        echo ""
        echo "Example:"
        echo "  ./upload-to-minio.sh ~/Documents/sample.pdf s3://llama-files/scenario1-red-hat/sample.pdf"
        echo ""
        echo "After uploading documents, run ingestion pipelines:"
        echo "  ./run-batch-ingestion.sh redhat    # For scenario1-red-hat"
        echo "  ./run-batch-ingestion.sh acme      # For scenario2-acme"
        echo "  ./run-batch-ingestion.sh eu-ai-act # For scenario3-eu-ai-act"
        echo ""
    fi
fi

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "Step 9: Launch RAG Ingestion Pipelines"
echo "══════════════════════════════════════════════════════════════════"
echo ""

# Wait a bit for KFP to be fully ready
echo "⏳ Waiting for KFP Data Science Pipeline to be ready..."
sleep 10

# Check if documents exist in MinIO before running pipelines
if [ "$BUCKET_CHECK" -gt 0 ]; then
    echo "✅ Documents found in MinIO - launching ingestion pipelines..."
    echo ""
    
    # Launch all three scenario pipelines
    for scenario in redhat acme eu-ai-act; do
        echo "────────────────────────────────────────────────────────────────"
        echo "🚀 Launching ingestion for scenario: $scenario"
        echo "────────────────────────────────────────────────────────────────"
        
        # Run ingestion script
        if [ -f "./run-batch-ingestion.sh" ]; then
            ./run-batch-ingestion.sh "$scenario" || echo "⚠️  Pipeline launch failed for $scenario (may need manual retry)"
        else
            echo "⚠️  run-batch-ingestion.sh not found - skipping $scenario"
        fi
        
        echo ""
        sleep 2  # Brief pause between launches
    done
    
    echo "✅ All ingestion pipelines launched!"
    echo ""
    echo "📊 Monitor pipeline progress:"
    echo "   https://ds-pipeline-dspa-${PROJECT_NAME}.apps.$(oc whoami --show-server | cut -d. -f2-)"
    echo ""
else
    echo "ℹ️  No documents in MinIO - skipping automatic ingestion"
    echo ""
    echo "To run ingestion manually after uploading documents:"
    echo "  ./run-batch-ingestion.sh redhat    # For Red Hat docs"
    echo "  ./run-batch-ingestion.sh acme      # For ACME docs"
    echo "  ./run-batch-ingestion.sh eu-ai-act # For EU AI Act docs"
    echo ""
fi

echo "══════════════════════════════════════════════════════════════════"
echo "  🎉 Stage 2 Deployment Complete!"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "📚 Access Points:"
echo "  • LlamaStack Playground: https://llamastack-${PROJECT_NAME}.apps.$(oc whoami --show-server | cut -d. -f2-)"
echo "  • KFP Pipeline UI: https://ds-pipeline-dspa-${PROJECT_NAME}.apps.$(oc whoami --show-server | cut -d. -f2-)"
echo "  • LlamaStack API: http://llama-stack-service.${PROJECT_NAME}.svc:8321"
echo ""
echo "🚀 Stage 2 is ready for RAG operations!"
echo ""

