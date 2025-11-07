#!/bin/bash
#
# Compile and run batch pipeline for all ACME documents
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "════════════════════════════════════════════════════════════════════════════════"
echo "🚀 BATCH PROCESSING: ALL ACME DOCUMENTS"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Activate venv
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install -q kfp

# Compile batch pipeline
echo "Step 1: Compiling batch pipeline..."
echo ""

cd kfp

python3 << 'PYEOF'
from kfp import compiler
from pathlib import Path
from pipeline import batch_docling_rag_pipeline

# Calculate paths
script_dir = Path.cwd()
stage_dir = script_dir.parent
stages_dir = stage_dir.parent
project_root = stages_dir.parent
artifacts_dir = project_root / "artifacts"
artifacts_dir.mkdir(exist_ok=True)

output_path = artifacts_dir / "batch-docling-rag-pipeline.yaml"

compiler.Compiler().compile(
    pipeline_func=batch_docling_rag_pipeline,
    package_path=str(output_path)
)
print(f"✅ Batch pipeline compiled: {output_path}")
PYEOF

cd ..

echo ""
echo "Step 2: Get MinIO credentials..."
echo ""

NS="private-ai-demo"
MINIO_KEY=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d)
MINIO_SECRET=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d)
MINIO_CREDS_B64=$(echo -n "$MINIO_KEY:$MINIO_SECRET" | base64)

echo "Credentials encoded: ${MINIO_CREDS_B64:0:20}..."
echo ""

# S3 prefix for ACME documents
S3_PREFIX="s3://llama-files/scenario2-acme/"

echo "Step 3: Upload and run smart batch pipeline..."
echo ""

python3 << PYEOF
import kfp
from kfp import client as kfp_client
import urllib3
import os

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# KFP connection
host = "https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com"
token = os.popen("oc whoami -t").read().strip()
client = kfp_client.Client(host=host, existing_token=token, verify_ssl=False)

print(f"Connected to: {host}")
print("")

# Upload batch pipeline
pipeline_file = "../../artifacts/batch-docling-rag-pipeline.yaml"
pipeline_name = "batch-data-processing-acme"

print(f"Uploading smart batch pipeline: {pipeline_name}")

try:
    pipeline = client.upload_pipeline(
        pipeline_package_path=pipeline_file,
        pipeline_name=pipeline_name
    )
    pipeline_id = pipeline.id if hasattr(pipeline, 'id') else pipeline.pipeline_id
    print(f"✅ Pipeline uploaded: {pipeline_id}")
except Exception as e:
    # Pipeline might already exist, get it
    pipelines = client.list_pipelines(page_size=100).pipelines
    pipeline = next((p for p in pipelines if pipeline_name in (p.name if hasattr(p, 'name') else p.display_name)), None)
    if pipeline:
        pipeline_id = pipeline.id if hasattr(pipeline, 'id') else pipeline.pipeline_id
        print(f"✅ Using existing pipeline: {pipeline_id}")
    else:
        raise e

print("")

# Get pipeline version
response = client.list_pipeline_versions(pipeline_id, page_size=10)
pipeline_versions = response.pipeline_versions if hasattr(response, 'pipeline_versions') else []
if pipeline_versions:
    version_id = pipeline_versions[0].pipeline_version_id
    print(f"Using version: {version_id}")
else:
    version_id = None
    print("No version found - will create default version")

print("")

# Create run - pipeline will auto-discover all PDFs in the folder
run_name = f"batch-acme-auto-discover-{os.popen('date +%Y%m%d-%H%M%S').read().strip()}"

params = {
    "s3_prefix": "$S3_PREFIX",
    "docling_url": "http://docling-service.private-ai-demo.svc:5001",
    "llamastack_url": "http://llama-stack-service.private-ai-demo.svc:8321",
    "vector_db_id": "acme_corporate",
    "chunk_size": 512,  # Integer, not string
    "minio_endpoint": "minio.model-storage.svc:9000",
    "minio_creds_b64": "$MINIO_CREDS_B64"
}

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"Run: {run_name}")
print(f"Pipeline: {pipeline_name} (Smart Auto-Discovery)")
print(f"S3 Prefix: $S3_PREFIX")
print(f"Collection: acme_corporate")
print(f"Parallelism: 2 PDFs at a time")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("")
print("Pipeline will:")
print("  1. Automatically discover all PDFs in $S3_PREFIX")
print("  2. Process 2 PDFs in parallel at a time")
print("  3. Insert all chunks into 'acme_corporate' collection")
print("")

if version_id:
    run = client.run_pipeline(
        experiment_id=None,
        job_name=run_name,
        pipeline_id=pipeline_id,
        version_id=version_id,
        params=params
    )
else:
    run = client.run_pipeline(
        experiment_id=None,
        job_name=run_name,
        pipeline_id=pipeline_id,
        params=params
    )

run_id = run.id if hasattr(run, 'id') else run.run_id
print(f"✅ Batch run created: {run_id}")
print(f"URL: {host}/#/runs/details/{run_id}")
print("")

PYEOF

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ BATCH PIPELINE RUNNING${NC}"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Monitor at: https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com"
echo ""

