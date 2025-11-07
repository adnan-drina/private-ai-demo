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
    minio_endpoint: str,
    minio_creds_b64: str
) -> List[str]:
    """
    Discover all PDF files in an S3 prefix
    
    Parameters:
        s3_prefix: S3 path prefix (e.g. "s3://llama-files/scenario2-acme/")
        minio_endpoint: MinIO endpoint
        minio_creds_b64: Base64-encoded credentials (format: "access_key:secret_key")
    
    Returns:
        List of full S3 URIs for all PDFs found (e.g. ["s3://bucket/file1.pdf", ...])
    """
    import boto3
    from botocore.client import Config
    import base64
    
    print(f"Discovering PDFs in: {s3_prefix}")
    
    # Decode credentials
    creds_decoded = base64.b64decode(minio_creds_b64).decode('utf-8')
    aws_access_key_id, aws_secret_access_key = creds_decoded.split(':', 1)
    
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
        endpoint_url=f"http://{minio_endpoint}",
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key,
        config=Config(signature_version="s3v4"),
        region_name="us-east-1"
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

