#!/usr/bin/env python3
"""
Run Three Validation Pipelines

Uploads the pipeline with secret injection and creates three runs.
Uses KFP SDK to avoid API upload issues.
"""

import subprocess
import sys
from datetime import datetime
from pathlib import Path

# Suppress warnings
import warnings
warnings.filterwarnings("ignore")

def get_oc_output(cmd):
    """Run oc command and return output"""
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return result.stdout.strip()

def main():
    print("════════════════════════════════════════════════════════════════════════════════")
    print("🚀 RUNNING THREE VALIDATION PIPELINES (KFP SDK)")
    print("════════════════════════════════════════════════════════════════════════════════")
    print("")
    
    # Get credentials
    namespace = "private-ai-demo"
    host = get_oc_output(["oc", "-n", namespace, "get", "route", "ds-pipeline-dspa", "-o", "jsonpath={.spec.host}"])
    token = get_oc_output(["oc", "whoami", "-t"])
    
    print(f"Cluster: {host}")
    print("")
    
    # Import KFP
    try:
        import kfp
    except ImportError:
        print("❌ kfp not installed. Installing...")
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "kfp"], check=True)
        import kfp
    
    # Create client
    print("Connecting to KFP...")
    client = kfp.Client(
        host=f"https://{host}",
        existing_token=token
    )
    print("✅ Connected")
    print("")
    
    # Upload pipeline
    pipeline_file = Path(__file__).parent.parent.parent / "artifacts" / "docling-rag-pipeline.yaml"
    
    if not pipeline_file.exists():
        print(f"❌ Pipeline file not found: {pipeline_file}")
        sys.exit(1)
    
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    pipeline_name = f"docling-rag-secrets-{timestamp}"
    
    print(f"Uploading pipeline: {pipeline_name}")
    print(f"File: {pipeline_file}")
    
    try:
        pipeline = client.upload_pipeline(
            pipeline_package_path=str(pipeline_file),
            pipeline_name=pipeline_name
        )
        pipeline_id = pipeline.pipeline_id
        print(f"✅ Pipeline uploaded: {pipeline_id}")
        print("")
    except Exception as e:
        print(f"❌ Upload failed: {e}")
        sys.exit(1)
    
    # Create 3 runs
    print("Creating 3 pipeline runs...")
    print("")
    
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
        "min_chunks": 10
    }
    
    experiment_name = f"rag-validation-{datetime.now().strftime('%Y%m%d')}"
    
    run_ids = []
    for i in range(1, 4):
        run_name = f"rag-validation-run{i}-{datetime.now().strftime('%H%M%S')}"
        
        print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print(f"Creating Run {i}/3: {run_name}")
        print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        try:
            run = client.create_run_from_pipeline_package(
                pipeline_file=str(pipeline_file),
                arguments=params,
                run_name=run_name,
                experiment_name=experiment_name
            )
            run_id = run.run_id
            run_ids.append(run_id)
            print(f"✅ Run {i} created: {run_id}")
            print("")
        except Exception as e:
            print(f"❌ Run {i} failed: {e}")
            print("")
    
    if not run_ids:
        print("❌ No runs created successfully")
        sys.exit(1)
    
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
    
    # Show workflows
    print("Workflows:")
    subprocess.run(
        ["oc", "-n", namespace, "get", "workflows.argoproj.io", 
         "--sort-by=.metadata.creationTimestamp"],
        check=False
    )
    print("")

if __name__ == "__main__":
    main()

