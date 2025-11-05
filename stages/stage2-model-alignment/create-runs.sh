#!/bin/bash
#
# Create three pipeline runs for validation
#

set -e

NS="private-ai-demo"
HOST=$(oc -n "$NS" get route ds-pipeline-dspa -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

# MinIO credentials are now injected from Kubernetes Secret (no parameters needed)
echo "MinIO credentials will be injected from Secret: minio-storage-credentials"
echo ""

# Use the latest pipeline
PIPELINE_ID="ab098c9f-0b3d-4053-9ec4-6dd55594f36f"

# Get pipeline versions
echo "Getting pipeline versions..."
VERSIONS_JSON=$(curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://$HOST/apis/v2beta1/pipelines/$PIPELINE_ID/versions?page_size=5")

PIPELINE_VERSION_ID=$(echo "$VERSIONS_JSON" | jq -r '.pipeline_versions[0].pipeline_version_id')

echo "Pipeline ID: $PIPELINE_ID"
echo "Version ID: $PIPELINE_VERSION_ID"
echo ""

# Create 3 runs
for i in 1 2 3; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Creating Run $i/3"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  RUN_NAME="rag-validation-run$i-$(date +%H%M%S)"
  
  RUN_JSON=$(jq -n \
    --arg name "$RUN_NAME" \
    --arg pid "$PIPELINE_ID" \
    --arg pvid "$PIPELINE_VERSION_ID" \
    --arg input_uri "s3://llama-files/sample/rag-mini.pdf" \
    --arg docling_url "http://docling-service.$NS.svc:5001" \
    --arg embedding_url "http://granite-embedding.private-ai-demo.svc/v1" \
    --arg embedding_model "ibm-granite/granite-embedding-125m-english" \
    --arg llamastack_url "http://llama-stack-service.private-ai-demo.svc:8321" \
    --arg vector_db_id "rag_documents" \
    '{
      name: $name,
      pipeline_spec: {
        pipeline_id: $pid,
        pipeline_version_id: $pvid
      },
      parameters: [
        {"name": "input_uri", "value": $input_uri},
        {"name": "docling_url", "value": $docling_url},
        {"name": "embedding_url", "value": $embedding_url},
        {"name": "embedding_model", "value": $embedding_model},
        {"name": "llamastack_url", "value": $llamastack_url},
        {"name": "vector_db_id", "value": $vector_db_id},
        {"name": "embedding_dimension", "value": "768"},
        {"name": "chunk_size", "value": "512"},
        {"name": "minio_endpoint", "value": "minio.model-storage.svc:9000"},
        {"name": "min_chunks", "value": "10"}
      ]
    }')
  
  RUN_RESPONSE=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -X POST "https://$HOST/apis/v1beta1/runs" \
    -d "$RUN_JSON")
  
  RUN_ID=$(echo "$RUN_RESPONSE" | jq -r '.run.id // .id // empty')
  
  if [ -n "$RUN_ID" ]; then
    echo "  ✅ Run $i created: $RUN_ID"
  else
    ERROR=$(echo "$RUN_RESPONSE" | jq -r '.error_message // .message // "Unknown error"')
    echo "  ❌ Run $i failed: $ERROR"
  fi
  
  echo ""
  sleep 2
done

echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ ALL THREE RUNS SUBMITTED"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Monitor at: https://$HOST"
echo ""
