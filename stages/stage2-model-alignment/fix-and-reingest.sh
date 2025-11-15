#!/bin/bash
# Fix and Re-Ingest RAG Data
# Drops old collection and re-runs pipeline with fixed stored_chunk_id

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "RAG FIX AND RE-INGESTION"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Step 1: Drop old collection
echo "Step 1: Dropping old red_hat_docs collection..."
echo ""
oc exec -it deployment/llama-stack -n private-ai-demo -- sh -c \
  "curl -X DELETE http://localhost:8321/v1/vector-dbs/red_hat_docs" || \
  echo "⚠️  Could not drop collection (may not exist yet)"

echo ""
echo "✅ Collection cleanup complete"
echo ""

# Step 2: Get OAuth token
echo "Step 2: Getting OAuth token..."
TOKEN=$(oc whoami -t)
echo "✅ Token obtained"
echo ""

# Step 3: Launch pipeline
echo "Step 3: Launching pipeline with fixed components..."
echo ""

KFP_HOST="https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com"
PIPELINE_FILE="$SCRIPT_DIR/kfp/batch-docling-rag-pipeline.yaml"

python3 << EOF
import kfp
import os

# Connect to KFP
client = kfp.Client(
    host='$KFP_HOST',
    existing_token='$TOKEN'
)

# Launch pipeline
run = client.create_run_from_pipeline_package(
    pipeline_file='$PIPELINE_FILE',
    arguments={
        's3_prefix': 's3://llama-files/scenario1-red-hat/',
        'vector_db_id': 'red_hat_docs',
        'chunk_size': 512,
        'num_splits': 1,  # Sequential
        'cache_buster': 'fixed-stored-chunk-id-v1',
        's3_secret_mount_path': '/mnt/secrets'
    },
    enable_caching=False  # Force re-execution
)

print(f"✅ Pipeline launched: {run.run_id}")
print(f"")
print(f"Monitor with:")
print(f"  watch -n 10 'oc get workflow -n private-ai-demo | grep {run.run_id[:12]}'")
print(f"")
print(f"Expected duration: 20-80 minutes")
print(f"")
print(f"After completion, test retrieval:")
print(f"  https://llama-stack-playground-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/rag")
EOF

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Re-ingestion started!"
echo "════════════════════════════════════════════════════════════════"

