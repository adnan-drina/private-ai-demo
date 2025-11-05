#!/bin/bash
#
# RAG Pipeline - Upload and Run
# 
# Prerequisites:
# 1. Upload document to MinIO:
#    ./upload-to-minio.sh ~/path/to/document.pdf s3://llama-files/sample/document.pdf
#
# 2. Run pipeline:
#    ./upload-and-run.sh s3://llama-files/sample/document.pdf
#
# This script creates a NEW pipeline version with updated defaults and runs it.
#

set -e

echo "════════════════════════════════════════════════════════════════════════════════"
echo "🚀 UPLOADING & RUNNING RAG PIPELINE (FULLY REPRODUCIBLE)"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Get credentials
NS="private-ai-demo"
HOST=$(oc -n "$NS" get route ds-pipeline-dspa -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)
BASE="https://$HOST/apis"

MINIO_KEY=$(oc get secret dspa-minio-credentials -n "$NS" -o jsonpath='{.data.accesskey}' | base64 -d)
MINIO_SECRET=$(oc get secret dspa-minio-credentials -n "$NS" -o jsonpath='{.data.secretkey}' | base64 -d)

echo "Cluster: $HOST"
echo "MinIO: $MINIO_KEY / ${MINIO_SECRET:0:10}..."
echo ""

# Update the pipeline YAML with correct defaults
PIPELINE_FILE="/Users/adrina/Sandbox/private-ai-demo/artifacts/docling-rag-pipeline-fixed.yaml"

echo "Creating pipeline with updated defaults..."
cat "/Users/adrina/Sandbox/private-ai-demo/artifacts/docling-rag-pipeline-ascii.yaml" | \
  sed "s|s3://llama-files/sample/acme-doc.txt|s3://llama-files/sample/acme-doc.txt|g" | \
  sed "s|minioadmin|$MINIO_SECRET|g" > "$PIPELINE_FILE"

echo "✅ Updated pipeline saved to: $PIPELINE_FILE"
echo ""

# Create new experiment
EXP_NAME="rag-validation-$(date +%Y%m%d)"
echo "Creating experiment: $EXP_NAME..."

EXP_RESPONSE=$(curl -sk -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "$BASE/v1beta1/experiments" \
  --max-time 15 \
  -d "{\"name\":\"$EXP_NAME\",\"description\":\"RAG validation $(date)\"}" 2>/dev/null || echo "{}")

if echo "$EXP_RESPONSE" | grep -q "already exists"; then
  EXP_LIST=$(curl -sk -H "Authorization: Bearer $TOKEN" "$BASE/v1beta1/experiments" --max-time 15 2>/dev/null)
  EXP_ID=$(echo "$EXP_LIST" | jq -r ".experiments[] | select(.name==\"$EXP_NAME\") | .id" 2>/dev/null | head -1)
else
  EXP_ID=$(echo "$EXP_RESPONSE" | jq -r '.id // empty' 2>/dev/null)
fi

echo "  Experiment ID: $EXP_ID"
echo ""

# Upload as new pipeline
PIPELINE_NAME="docling-rag-$(date +%H%M%S)"
echo "Uploading pipeline: $PIPELINE_NAME..."

# Use multipart upload (simpler than versioning)
UPLOAD_RESPONSE=$(curl -sk -H "Authorization: Bearer $TOKEN" \
  -X POST "$BASE/v1beta1/pipelines/upload" \
  --max-time 30 \
  -F "uploadfile=@${PIPELINE_FILE};type=application/x-yaml" \
  -F "name=$PIPELINE_NAME" 2>/dev/null || echo "{}")

PIPELINE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id // empty' 2>/dev/null)

if [ -n "$PIPELINE_ID" ] && [ "$PIPELINE_ID" != "null" ]; then
  echo "  ✅ Pipeline ID: $PIPELINE_ID"
else
  echo "  ❌ Upload failed"
  echo "$UPLOAD_RESPONSE" | jq '.' | head -20
  exit 1
fi

echo ""

# Create run (no parameters needed - defaults are baked in)
RUN_NAME="rag-validation-$(date +%H%M%S)"
echo "Creating run: $RUN_NAME..."

RUN_REQUEST=$(cat <<EOF
{
  "name": "$RUN_NAME",
  "pipeline_spec": {
    "pipeline_id": "$PIPELINE_ID"
  },
  "resource_references": [
    { "key": { "type": "EXPERIMENT", "id": "$EXP_ID" }, "relationship": "OWNER" }
  ]
}
EOF
)

RUN_RESPONSE=$(curl -sk -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "$BASE/v1beta1/runs" \
  --max-time 30 \
  -d "$RUN_REQUEST" 2>/dev/null || echo "{}")

RUN_ID=$(echo "$RUN_RESPONSE" | jq -r '.run.id // empty' 2>/dev/null)

if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ]; then
  echo "  ✅ Run ID: $RUN_ID"
  echo ""
  
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "✅ PIPELINE RUNNING"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo "Run ID: $RUN_ID"
  echo "Dashboard: https://$HOST/#/runs/details/$RUN_ID"
  echo ""
  
  # Save for monitoring
  echo "$RUN_ID" > /tmp/pipeline_run_id.txt
  echo "$(pwd)/upload-and-run.sh" > /tmp/pipeline_script.txt
  
  echo "Run ID saved to /tmp/pipeline_run_id.txt"
  echo ""
  
  # Monitor briefly
  echo "Monitoring (60 seconds)..."
  sleep 60
  
  echo ""
  echo "Status check..."
  STATUS=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    --max-time 10 \
    "$BASE/v1beta1/runs/$RUN_ID" 2>/dev/null | \
    jq -r '.run.status // "unknown"')
  
  echo "  Current status: $STATUS"
  echo ""
  
  if [ "$STATUS" != "Succeeded" ] && [ "$STATUS" != "Failed" ]; then
    echo "Pipeline is running. Monitor with:"
    echo "  oc get pods -n private-ai-demo | grep rag-validation"
  fi
  
else
  echo "  ❌ Run creation failed"
  echo "$RUN_RESPONSE" | jq '.' | head -20
  exit 1
fi

