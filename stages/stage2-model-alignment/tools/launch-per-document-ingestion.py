#!/usr/bin/env python3
"""
Per-Document Pipeline Launcher

Submits one pipeline run per document for better UI visibility and cleaner execution.
Follows KFP best practices for production workloads.

Usage:
    ./launch-per-document-ingestion.py --scenario acme
    ./launch-per-document-ingestion.py --scenario red-hat --max-concurrent 4
    ./launch-per-document-ingestion.py --scenario eu-ai-act --dry-run

References:
    - https://www.kubeflow.org/docs/components/pipelines/user-guides/
"""

# Fix sys.path FIRST to avoid importing local kfp/ directory
import sys
from pathlib import Path

script_dir = Path(__file__).parent.resolve()
local_kfp_dir = str(script_dir / "kfp")

# Remove local kfp directory from sys.path if present
sys.path = [p for p in sys.path if Path(p).resolve() != Path(local_kfp_dir).resolve()]

# Also remove the script directory itself to avoid relative imports
sys.path = [p for p in sys.path if Path(p).resolve() != script_dir]

# Now safe to import
import argparse
import base64
import os
import subprocess
import time
from datetime import datetime
from typing import List, Dict

# Import KFP from installed package
from kfp import client as kfp_client
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


# Scenario Configuration
SCENARIOS = {
    "red-hat": {
        "s3_prefix": "s3://llama-files/scenario1-red-hat/",
        "vector_db_id": "red_hat_docs",
        "description": "Red Hat OpenShift AI documentation"
    },
    "acme": {
        "s3_prefix": "s3://llama-files/scenario2-acme/",
        "vector_db_id": "acme_corporate",
        "description": "ACME Corporate lithography system documentation"
    },
    "eu-ai-act": {
        "s3_prefix": "s3://llama-files/scenario3-eu-ai-act/",
        "vector_db_id": "eu_ai_act",
        "description": "EU AI Act regulatory documentation"
    }
}


def get_kfp_client() -> kfp_client.Client:
    """Connect to KFP API"""
    host = subprocess.check_output(
        "oc get route ds-pipeline-dspa -n private-ai-demo -o jsonpath='{.spec.host}'",
        shell=True, text=True
    ).strip()
    host = f"https://{host}"
    
    token = subprocess.check_output("oc whoami -t", shell=True, text=True).strip()
    
    return kfp_client.Client(host=host, existing_token=token, verify_ssl=False)


def get_minio_credentials() -> str:
    """Get MinIO credentials as base64-encoded string"""
    access_key = subprocess.check_output(
        "oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d",
        shell=True, text=True
    ).strip()
    
    secret_key = subprocess.check_output(
        "oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d",
        shell=True, text=True
    ).strip()
    
    return base64.b64encode(f"{access_key}:{secret_key}".encode()).decode()


def list_pdfs_in_s3(s3_prefix: str, minio_creds_b64: str) -> List[str]:
    """
    Discover all PDF files in an S3 prefix using mc (MinIO client)
    
    Returns list of full S3 URIs (e.g., ["s3://bucket/file1.pdf", ...])
    """
    # Decode credentials
    creds = base64.b64decode(minio_creds_b64).decode('utf-8')
    access_key, secret_key = creds.split(':', 1)
    
    # Parse S3 prefix
    s3_prefix_clean = s3_prefix.replace("s3://", "").rstrip('/')
    parts = s3_prefix_clean.split("/", 1)
    bucket = parts[0]
    prefix = parts[1] + "/" if len(parts) > 1 else ""
    
    # Use oc run with mc to list files
    cmd = [
        "oc", "-n", "private-ai-demo", "run", "mc-list-pdfs", 
        "--rm", "-i", "--restart=Never",
        "--image=quay.io/minio/mc",
        f"--env=AK={access_key}",
        f"--env=SK={secret_key}",
        "--env=ENDPOINT=http://minio.model-storage.svc:9000",
        "--",
        "sh", "-c",
        f"mc alias set minio $ENDPOINT $AK $SK --api S3v4 >/dev/null 2>&1 && "
        f"mc ls --recursive minio/{bucket}/{prefix} 2>/dev/null | grep -i '.pdf' | awk '{{print $NF}}'"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        
        if result.returncode == 0 and result.stdout.strip():
            # Parse output - each line is a file path
            pdf_keys = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
            
            # Build full S3 URIs
            return [f"s3://{bucket}/{key}" for key in pdf_keys if key.lower().endswith('.pdf')]
        
        return []
        
    except subprocess.TimeoutExpired:
        print("⚠️  Warning: Timeout listing PDFs from MinIO")
        return []
    except Exception as e:
        print(f"⚠️  Warning: Error listing PDFs: {e}")
        return []


def get_or_create_experiment(client: kfp_client.Client, name: str) -> str:
    """Get or create experiment and return its ID"""
    import json
    
    try:
        experiments = client.list_experiments(
            filter=json.dumps({
                "predicates": [{
                    "key": "display_name",
                    "operation": "EQUALS",
                    "stringValue": name
                }]
            })
        )
        
        if experiments and experiments.experiments:
            return experiments.experiments[0].experiment_id
        
        experiment = client.create_experiment(name=name)
        return experiment.experiment_id
        
    except Exception:
        return None


def submit_document_run(
    client: kfp_client.Client,
    pipeline_id: str,
    version_id: str,
    experiment_id: str,
    pdf_uri: str,
    vector_db_id: str,
    minio_creds_b64: str,
    scenario_name: str
) -> Dict:
    """
    Submit a single pipeline run for one document
    
    Returns dict with run_id and display_name
    """
    # Extract filename from URI for display name
    filename = pdf_uri.split('/')[-1].replace('.pdf', '')
    display_name = f"{scenario_name}-{filename}-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    
    # Parameters (all correct types)
    params = {
        "input_uri": pdf_uri,
        "docling_url": "http://docling-service.private-ai-demo.svc:5001",
        "llamastack_url": "http://llama-stack-service.private-ai-demo.svc:8321",
        "vector_db_id": vector_db_id,
        "chunk_size": 512,  # int, not string
        "minio_endpoint": "minio.model-storage.svc:9000",
        "minio_creds_b64": minio_creds_b64,
        "min_chunks": 10  # int, not string
    }
    
    # Submit run
    run = client.run_pipeline(
        experiment_id=experiment_id,
        job_name=display_name,
        pipeline_id=pipeline_id,
        version_id=version_id,
        params=params,
        enable_caching=False
    )
    
    return {
        "run_id": run.run_id,
        "display_name": display_name,
        "pdf_uri": pdf_uri
    }


def main():
    parser = argparse.ArgumentParser(
        description="Launch per-document pipeline runs for RAG ingestion",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process all ACME documents (max 2 concurrent)
  ./launch-per-document-ingestion.py --scenario acme

  # Process Red Hat docs with higher concurrency
  ./launch-per-document-ingestion.py --scenario red-hat --max-concurrent 4

  # Dry run to see what would be submitted
  ./launch-per-document-ingestion.py --scenario eu-ai-act --dry-run

Scenarios:
  red-hat    : Red Hat OpenShift AI documentation
  acme       : ACME Corporate lithography system documentation
  eu-ai-act  : EU AI Act regulatory documentation
        """
    )
    
    parser.add_argument(
        "--scenario",
        required=True,
        choices=list(SCENARIOS.keys()),
        help="Scenario to process"
    )
    
    parser.add_argument(
        "--max-concurrent",
        type=int,
        default=2,
        help="Maximum concurrent pipeline runs (default: 2)"
    )
    
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List documents without submitting runs"
    )
    
    parser.add_argument(
        "--pipeline-id",
        default="88397afe-c279-46c4-ae03-9ed25ed7a253",
        help="Pipeline ID (default: data-processing-and-insertion)"
    )
    
    parser.add_argument(
        "--version-id",
        default="fd3bc949-7dad-45ad-92c7-b349d5ef56a7",
        help="Pipeline version ID (default: v1.0.0)"
    )
    
    args = parser.parse_args()
    
    # Get scenario config
    config = SCENARIOS[args.scenario]
    
    print("=" * 80)
    print(f"🚀 Per-Document Pipeline Launcher")
    print("=" * 80)
    print()
    print(f"Scenario: {args.scenario}")
    print(f"Description: {config['description']}")
    print(f"S3 Prefix: {config['s3_prefix']}")
    print(f"Vector DB: {config['vector_db_id']}")
    print(f"Max Concurrent: {args.max_concurrent}")
    print(f"Dry Run: {args.dry_run}")
    print()
    
    # Get MinIO credentials
    print("📦 Getting MinIO credentials...")
    minio_creds_b64 = get_minio_credentials()
    print("✅ Credentials retrieved")
    print()
    
    # Discover PDFs
    print(f"🔍 Discovering PDFs in {config['s3_prefix']}...")
    pdf_uris = list_pdfs_in_s3(config['s3_prefix'], minio_creds_b64)
    
    if not pdf_uris:
        print(f"❌ No PDFs found in {config['s3_prefix']}")
        print()
        print("Please upload documents to MinIO:")
        print(f"  ./upload-to-minio.sh <file.pdf> {config['s3_prefix']}<filename>.pdf")
        return 1
    
    print(f"✅ Found {len(pdf_uris)} PDF(s):")
    for i, uri in enumerate(pdf_uris, 1):
        filename = uri.split('/')[-1]
        print(f"   {i}. {filename}")
    print()
    
    if args.dry_run:
        print("🔍 Dry run mode - would submit these runs:")
        for uri in pdf_uris:
            filename = uri.split('/')[-1].replace('.pdf', '')
            print(f"   • {args.scenario}-{filename}")
        print()
        print("Run without --dry-run to submit actual runs")
        return 0
    
    # Connect to KFP
    print("🔗 Connecting to KFP...")
    client = get_kfp_client()
    print("✅ Connected")
    print()
    
    # Get or create experiment
    experiment_name = "RAG Ingestion Experiments"
    print(f"📊 Getting experiment: {experiment_name}")
    experiment_id = get_or_create_experiment(client, experiment_name)
    if experiment_id:
        print(f"✅ Experiment ID: {experiment_id}")
    else:
        print("⚠️  Using default experiment")
    print()
    
    # Submit runs (with concurrency control)
    print(f"🚀 Submitting {len(pdf_uris)} pipeline run(s)...")
    print(f"   (Max {args.max_concurrent} concurrent)")
    print()
    
    submitted_runs = []
    active_runs = []
    
    for i, pdf_uri in enumerate(pdf_uris, 1):
        filename = pdf_uri.split('/')[-1]
        
        # Wait if at max concurrency
        while len(active_runs) >= args.max_concurrent:
            # Check status of active runs
            completed = []
            for run_info in active_runs:
                try:
                    run = client.get_run(run_id=run_info["run_id"])
                    status = run.state if hasattr(run, 'state') else 'Unknown'
                    if status in ['SUCCEEDED', 'FAILED', 'SKIPPED', 'ERROR']:
                        completed.append(run_info)
                except:
                    pass
            
            # Remove completed runs
            for run_info in completed:
                active_runs.remove(run_info)
            
            if len(active_runs) >= args.max_concurrent:
                print(f"   ⏳ Waiting for slot ({len(active_runs)}/{args.max_concurrent} active)...")
                time.sleep(5)
        
        # Submit run
        print(f"   {i}/{len(pdf_uris)} Submitting: {filename}")
        
        try:
            run_info = submit_document_run(
                client=client,
                pipeline_id=args.pipeline_id,
                version_id=args.version_id,
                experiment_id=experiment_id,
                pdf_uri=pdf_uri,
                vector_db_id=config['vector_db_id'],
                minio_creds_b64=minio_creds_b64,
                scenario_name=args.scenario
            )
            
            submitted_runs.append(run_info)
            active_runs.append(run_info)
            
            print(f"      ✅ Run ID: {run_info['run_id']}")
            
        except Exception as e:
            print(f"      ❌ Error: {e}")
    
    print()
    print("=" * 80)
    print(f"✅ Submitted {len(submitted_runs)} run(s)")
    print("=" * 80)
    print()
    
    # Print dashboard links
    host = subprocess.check_output(
        "oc get route ds-pipeline-dspa -n private-ai-demo -o jsonpath='{.spec.host}'",
        shell=True, text=True
    ).strip()
    host = f"https://{host}"
    
    print("📊 Monitor runs:")
    for run_info in submitted_runs:
        print(f"   • {run_info['display_name']}")
        print(f"     {host}/#/runs/details/{run_info['run_id']}")
        print()
    
    print("💡 Each document is now a top-level run with clear visibility!")
    print()
    
    return 0


if __name__ == "__main__":
    sys.exit(main())

