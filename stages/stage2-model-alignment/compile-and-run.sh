#!/bin/bash
#
# Compile Pipeline and Run Three Validation Pipelines
#
# Fixes:
# 1. Creates proper pipeline version (so runs show version in dashboard)
# 2. Uses base64-encoded credentials (works within KFP v2 limitations)
#

set -e

echo "════════════════════════════════════════════════════════════════════════════════"
echo "🔧 COMPILING & RUNNING RAG PIPELINES (WITH PIPELINE VERSION)"
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

echo "Step 3: Upload pipeline with version and create 3 runs..."

# Create Python script for proper version handling
cat > /tmp/run-pipelines-with-version.py <<PYTHON_EOF
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

# Upload pipeline and create version
pipeline_file = "../../artifacts/docling-rag-pipeline.yaml"
timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
pipeline_name = f"data-processing-and-insertion-{timestamp}"

print(f"Uploading pipeline: {pipeline_name}")
try:
    # Upload creates both pipeline and first version
    pipeline = client.upload_pipeline(
        pipeline_package_path=pipeline_file,
        pipeline_name=pipeline_name
    )
    pipeline_id = pipeline.pipeline_id
    print(f"✅ Pipeline uploaded: {pipeline_id}")
    print("")
except Exception as e:
    print(f"❌ Upload failed: {e}")
    sys.exit(1)

# Get the pipeline version that was just created
print("Getting pipeline version...")
try:
    versions = client.list_pipeline_versions(pipeline_id, page_size=1)
    if versions.pipeline_versions:
        version_id = versions.pipeline_versions[0].pipeline_version_id
        version_name = versions.pipeline_versions[0].display_name
        print(f"✅ Pipeline version: {version_name} ({version_id})")
    else:
        print("⚠️  No version found, will create run without version")
        version_id = None
except Exception as e:
    print(f"⚠️  Could not get version: {e}")
    version_id = None

print("")

# Define scenarios with different documents and collections
# All PDFs now uploaded to MinIO with proper organization
scenarios = [
    {
        "name": "red-hat-docs",
        "display": "Red Hat Documentation",
        "input_uri": "s3://llama-files/scenario1-red-hat/rhoai-rag-guide.pdf",
        "vector_db_id": "red_hat_docs",
        "min_chunks": 10
    },
    {
        "name": "acme-corporate",
        "display": "ACME Corporate Policy",
        "input_uri": "s3://llama-files/scenario2-acme/ACME_06_Reliability_Summary_Q3_FY25.pdf",
        "vector_db_id": "acme_corporate",
        "min_chunks": 5  # Smaller file
    },
    {
        "name": "eu-ai-act",
        "display": "EU AI Act Regulation",
        "input_uri": "s3://llama-files/scenario3-eu-ai-act/eu-ai-act-official-journal.pdf",
        "vector_db_id": "eu_ai_act",
        "min_chunks": 50  # Large official document
    }
]

experiment_name = f"rag-validation-{datetime.now().strftime('%Y%m%d')}"

print("Creating 3 scenario-based pipeline runs...")
print("")

run_ids = []
for idx, scenario in enumerate(scenarios, 1):
    run_name = f"{scenario['name']}-{datetime.now().strftime('%H%M%S')}"
    
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"Scenario {idx}/3: {scenario['display']}")
    print(f"Run name: {run_name}")
    print(f"Collection: {scenario['vector_db_id']}")
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
    # Build parameters for this scenario
    params = {
        "input_uri": scenario["input_uri"],
        "docling_url": f"http://docling-service.{namespace}.svc:5001",
        "llamastack_url": f"http://llama-stack-service.{namespace}.svc:8321",
        "vector_db_id": scenario["vector_db_id"],
        "chunk_size": 512,
        "minio_endpoint": "minio.model-storage.svc:9000",
        "minio_creds_b64": "$CREDS_B64",
        "min_chunks": scenario["min_chunks"]
    }
    
    try:
        if version_id:
            # Create run with version reference (proper way)
            run = client.run_pipeline(
                experiment_id=None,
                job_name=run_name,
                pipeline_id=pipeline_id,
                version_id=version_id,
                params=params
            )
            run_id = run.id if hasattr(run, 'id') else run.run_id
        else:
            # Fallback: create from package
            run = client.create_run_from_pipeline_package(
                pipeline_file=pipeline_file,
                arguments=params,
                run_name=run_name,
                experiment_name=experiment_name
            )
            run_id = run.run_id
        
        run_ids.append(run_id)
        print(f"✅ Run {idx} created: {run_id}")
        print("")
    except Exception as e:
        print(f"❌ Run {idx} failed: {e}")
        print("")

if run_ids:
    print("════════════════════════════════════════════════════════════════════════════════")
    print("✅ ALL SCENARIO RUNS CREATED WITH PIPELINE VERSION")
    print("════════════════════════════════════════════════════════════════════════════════")
    print("")
    print(f"Monitor at: https://{host}")
    print("")
    print("Scenario Runs:")
    for idx, (scenario, run_id) in enumerate(zip(scenarios, run_ids), 1):
        print(f"  {idx}. {scenario['display']}: {run_id}")
        print(f"     Collection: {scenario['vector_db_id']}")
    print("")
    print("Pipeline Version: {}")
    print("")
else:
    print("❌ No runs created")
    sys.exit(1)
PYTHON_EOF

python3 /tmp/run-pipelines-with-version.py
rm /tmp/run-pipelines-with-version.py

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ PIPELINES RUNNING (WITH VERSION TRACKING)"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

