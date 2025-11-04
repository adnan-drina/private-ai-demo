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
echo -e "${YELLOW}⏳ Checking if pipeline is uploaded...${NC}"
echo ""

# Get DSPA route and check for pipeline
DSPA_ROUTE=$(oc get route ds-pipeline-dspa -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -z "$DSPA_ROUTE" ]; then
  echo -e "${RED}❌ ERROR: DSPA route not found${NC}"
  exit 1
fi

# Use programmatic access to check for pipeline
HOST="https://$DSPA_ROUTE"
TOKEN=$(oc whoami -t)

PIPELINES=$(curl -sk -H "Authorization: Bearer $TOKEN" "$HOST/apis/v2beta1/pipelines?page_size=100" 2>/dev/null || echo "{}")
PIPELINE_ID=$(echo "$PIPELINES" | jq -r '.pipelines[]? | select(.display_name=="docling-rag-ingestion") | .pipeline_id' 2>/dev/null || echo "")

if [ -z "$PIPELINE_ID" ]; then
  echo -e "${RED}❌ ERROR: Pipeline 'docling-rag-ingestion' not found in DSPA${NC}"
  echo ""
  echo "You need to upload the pipeline first:"
  echo ""
  echo "  1. Open RHOAI Dashboard:"
  echo "     https://rhods-dashboard-redhat-ods-applications.apps.$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')"
  echo ""
  echo "  2. Navigate: Data Science Projects → $NAMESPACE → Pipelines"
  echo ""
  echo "  3. Upload pipeline:"
  echo "     File: $PROJECT_ROOT/artifacts/docling-rag-pipeline.yaml"
  echo "     Name: docling-rag-ingestion"
  echo ""
  echo "See detailed instructions:"
  echo "  $PROJECT_ROOT/gitops/stage02-model-alignment/kfp/DEPLOY.md"
  echo ""
  exit 1
fi

echo -e "${GREEN}✅ Pipeline found (ID: $PIPELINE_ID)${NC}"
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

# Create run request
RUN_NAME="rag-ingestion-$(date +%s)"
RUN_REQUEST=$(cat <<EOF
{
  "display_name": "$RUN_NAME",
  "description": "RAG ingestion for $DOCUMENT_URI",
  "pipeline_id": "$PIPELINE_ID",
  "runtime_config": {
    "parameters": {
      "input_uri": {"string_value": "$DOCUMENT_URI"},
      "docling_url": {"string_value": "http://docling.$NAMESPACE.svc:8080"},
      "embedding_url": {"string_value": "http://llamastack.$NAMESPACE.svc:8321/v1"},
      "embedding_model": {"string_value": "ibm-granite/granite-embedding-125m-english"},
      "milvus_uri": {"string_value": "tcp://milvus-standalone.$NAMESPACE.svc.cluster.local:19530"},
      "milvus_collection": {"string_value": "rag_documents"},
      "embedding_dimension": {"int_value": 768},
      "chunk_size": {"int_value": 512},
      "minio_endpoint": {"string_value": "minio.model-storage.svc:9000"},
      "aws_access_key_id": {"string_value": "$MINIO_KEY"},
      "aws_secret_access_key": {"string_value": "$MINIO_SECRET"},
      "min_entities": {"int_value": 10}
    }
  }
}
EOF
)

# Submit the run
RESPONSE=$(curl -sk -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$RUN_REQUEST" \
  "$HOST/apis/v2beta1/runs" 2>/dev/null)

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
echo "    \"$HOST/apis/v2beta1/runs/$RUN_ID\""
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
