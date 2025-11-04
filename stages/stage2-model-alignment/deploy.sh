#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 2: Model Alignment with RAG + Llama Stack (KFP v2)
#
# Deploys:
#   - Milvus vector database
#   - Llama Stack orchestrator (connects to vLLM + Milvus)
#   - Docling + Granite embedding model
#   - KFP v2 (Data Science Pipelines Application - DSPA)
#   - RAG demonstration notebooks
#
# Prerequisites:
#   - Stage 0 and Stage 1 deployed
#   - MinIO running in model-storage namespace
#   - .env file with MinIO credentials
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GITOPS_PATH="${PROJECT_ROOT}/gitops/stage02-model-alignment"
ENV_FILE="${PROJECT_ROOT}/.env"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2: Model Alignment with RAG + KFP v2"
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
    echo "   oc get secret minio-root-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d"
    echo "   oc get secret minio-root-credentials -n model-storage -o jsonpath='{.data.secretkey}' | base64 -d"
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
    echo "   oc get secret minio-root-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d"
    echo "   oc get secret minio-root-credentials -n model-storage -o jsonpath='{.data.secretkey}' | base64 -d"
    exit 1
fi

echo "✅ Configuration loaded"
echo "   Project: $PROJECT_NAME"
echo "   MinIO: $MINIO_ENDPOINT"
echo "   KFP Bucket: $MINIO_KFP_BUCKET"
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

echo "🔐 Granting anyuid SCC to rag-workload-sa (required by LlamaStack Operator)..."
echo "   Note: LlamaStack Operator sets fsGroup: 0 which requires anyuid SCC"
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
echo "   oc get deployment docling milvus-standalone -n $PROJECT_NAME"
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
echo "5. Monitor Docling startup (takes ~10 minutes for first start):"
echo "   oc get pods -l app=docling -n $PROJECT_NAME -w"
echo ""
echo "6. Pipeline Status:"
if [ -n "${PIPELINE_ID:-}" ]; then
echo "   ✅ Pipeline automatically uploaded to DSPA"
echo "   📖 View in RHOAI Dashboard:"
echo "      https://rhods-dashboard-redhat-ods-applications.apps.$(oc get dns cluster -o jsonpath='{.spec.baseDomain}' 2>/dev/null || echo '<cluster-domain>')"
echo "      → Data Science Projects → $PROJECT_NAME → Pipelines"
else
echo "   ⚠️  Pipeline not uploaded (jq may be missing)"
echo "   📖 Manual upload instructions: ${PROJECT_ROOT}/gitops/stage02-model-alignment/kfp/DEPLOY.md"
fi
echo ""
echo "7. Run RAG ingestion pipeline:"
echo "   ./run-rag-ingestion.sh"
echo "   # Or with custom document:"
echo "   ./run-rag-ingestion.sh s3://llama-files/docs/my-doc.pdf"
echo ""
echo "8. Run validation:"
echo "   ./validate.sh"
echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "📚 Documentation"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "• KFP Pipeline Guide: ${PROJECT_ROOT}/gitops/stage02-model-alignment/kfp/DEPLOY.md"
echo "• LlamaStack Status: ${PROJECT_ROOT}/docs/02-STAGES/STAGE-2-LLAMASTACK-STATUS.md"
echo "• RHOAI 2.25 Docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_llama_stack/index"
echo ""
echo "══════════════════════════════════════════════════════════════════"
