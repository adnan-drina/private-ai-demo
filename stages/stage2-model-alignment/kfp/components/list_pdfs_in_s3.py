"""
List PDF files from S3/MinIO prefix

This component discovers all PDF files in a given S3 prefix for batch processing.
"""

from typing import List
from kfp import dsl

# Base container images
# Pinned to specific version for reproducibility (per KFP best practices)
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:1-77"


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["boto3"]
)
def list_pdfs_in_s3(
    s3_prefix: str,
    s3_secret_mount_path: str = "/mnt/secrets",
    minio_endpoint: str = "",
    minio_creds_b64: str = ""
) -> List[str]:
    """
    Discover all PDF files in an S3 prefix
    
    Parameters:
        s3_prefix: S3 path prefix (e.g. "s3://llama-files/scenario2-acme/")
        s3_secret_mount_path: Filesystem path where S3 credentials are mounted
        minio_endpoint: Optional fallback endpoint (used if secret not mounted)
        minio_creds_b64: Optional fallback credentials in base64 ("access:secret")
    
    Returns:
        List of full S3 URIs for all PDFs found (e.g. ["s3://bucket/file1.pdf", ...])
    """
    import os
    from pathlib import Path

    import boto3
    from botocore.client import Config
    
    print(f"Discovering PDFs in: {s3_prefix}")
    
    endpoint_url = ""
    access_key = ""
    secret_key = ""

    def _read_secret(key: str) -> str:
        file_path = Path(s3_secret_mount_path) / key
        if file_path.is_file():
            return file_path.read_text().strip()
        raise FileNotFoundError

    try:
        endpoint_url = _read_secret("S3_ENDPOINT_URL")
        access_key = _read_secret("S3_ACCESS_KEY")
        secret_key = _read_secret("S3_SECRET_KEY")
        print(f"[OK] Loaded S3 credentials from secret at {s3_secret_mount_path}")
    except FileNotFoundError:
        if not minio_endpoint or not minio_creds_b64:
            raise ValueError(
                "S3 secret files were not found and fallback credentials were not provided. "
                "Provide `minio_endpoint` and `minio_creds_b64`, or mount the secret."
            )
        import base64

        creds_decoded = base64.b64decode(minio_creds_b64).decode("utf-8").strip()
        access_key, secret_key = [c.strip() for c in creds_decoded.split(":", 1)]
        endpoint_url = f"http://{minio_endpoint}" if not minio_endpoint.startswith("http") else minio_endpoint
        print("[WARN] Falling back to inline credentials (base64 parameter).")
    
    # Parse S3 prefix
    if s3_prefix.startswith("s3://"):
        s3_prefix = s3_prefix[5:]
    
    # Remove trailing slash
    s3_prefix = s3_prefix.rstrip('/')
    
    parts = s3_prefix.split("/", 1)
    bucket = parts[0]
    prefix = parts[1] + "/" if len(parts) > 1 else ""
    
    print(f"Bucket: {bucket}, Prefix: {prefix}")
    
    # Configure S3 client
    s3_client = boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
        region_name="us-east-1",
    )
    
    # List all objects with prefix
    response = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    
    if 'Contents' not in response:
        print(f"No files found in {s3_prefix}")
        return []
    
    # Filter for PDFs only
    pdf_keys = [
        obj['Key'] for obj in response['Contents']
        if obj['Key'].lower().endswith('.pdf')
    ]
    
    # Build full S3 URIs
    pdf_uris = [f"s3://{bucket}/{key}" for key in pdf_keys]
    
    print(f"[OK] Found {len(pdf_uris)} PDF files:")
    for uri in pdf_uris:
        print(f"  - {uri.split('/')[-1]}")
    
    return pdf_uris

