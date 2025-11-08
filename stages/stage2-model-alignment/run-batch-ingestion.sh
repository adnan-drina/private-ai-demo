#!/bin/bash
# Unified Batch Ingestion Script for All Scenarios
# Usage: ./run-batch-ingestion.sh <scenario>
#   scenario: acme | redhat | eu-ai-act

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCENARIO="${1:-}"

# Scenario configurations
declare -A S3_PREFIXES=(
    ["acme"]="s3://llama-files/scenario2-acme/"
    ["redhat"]="s3://llama-files/scenario1-red-hat/"
    ["eu-ai-act"]="s3://llama-files/scenario3-eu-ai-act/"
)

declare -A VECTOR_DB_IDS=(
    ["acme"]="acme_corporate"
    ["redhat"]="red_hat_docs"
    ["eu-ai-act"]="eu_ai_act"
)

declare -A DESCRIPTIONS=(
    ["acme"]="ACME Corporate Lithography Documentation"
    ["redhat"]="Red Hat OpenShift AI RAG Guide"
    ["eu-ai-act"]="EU AI Act Official Documents"
)

# Validation
if [[ -z "$SCENARIO" ]]; then
    echo -e "${RED}❌ Error: Scenario parameter required${NC}"
    echo ""
    echo "Usage: $0 <scenario>"
    echo ""
    echo "Available scenarios:"
    echo "  acme       - ACME Corporate documents (6 PDFs)"
    echo "  redhat     - Red Hat documentation (1 PDF)"
    echo "  eu-ai-act  - EU AI Act documents (3 PDFs)"
    echo ""
    exit 1
fi

if [[ ! -v S3_PREFIXES[$SCENARIO] ]]; then
    echo -e "${RED}❌ Error: Invalid scenario: $SCENARIO${NC}"
    echo "Valid options: acme, redhat, eu-ai-act"
    exit 1
fi

# Get configuration for this scenario
S3_PREFIX="${S3_PREFIXES[$SCENARIO]}"
VECTOR_DB_ID="${VECTOR_DB_IDS[$SCENARIO]}"
DESCRIPTION="${DESCRIPTIONS[$SCENARIO]}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  RAG Batch Ingestion Pipeline${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}📊 Scenario:${NC} $SCENARIO"
echo -e "${GREEN}📁 S3 Path:${NC} $S3_PREFIX"
echo -e "${GREEN}🗄️  Collection:${NC} $VECTOR_DB_ID"
echo -e "${GREEN}📝 Description:${NC} $DESCRIPTION"
echo ""

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    echo -e "${YELLOW}🐍 Activating Python virtual environment...${NC}"
    source venv/bin/activate
fi

# Compile pipeline
echo -e "${YELLOW}📦 Compiling pipeline...${NC}"
python3 -c "
import os
import sys
import time
from kfp import dsl, compiler, client

# Add project root to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath('$0')), 'kfp'))

# Import pipeline from pipeline.py
from pipeline import batch_docling_rag_pipeline

# Compile
compiler.Compiler().compile(
    pipeline_func=batch_docling_rag_pipeline,
    package_path='kfp/batch-docling-rag-pipeline.yaml'
)
print('✅ Pipeline compiled successfully')
"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Pipeline compilation failed${NC}"
    exit 1
fi

# Run pipeline via KFP client
echo -e "${YELLOW}🚀 Launching pipeline run...${NC}"
python3 << 'PYTHON_SCRIPT'
import os
import sys
import time
from kfp import client
from urllib3.exceptions import MaxRetryError
from kfp_server_api.exceptions import ApiException

# Configuration
DSPA_ROUTE = os.environ.get('DSPA_ROUTE', 'https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com')
NAMESPACE = 'private-ai-demo'
PIPELINE_NAME = "data-processing-and-insertion"
VERSION_DESCRIPTION = "v1.0.2 - Unified ingestion for all scenarios"

# Scenario-specific parameters from environment
S3_PREFIX = os.environ['S3_PREFIX']
VECTOR_DB_ID = os.environ['VECTOR_DB_ID']
SCENARIO = os.environ['SCENARIO']

print(f"📊 Connecting to KFP at: {DSPA_ROUTE}")

# Initialize client (auto-detects RHOAI session cookie or uses local kubeconfig)
try:
    kfp_client = client.Client(host=DSPA_ROUTE, namespace=NAMESPACE)
    print("✅ KFP client initialized")
except Exception as e:
    print(f"❌ Failed to initialize KFP client: {e}")
    sys.exit(1)

# Upload pipeline
print(f"📤 Uploading pipeline: {PIPELINE_NAME}")
try:
    pipeline = kfp_client.upload_pipeline(
        pipeline_package_path='kfp/batch-docling-rag-pipeline.yaml',
        pipeline_name=PIPELINE_NAME,
        description=f"RAG Ingestion Pipeline v1.0.2 - Scenario: {SCENARIO}"
    )
    pipeline_id = pipeline.pipeline_id
    print(f"✅ Pipeline uploaded: {pipeline_id}")

    # Upload a new version
    version_name = f"v{int(time.time())}-{SCENARIO}"
    version = kfp_client.upload_pipeline_version(
        pipeline_package_path='kfp/batch-docling-rag-pipeline.yaml',
        pipeline_version_name=version_name,
        pipeline_name=PIPELINE_NAME,
        description=VERSION_DESCRIPTION
    )
    version_id = version.pipeline_version_id
    print(f"✅ Pipeline version uploaded: {version_id}")

except Exception as e:
    if "already exists" in str(e):
        print("ℹ️  Pipeline already exists, fetching existing pipeline...")
        pipelines = kfp_client.list_pipelines(page_size=100).pipelines
        pipeline = next((p for p in pipelines if p.name == PIPELINE_NAME), None)
        if pipeline:
            pipeline_id = pipeline.pipeline_id
            print(f"✅ Found existing pipeline: {pipeline_id}")

            # Upload new version
            version_name = f"v{int(time.time())}-{SCENARIO}"
            try:
                version = kfp_client.upload_pipeline_version(
                    pipeline_package_path='kfp/batch-docling-rag-pipeline.yaml',
                    pipeline_version_name=version_name,
                    pipeline_name=PIPELINE_NAME,
                    description=VERSION_DESCRIPTION
                )
                version_id = version.pipeline_version_id
                print(f"✅ Pipeline version uploaded: {version_id}")
            except Exception as ve:
                print(f"⚠️  Failed to upload new version: {ve}")
                # Get latest version
                response = kfp_client.list_pipeline_versions(pipeline_id, page_size=10, sort_by="created_at desc")
                versions = response.pipeline_versions if hasattr(response, 'pipeline_versions') else []
                if versions:
                    version_id = versions[0].pipeline_version_id
                    print(f"ℹ️  Using latest version: {version_id}")
                else:
                    version_id = None
        else:
            print(f"❌ Pipeline not found: {PIPELINE_NAME}")
            sys.exit(1)
    else:
        print(f"❌ Pipeline upload failed: {e}")
        sys.exit(1)

# Create run
print(f"🚀 Creating pipeline run for scenario: {SCENARIO}")
run_name = f"{SCENARIO}-batch-ingestion-{int(time.time())}"

params = {
    "s3_prefix": S3_PREFIX,
    "docling_url": "http://docling-service.private-ai-demo.svc:8080",
    "llamastack_url": "http://llama-stack-service.private-ai-demo.svc:8321",
    "vector_db_id": VECTOR_DB_ID,
    "chunk_size": 512,
    "minio_endpoint": "minio.model-storage.svc:9000",
    "minio_creds_b64": "YWRtaW46bWluaW9hZG1pbg==",
    "cache_buster": str(int(time.time()))  # Force fresh run
}

try:
    if version_id:
        run = kfp_client.run_pipeline(
            experiment_name=f"rag-ingestion-{SCENARIO}",
            job_name=run_name,
            pipeline_id=pipeline_id,
            version_id=version_id,
            params=params,
            enable_caching=False  # Force fresh run
        )
    else:
        run = kfp_client.run_pipeline(
            experiment_name=f"rag-ingestion-{SCENARIO}",
            job_name=run_name,
            pipeline_id=pipeline_id,
            params=params,
            enable_caching=False  # Force fresh run
        )

    print(f"✅ Pipeline run created: {run.run_id}")
    print(f"📊 Run name: {run_name}")
    print(f"🔗 View in UI: {DSPA_ROUTE}/#/runs/details/{run.run_id}")

except Exception as e:
    print(f"❌ Failed to create run: {e}")
    sys.exit(1)

PYTHON_SCRIPT

# Export variables for Python script
export S3_PREFIX
export VECTOR_DB_ID
export SCENARIO

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Pipeline launched successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo ""
    echo -e "${RED}❌ Pipeline launch failed${NC}"
    exit 1
fi

