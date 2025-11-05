#!/bin/bash
#
# Compile Pipeline and Run Three Validation Pipelines
#
# Uses base64-encoded credentials parameter (works within KFP v2 limitations)
#

set -e

echo "════════════════════════════════════════════════════════════════════════════════"
echo "🔧 COMPILING & RUNNING RAG PIPELINES"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "$SCRIPT_DIR"

echo "Step 1: Compile pipeline..."
source venv/bin/activate
python3 kfp/pipeline.py

echo "✅ Pipeline compiled"
echo ""

echo "Step 2: Get MinIO credentials..."
NS="private-ai-demo"

MINIO_KEY=$(oc -n "$NS" get secret dspa-minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d)
MINIO_SECRET=$(oc -n "$NS" get secret dspa-minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d)

# Create base64-encoded credentials in format "access_key:secret_key"
CREDS_B64=$(echo -n "${MINIO_KEY}:${MINIO_SECRET}" | base64)

echo "Credentials: $MINIO_KEY / ${MINIO_SECRET:0:10}..."
echo "Base64 param: ${CREDS_B64:0:20}..."
echo ""

echo "Step 3: Upload pipeline and create 3 runs..."

# Create Python script for upload and run
cat > /tmp/run-pipelines.py <<PYTHON_EOF
#!/usr/bin/env python3
import subprocess
import sys
from datetime import datetime

# Get credentials
def get_oc_output(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return result.stdout.strip()

namespace = "$NS"
host = get_oc_output(["oc", "-n", namespace, "get", "route", "ds-pipeline-dspa", "-o", "jsonpath={.spec.host}"])
token = get_oc_output(["oc", "whoami", "-t"])

print(f"Cluster: {host}")
print("")

# Import KFP
try:
    import kfp
except ImportError:
    print("Installing kfp...")
    subprocess.run([sys.executable, "-m", "pip", "install", "-q", "kfp"], check=True)
    import kfp

# Create client
client = kfp.Client(host=f"https://{host}", existing_token=token)
print("✅ Connected to KFP")
print("")

# Upload pipeline
pipeline_file = "../../artifacts/docling-rag-pipeline.yaml"
timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
pipeline_name = f"docling-rag-b64creds-{timestamp}"

print(f"Uploading pipeline: {pipeline_name}")
try:
    pipeline = client.upload_pipeline(
        pipeline_package_path=pipeline_file,
        pipeline_name=pipeline_name
    )
    print(f"✅ Pipeline uploaded: {pipeline.pipeline_id}")
    print("")
except Exception as e:
    print(f"❌ Upload failed: {e}")
    sys.exit(1)

# Create 3 runs
params = {
    "input_uri": "s3://llama-files/sample/rag-mini.pdf",
    "docling_url": f"http://docling-service.{namespace}.svc:5001",
    "embedding_url": f"http://granite-embedding.{namespace}.svc/v1",
    "embedding_model": "ibm-granite/granite-embedding-125m-english",
    "llamastack_url": f"http://llama-stack-service.{namespace}.svc:8321",
    "vector_db_id": "rag_documents",
    "embedding_dimension": 768,
    "chunk_size": 512,
    "minio_endpoint": "minio.model-storage.svc:9000",
    "minio_creds_b64": "$CREDS_B64",
    "min_chunks": 10
}

experiment_name = f"rag-validation-{datetime.now().strftime('%Y%m%d')}"

print("Creating 3 pipeline runs...")
print("")

run_ids = []
for i in range(1, 4):
    run_name = f"rag-b64creds-run{i}-{datetime.now().strftime('%H%M%S')}"
    
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"Run {i}/3: {run_name}")
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
    try:
        run = client.create_run_from_pipeline_package(
            pipeline_file=pipeline_file,
            arguments=params,
            run_name=run_name,
            experiment_name=experiment_name
        )
        run_ids.append(run.run_id)
        print(f"✅ Run {i} created: {run.run_id}")
        print("")
    except Exception as e:
        print(f"❌ Run {i} failed: {e}")
        print("")

if run_ids:
    print("════════════════════════════════════════════════════════════════════════════════")
    print("✅ ALL RUNS CREATED")
    print("════════════════════════════════════════════════════════════════════════════════")
    print("")
    print(f"Monitor at: https://{host}")
    print("")
    print("Run IDs:")
    for i, run_id in enumerate(run_ids, 1):
        print(f"  {i}. {run_id}")
    print("")
else:
    print("❌ No runs created")
    sys.exit(1)
PYTHON_EOF

python3 /tmp/run-pipelines.py
rm /tmp/run-pipelines.py

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ PIPELINES RUNNING"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

