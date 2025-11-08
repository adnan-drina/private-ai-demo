#!/bin/bash
#
# Run batch pipeline for Red Hat documentation
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "════════════════════════════════════════════════════════════════════════════════"
echo "🚀 BATCH PROCESSING: RED HAT DOCUMENTATION"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Activate venv
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install -q kfp

echo "Step 1: Get MinIO credentials..."
echo ""

NS="private-ai-demo"
MINIO_KEY=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d)
MINIO_SECRET=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d)
MINIO_CREDS_B64=$(echo -n "$MINIO_KEY:$MINIO_SECRET" | base64)

echo "✅ Credentials retrieved"
echo ""

# S3 prefix for Red Hat documents
S3_PREFIX="s3://llama-files/scenario1-red-hat/"
VECTOR_DB_ID="red_hat_docs"

echo "Step 2: Create pipeline run..."
echo ""

python3 << PYEOF
import kfp
import urllib3
import os
from datetime import datetime

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# KFP connection
host = "https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com"
token = os.popen("oc whoami -t").read().strip()
client = kfp.Client(host=host, existing_token=token, verify_ssl=False)

print(f"Connected to: {host}")
print("")

# Get pipeline
pipeline_name = "data-processing-and-insertion"
pipelines = client.list_pipelines(page_size=100).pipelines
pipeline = next((p for p in pipelines if pipeline_name in (p.name if hasattr(p, 'name') else p.display_name)), None)

if not pipeline:
    print(f"❌ Pipeline '{pipeline_name}' not found. Run run-batch-acme.sh first to upload pipeline.")
    exit(1)

pipeline_id = pipeline.pipeline_id if hasattr(pipeline, 'pipeline_id') else pipeline.id
print(f"✅ Found pipeline: {pipeline_id}")

# Get LATEST version (sorted by creation time descending)
response = client.list_pipeline_versions(pipeline_id, page_size=10, sort_by="created_at desc")
pipeline_versions = response.pipeline_versions if hasattr(response, 'pipeline_versions') else []
version_id = pipeline_versions[0].pipeline_version_id if pipeline_versions else None

if version_id:
    print(f"✅ Using LATEST version: {version_id}")
else:
    print("⚠️  No version found, using pipeline directly")

print("")

# Create run
run_name = f"batch-red-hat-docs-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

import time

params = {
    "s3_prefix": "$S3_PREFIX",
    "docling_url": "http://docling-service.private-ai-demo.svc:5001",
    "llamastack_url": "http://llama-stack-service.private-ai-demo.svc:8321",
    "vector_db_id": "$VECTOR_DB_ID",
    "chunk_size": 512,
    "num_splits": 2,
    "s3_secret_mount_path": "/mnt/secrets",
    "minio_endpoint": "minio.model-storage.svc:9000",
    "minio_creds_b64": "$MINIO_CREDS_B64",
    "cache_buster": str(int(time.time()))  # Force fresh run - no cache
}

print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"Creating run: {run_name}")
print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  S3 Prefix: $S3_PREFIX")
print(f"  Collection: $VECTOR_DB_ID")
print(f"  Parallelism: {params['num_splits']} balanced groups")
print("")

try:
    if version_id:
        run = client.run_pipeline(
            experiment_id=None,
            job_name=run_name,
            pipeline_id=pipeline_id,
            version_id=version_id,
            params=params,
            enable_caching=False  # Force fresh run - no caching
        )
    else:
        run = client.run_pipeline(
            experiment_id=None,
            job_name=run_name,
            pipeline_id=pipeline_id,
            params=params,
            enable_caching=False  # Force fresh run - no caching
        )
    
    run_id = run.run_id if hasattr(run, 'run_id') else run.id
    print(f"✅ Run created: {run_id}")
    print(f"   URL: {host}/#/runs/details/{run_id}")
    
except Exception as e:
    print(f"❌ Failed to create run: {e}")
    exit(1)

print("")
print("════════════════════════════════════════════════════════════════════════════════")
print("Monitor progress:")
print(f"  Dashboard: {host}/#/runs")
print("════════════════════════════════════════════════════════════════════════════════")
PYEOF

echo ""
deactivate

