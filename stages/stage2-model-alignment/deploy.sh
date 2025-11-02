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
GITOPS_PATH="${SCRIPT_DIR}/../../gitops/stage02-model-alignment"
ENV_FILE="${SCRIPT_DIR}/.env"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2: Model Alignment with RAG + KFP v2"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Load environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ ERROR: .env file not found at $ENV_FILE"
    echo "   Create it from env.template:"
    echo "   cp env.template .env"
    echo "   Then edit .env with your MinIO credentials"
    exit 1
fi

echo "📄 Loading configuration from .env..."
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

# Step 2: Create DSPA MinIO credentials secret
echo "──────────────────────────────────────────────────────────────────"
echo "Step 2: Create DSPA MinIO credentials secret"
echo "──────────────────────────────────────────────────────────────────"
echo ""

echo "🔐 Creating secret: dspa-minio-credentials in namespace $PROJECT_NAME"
oc create secret generic dspa-minio-credentials \
    -n "${PROJECT_NAME}" \
    --from-literal=accesskey="${MINIO_ACCESS_KEY}" \
    --from-literal=secretkey="${MINIO_SECRET_KEY}" \
    --dry-run=client -o yaml | oc apply -f -

echo "✅ Secret created"
echo ""

# Step 3: Deploy GitOps resources
echo "──────────────────────────────────────────────────────────────────"
echo "Step 3: Deploy GitOps resources"
echo "──────────────────────────────────────────────────────────────────"
echo ""

echo "📦 Deploying from: $GITOPS_PATH"
oc apply -k "$GITOPS_PATH"

echo ""
echo "✅ Deployment complete!"
echo ""

# Step 4: Verification instructions
echo "══════════════════════════════════════════════════════════════════"
echo "📋 Next Steps"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "1. Verify DSPA is running:"
echo "   oc get dspa -n $PROJECT_NAME"
echo "   oc get pods -n $PROJECT_NAME -l app=ds-pipeline-dspa"
echo ""
echo "2. Check Data Science Pipelines API:"
echo "   oc get route ds-pipeline-dspa -n $PROJECT_NAME"
echo ""
echo "3. Compile the KFP pipeline:"
echo "   cd ${SCRIPT_DIR}/kfp"
echo "   ./compile.sh"
echo ""
echo "4. Access RHOAI Dashboard to register and run pipeline:"
echo "   - Navigate to Data Science Pipelines"
echo "   - Import: kfp/artifacts/docling-rag-pipeline.yaml"
echo "   - Create experiment and run"
echo ""
echo "5. Monitor deployment:"
echo "   ./validate.sh"
echo ""
echo "══════════════════════════════════════════════════════════════════"
