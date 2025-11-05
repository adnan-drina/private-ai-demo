#!/usr/bin/env python3
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

# Get pipeline ID
pipeline_name = "data-processing-and-insertion"
pipelines = client.list_pipelines(page_size=100).pipelines
pipeline = next((p for p in pipelines if pipeline_name in p.name), None)

if not pipeline:
    print(f"ERROR: Pipeline '{pipeline_name}' not found")
    exit(1)

pipeline_id = pipeline.pipeline_id
print(f"Pipeline ID: {pipeline_id}")

# Get latest pipeline version
response = client.list_pipeline_versions(pipeline_id, page_size=10)
pipeline_versions = response.pipeline_versions if hasattr(response, 'pipeline_versions') else []
if pipeline_versions:
    version_id = pipeline_versions[0].pipeline_version_id
    print(f"Using version: {version_id}")
else:
    version_id = None
    print("No version found - using pipeline directly")

# MinIO credentials (base64 encoded)
minio_creds_b64 = "YWRtaW46T2tnZEhUd0ppamYyb1dvOFF6OUpWMkFXb2JqMXJxVEY="

# ACME documents to process (excluding the one already running)
acme_docs = [
    "ACME_01_ACME_DFO_Calibration_SOP_v1.9_(Tool_L-900_EUV).pdf",
    "ACME_02_PX-7_Lithography_Control_Plan_&_SPC_Limits.pdf",
    "ACME_03_L-900_Tool_Health_&_Predictive_Rules_(FMEA_Extract).pdf",
    "ACME_04_Scanner_&_Metrology_Test_Recipe_Handbook.pdf",
    "ACME_05_Trouble_Response_Playbook_(Tier-1-Tier-2).pdf"
]

print(f"\nCreating {len(acme_docs)} additional runs for ACME documents...")
print("")

for doc in acme_docs:
    run_name = f"acme-{doc.replace('.pdf', '').lower()[:30]}-{datetime.now().strftime('%H%M%S')}"
    
    params = {
        "input_uri": f"s3://llama-files/scenario2-acme/{doc}",
        "docling_url": "http://docling-service.private-ai-demo.svc:5001",
        "llamastack_url": "http://llama-stack-service.private-ai-demo.svc:8321",
        "vector_db_id": "acme_corporate",
        "chunk_size": "512",
        "minio_endpoint": "minio.model-storage.svc:9000",
        "minio_creds_b64": minio_creds_b64,
        "min_chunks": "5"
    }
    
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"Document: {doc}")
    print(f"Run name: {run_name}")
    print(f"Collection: acme_corporate")
    
    try:
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
        
        print(f"✅ Run created: {run.run_id}")
        print(f"URL: {host}/#/runs/details/{run.run_id}")
    except Exception as e:
        print(f"❌ Failed: {e}")
    
    print("")

print("════════════════════════════════════════════════════════════════════════════════")
print("✅ ALL ACME DOCUMENT RUNS CREATED")
print("════════════════════════════════════════════════════════════════════════════════")
print("")
print("All 6 ACME documents will be ingested into the 'acme_corporate' collection.")
print("Each document is processed as a separate pipeline run for better tracking.")
print("")
