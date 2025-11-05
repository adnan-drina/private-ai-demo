#!/usr/bin/env python3
"""
Upload KFP pipeline using Python SDK
This is more reliable than curl-based uploads
"""

import kfp
import sys
import os
import subprocess

def get_kfp_client():
    """Get KFP client with OAuth token"""
    # Get route host
    result = subprocess.run(
        ["oc", "-n", "private-ai-demo", "get", "route", "ds-pipeline-dspa", 
         "-o", "jsonpath={.spec.host}"],
        capture_output=True,
        text=True
    )
    host = result.stdout.strip()
    
    # Get OAuth token
    result = subprocess.run(
        ["oc", "whoami", "-t"],
        capture_output=True,
        text=True
    )
    token = result.stdout.strip()
    
    # Create client
    client = kfp.Client(
        host=f"https://{host}",
        existing_token=token
    )
    
    return client, host

def upload_pipeline(pipeline_file, pipeline_name):
    """Upload pipeline to KFP"""
    print(f"📤 Uploading pipeline: {pipeline_name}")
    print(f"   File: {pipeline_file}")
    print("")
    
    client, host = get_kfp_client()
    
    print(f"✅ Connected to: {host}")
    print("")
    
    try:
        # Upload pipeline
        pipeline = client.upload_pipeline(
            pipeline_package_path=pipeline_file,
            pipeline_name=pipeline_name,
            description="RAG ingestion pipeline with async Docling API"
        )
        
        print(f"✅ Pipeline uploaded successfully!")
        print(f"   Pipeline ID: {pipeline.id}")
        print(f"   Pipeline Name: {pipeline.name}")
        print("")
        print(f"📊 View in dashboard: https://{host}/#/pipelines/details/{pipeline.id}")
        print("")
        
        return pipeline.id
        
    except Exception as e:
        if "already exists" in str(e).lower():
            print(f"⚠️  Pipeline '{pipeline_name}' already exists")
            print("")
            print(f"Options:")
            print(f"  1. Use a different name")
            print(f"  2. Delete the existing pipeline first")
            print(f"  3. Upload as a new version (requires pipeline ID)")
            print("")
            sys.exit(1)
        else:
            print(f"❌ Upload failed: {e}")
            sys.exit(1)

def create_run(pipeline_id, pipeline_name):
    """Create a pipeline run"""
    client, host = get_kfp_client()
    
    # Get MinIO credentials
    result = subprocess.run(
        ["oc", "-n", "private-ai-demo", "get", "secret", "dspa-minio-credentials",
         "-o", "jsonpath={.data.accesskey}"],
        capture_output=True,
        text=True
    )
    minio_key = subprocess.run(
        ["base64", "-d"],
        input=result.stdout,
        capture_output=True,
        text=True
    ).stdout.strip()
    
    result = subprocess.run(
        ["oc", "-n", "private-ai-demo", "get", "secret", "dspa-minio-credentials",
         "-o", "jsonpath={.data.secretkey}"],
        capture_output=True,
        text=True
    )
    minio_secret = subprocess.run(
        ["base64", "-d"],
        input=result.stdout,
        capture_output=True,
        text=True
    ).stdout.strip()
    
    print(f"🚀 Creating pipeline run...")
    print("")
    
    params = {
        "input_uri": "s3://llama-files/sample/rag-mini.pdf",
        "docling_url": "http://docling-service.private-ai-demo.svc:5001",
        "embedding_url": "http://granite-embedding.private-ai-demo.svc/v1",
        "embedding_model": "ibm-granite/granite-embedding-125m-english",
        "llamastack_url": "http://llama-stack-service.private-ai-demo.svc:8321",
        "vector_db_id": "rag_documents",
        "embedding_dimension": 768,  # int, not string
        "chunk_size": 512,  # int, not string
        "minio_endpoint": "minio.model-storage.svc:9000",
        "aws_access_key_id": minio_key,
        "aws_secret_access_key": minio_secret,
        "min_chunks": 10  # int, not string
    }
    
    from datetime import datetime
    run_name = f"async-docling-test-{datetime.now().strftime('%H%M%S')}"
    
    try:
        run = client.create_run_from_pipeline_package(
            pipeline_file=os.path.join(os.path.dirname(__file__), "../../artifacts/docling-rag-pipeline.yaml"),
            arguments=params,
            run_name=run_name
        )
        
        print(f"✅ Run created successfully!")
        print(f"   Run Name: {run_name}")
        print(f"   Run ID: {run.id if hasattr(run, 'id') else 'N/A'}")
        print("")
        print(f"📊 Monitor: https://{host}/#/runs")
        print("")
        
        return run
        
    except Exception as e:
        print(f"❌ Run creation failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Get pipeline file path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    pipeline_file = os.path.join(script_dir, "../../artifacts/docling-rag-pipeline.yaml")
    
    print("════════════════════════════════════════════════════════════════════════════════")
    print("📤 KFP PIPELINE UPLOAD & RUN (Python SDK)")
    print("════════════════════════════════════════════════════════════════════════════════")
    print("")
    
    # Check if we should skip upload (pipeline already exists)
    if len(sys.argv) > 1 and sys.argv[1] == "--run-only":
        pipeline_id = sys.argv[2] if len(sys.argv) > 2 else "97f77715-7aba-4f5a-b954-e60d5aa65e65"
        pipeline_name = "docling-rag-async"
        print(f"⏩ Skipping upload, using existing pipeline: {pipeline_id}")
        print("")
    else:
        # Use timestamp in name to avoid conflicts
        from datetime import datetime
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        pipeline_name = f"docling-rag-async-{timestamp}"
        
        pipeline_id = upload_pipeline(pipeline_file, pipeline_name)
    
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("")
    
    # Create run
    create_run(pipeline_id, pipeline_name)
    
    print("════════════════════════════════════════════════════════════════════════════════")
    print("✅ PIPELINE RUNNING")
    print("════════════════════════════════════════════════════════════════════════════════")
    print("")
    print("This pipeline uses ASYNC Docling API:")
    print("  - 10-minute timeout")
    print("  - Exponential backoff polling")
    print("  - Handles large PDFs (> 3MB) reliably")
    print("")

