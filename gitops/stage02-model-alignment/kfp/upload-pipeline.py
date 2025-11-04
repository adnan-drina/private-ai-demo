#!/usr/bin/env python3
"""
Programmatic KFP Pipeline Upload Script
Fully automated, reproducible pipeline upload to DSPA
"""
import kfp
from kfp import Client
import sys
import os
import urllib3

# Suppress SSL warnings for self-signed certs
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Configuration
PIPELINE_FILE = "artifacts/docling-rag-pipeline.yaml"
PIPELINE_NAME = "docling-rag-ingestion"
PIPELINE_DESCRIPTION = "RAG ingestion: Docling → Embeddings → Milvus"

# DSPA endpoint - use port-forward for authentication bypass
# Run: oc port-forward svc/ds-pipeline-dspa 8888:8443 -n private-ai-demo
DSPA_ENDPOINT = os.getenv("DSPA_ENDPOINT", "https://localhost:8888")

def upload_pipeline():
    """Upload pipeline to DSPA"""
    print("=" * 80)
    print("KFP V2 PIPELINE UPLOAD (PROGRAMMATIC)")
    print("=" * 80)
    print()
    
    if not os.path.exists(PIPELINE_FILE):
        print(f"❌ Pipeline file not found: {PIPELINE_FILE}")
        print("   Run: python3 stages/stage2-model-alignment/kfp/pipeline.py")
        return 1
    
    print(f"Pipeline file: {PIPELINE_FILE}")
    print(f"DSPA endpoint: {DSPA_ENDPOINT}")
    print()
    
    try:
        # Create KFP client (no auth needed via port-forward, disable SSL verification)
        client = Client(host=DSPA_ENDPOINT, verify_ssl=False)
        
        print("✅ Connected to DSPA")
        print()
        
        # Check if pipeline already exists
        existing_pipelines = client.list_pipelines(page_size=100).pipelines or []
        existing = None
        for p in existing_pipelines:
            if p.display_name == PIPELINE_NAME:
                existing = p
                break
        
        if existing:
            print(f"ℹ️  Pipeline '{PIPELINE_NAME}' already exists (ID: {existing.pipeline_id})")
            print("   Uploading new version...")
            
            # Upload new version
            pipeline_version = client.upload_pipeline_version(
                pipeline_package_path=PIPELINE_FILE,
                pipeline_name=PIPELINE_NAME,
                pipeline_version_name=f"v{len(existing.default_version_id or [])+1}"
            )
            print(f"✅ New version uploaded: {pipeline_version.pipeline_version_id}")
        else:
            # Upload new pipeline
            pipeline = client.upload_pipeline(
                pipeline_package_path=PIPELINE_FILE,
                pipeline_name=PIPELINE_NAME,
                description=PIPELINE_DESCRIPTION
            )
            print(f"✅ Pipeline uploaded: {pipeline.pipeline_id}")
        
        print()
        print("Pipeline is now available in DSPA and will persist")
        print("Access via:")
        print("  • RHOAI Dashboard → Pipelines tab")
        print("  • Direct KFP UI")
        print()
        
        return 0
        
    except Exception as e:
        print(f"❌ Error: {e}")
        print()
        print("Troubleshooting:")
        print("  1. Ensure port-forward is running:")
        print("     oc port-forward svc/ds-pipeline-dspa 8888:8443 -n private-ai-demo")
        print("  2. Set DSPA_ENDPOINT if using different port:")
        print("     export DSPA_ENDPOINT=http://localhost:8888")
        print()
        return 1

if __name__ == "__main__":
    sys.exit(upload_pipeline())
