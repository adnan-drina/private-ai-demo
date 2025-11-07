"""
Download document from S3/MinIO

This component downloads a PDF from MinIO using boto3.
Credentials are passed as base64-encoded parameter (per KFP v2 limitations).
"""

from kfp import dsl
from kfp.dsl import Dataset, Output

# Base container images
# Pinned to specific version for reproducibility (per KFP best practices)
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:1-77"


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["boto3", "requests"]
)
def download_from_s3(
    input_uri: str,
    minio_endpoint: str,
    minio_creds_b64: str,
    output_file: Output[Dataset]
):
    """
    Download document from MinIO/S3
    
    Credentials passed as base64-encoded string parameter (format: "access_key:secret_key")
    to work within KFP v2 limitations (strips env secretKeyRef and custom volumes).
    
    This follows Red Hat guidance: base64 encode structured/sensitive parameters,
    decode in component. Keeps secrets out of plaintext parameters.
    """
    import boto3
    from botocore.client import Config
    import base64
    import os
    
    print(f"Downloading from: {input_uri}")
    print(f"Endpoint: {minio_endpoint}")
    
    # Decode credentials from base64 parameter
    # Format: "access_key:secret_key" encoded as base64
    try:
        creds_decoded = base64.b64decode(minio_creds_b64).decode('utf-8')
        aws_access_key_id, aws_secret_access_key = creds_decoded.split(':', 1)
        
        # Security: Do not log credentials (per KFP best practices)
        print(f"[OK] Credentials decoded from parameter")
    except Exception as e:
        raise ValueError(
            "Failed to decode MinIO credentials from minio_creds_b64 parameter. "
            "Expected base64-encoded string in format 'access_key:secret_key'"
        ) from e
    
    # Parse S3 URI
    if input_uri.startswith("s3://"):
        input_uri = input_uri[5:]
    
    parts = input_uri.split("/", 1)
    bucket = parts[0]
    key = parts[1] if len(parts) > 1 else ""
    
    print(f"Bucket: {bucket}, Key: {key}")
    
    # Configure S3 client for MinIO
    s3_client = boto3.client(
        "s3",
        endpoint_url=f"http://{minio_endpoint}",
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key,
        config=Config(signature_version="s3v4"),
        region_name="us-east-1"
    )
    
    # Download file
    output_path = output_file.path
    s3_client.download_file(bucket, key, output_path)
    
    file_size = os.path.getsize(output_path)
    print(f"[OK] Downloaded: {file_size} bytes to {output_path}")

