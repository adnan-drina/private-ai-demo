#!/bin/bash
set -euo pipefail

##############################################################################
# Run RAG Ingestion Pipeline (KFP v2)
# 
# Runs the Kubeflow Pipeline to:
#   1. Download document from MinIO
#   2. Process with Docling
#   3. Generate embeddings with LlamaStack/Granite
#   4. Store in Milvus vector database
#   5. Verify ingestion (≥10 entities)
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai-demo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
  cat << EOF
Usage: $0 [DOCUMENT_URI]

Runs the RAG ingestion pipeline for document processing.

Arguments:
  DOCUMENT_URI - S3 URI of document to process (optional)
                 Default: s3://llama-files/sample/rag-mini.pdf

Examples:
  $0                                           # Use default sample document
  $0 s3://llama-files/docs/my-document.pdf    # Process specific document

The pipeline will:
  1. Download document from MinIO S3 storage
  2. Process document with Docling (extract text, structure)
  3. Generate embeddings using LlamaStack/Granite model
  4. Store embeddings in Milvus vector database
  5. Verify at least 10 entities were ingested

Prerequisites:
  - Stage 2 deployed (DSPA, Milvus, LlamaStack, Docling)
  - Pipeline uploaded to DSPA (see: gitops/stage02-model-alignment/kfp/DEPLOY.md)
  - Document available in MinIO llama-files bucket

EOF
  exit 1
}

# Parse arguments
DOCUMENT_URI="${1:-s3://llama-files/sample/rag-mini.pdf}"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  RAG Ingestion Pipeline Runner${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}⏳ Checking prerequisites...${NC}"
echo ""

# 1. Check if DSPA is ready
if ! oc get dspa dspa -n "$NAMESPACE" &>/dev/null; then
  echo -e "${RED}❌ ERROR: DSPA not found in namespace $NAMESPACE${NC}"
  echo "   Run Stage 2 deployment first: ./deploy.sh"
  exit 1
fi

DSPA_READY=$(oc get dspa dspa -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$DSPA_READY" != "True" ]; then
  echo -e "${RED}❌ ERROR: DSPA is not ready${NC}"
  echo "   Check DSPA status: oc get dspa dspa -n $NAMESPACE -o yaml"
  exit 1
fi

echo -e "${GREEN}✅ DSPA ready${NC}"

# 2. Check if required services are running
echo ""
echo -e "${YELLOW}⏳ Verifying Stage 2 services...${NC}"

SERVICES=("docling" "milvus-standalone")
for service in "${SERVICES[@]}"; do
  if oc get deployment "$service" -n "$NAMESPACE" &>/dev/null; then
    REPLICAS=$(oc get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" -gt 0 ]; then
      echo -e "${GREEN}✅ $service running${NC}"
    else
      echo -e "${RED}❌ $service not ready (0 replicas)${NC}"
      exit 1
    fi
  else
    echo -e "${RED}❌ $service deployment not found${NC}"
    exit 1
  fi
done

# 3. Check if LlamaStack is running
if oc get llamastackdistribution llama-stack -n "$NAMESPACE" &>/dev/null; then
  echo -e "${GREEN}✅ LlamaStack deployed${NC}"
else
  echo -e "${RED}❌ LlamaStack not found${NC}"
  exit 1
fi

echo ""
echo -e "${YELLOW}⏳ Ensuring pipeline is uploaded...${NC}"
echo ""

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo -e "${RED}❌ ERROR: jq is required for pipeline management${NC}"
  echo "   Install jq: https://stedolan.github.io/jq/"
  exit 1
fi

# Source KFP API helpers
KFP_HELPERS="${SCRIPT_DIR}/kfp/kfp-api-helpers.sh"
if [ ! -f "$KFP_HELPERS" ]; then
  echo -e "${RED}❌ ERROR: KFP helpers not found: $KFP_HELPERS${NC}"
  exit 1
fi

# shellcheck source=/dev/null
source "$KFP_HELPERS"

# Ensure pipeline is imported (idempotent)
PIPELINE_FILE="$PROJECT_ROOT/artifacts/docling-rag-pipeline.yaml"
PIPELINE_NAME="docling-rag-pipeline"

if [ ! -f "$PIPELINE_FILE" ]; then
  echo -e "${RED}❌ ERROR: Pipeline file not found: $PIPELINE_FILE${NC}"
  echo "   Run deployment first: cd stages/stage2-model-alignment && ./deploy.sh"
  exit 1
fi

if ! ensure_pipeline_imported "$PIPELINE_FILE" "$PIPELINE_NAME"; then
  echo -e "${RED}❌ ERROR: Failed to ensure pipeline is uploaded${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Pipeline ready (ID: $PIPELINE_ID, Version: $PIPELINE_VERSION_ID)${NC}"
echo ""

# Create the run
echo -e "${YELLOW}⏳ Creating pipeline run...${NC}"
echo ""
echo "Parameters:"
echo "  • Document: $DOCUMENT_URI"
echo "  • Docling URL: http://docling.$NAMESPACE.svc:8080"
echo "  • Embedding URL: http://llamastack.$NAMESPACE.svc:8321/v1"
echo "  • Milvus URI: tcp://milvus-standalone.$NAMESPACE.svc.cluster.local:19530"
echo "  • Collection: rag_documents"
echo ""

# Get MinIO credentials for the run
MINIO_KEY=$(oc get secret dspa-minio-credentials -n "$NAMESPACE" -o jsonpath='{.data.accesskey}' 2>/dev/null | base64 -d || echo "admin")
MINIO_SECRET=$(oc get secret dspa-minio-credentials -n "$NAMESPACE" -o jsonpath='{.data.secretkey}' 2>/dev/null | base64 -d || echo "")

if [ -z "$MINIO_SECRET" ]; then
  echo -e "${RED}❌ ERROR: Could not retrieve MinIO credentials${NC}"
  exit 1
fi

# Create run name
RUN_NAME="rag-ingestion-$(date +%s)"

# Build parameters JSON
PARAMS_JSON=$(jq -n \
  --arg input_uri "$DOCUMENT_URI" \
  --arg docling_url "http://docling.$NAMESPACE.svc:8080" \
  --arg embedding_url "http://llamastack.$NAMESPACE.svc:8321/v1" \
  --arg embedding_model "ibm-granite/granite-embedding-125m-english" \
  --arg milvus_uri "tcp://milvus-standalone.$NAMESPACE.svc.cluster.local:19530" \
  --arg milvus_collection "rag_documents" \
  --argjson embedding_dimension 768 \
  --argjson chunk_size 512 \
  --arg minio_endpoint "minio.model-storage.svc:9000" \
  --arg minio_key "$MINIO_KEY" \
  --arg minio_secret "$MINIO_SECRET" \
  --argjson min_entities 10 \
  '{
    input_uri: {string_value: $input_uri},
    docling_url: {string_value: $docling_url},
    embedding_url: {string_value: $embedding_url},
    embedding_model: {string_value: $embedding_model},
    milvus_uri: {string_value: $milvus_uri},
    milvus_collection: {string_value: $milvus_collection},
    embedding_dimension: {int_value: $embedding_dimension},
    chunk_size: {int_value: $chunk_size},
    minio_endpoint: {string_value: $minio_endpoint},
    aws_access_key_id: {string_value: $minio_key},
    aws_secret_access_key: {string_value: $minio_secret},
    min_entities: {int_value: $min_entities}
  }')

# Create the run using helper function
RESPONSE=$(kfp_create_run "$RUN_NAME" "$PIPELINE_VERSION_ID" "$PARAMS_JSON")

RUN_ID=$(echo "$RESPONSE" | jq -r '.run_id // empty' 2>/dev/null)

if [ -z "$RUN_ID" ]; then
  echo -e "${RED}❌ ERROR: Failed to create pipeline run${NC}"
  echo ""
  echo "Response:"
  echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
  exit 1
fi

echo -e "${GREEN}✅ Pipeline run created!${NC}"
echo ""
echo "Run ID: $RUN_ID"
echo "Run Name: $RUN_NAME"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Monitoring Pipeline${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

echo "View run in RHOAI Dashboard:"
echo "  https://rhods-dashboard-redhat-ods-applications.apps.$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')"
echo "  → Data Science Projects → $NAMESPACE → Pipelines → Runs"
echo ""

echo "Monitor via CLI:"
echo "  # Get run status"
echo "  curl -sk -H \"Authorization: Bearer \$(oc whoami -t)\" \\"
echo "    \"$KFP_HOST/apis/v2beta1/runs/$RUN_ID\""
echo ""
echo "  # Watch pods"
echo "  oc get pods -n $NAMESPACE -w | grep -E 'docling|rag'"
echo ""
echo "  # View logs (once pods start)"
echo "  oc logs -n $NAMESPACE -l pipeline/runid=$RUN_ID -f"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ Pipeline run submitted successfully!${NC}"
echo ""
