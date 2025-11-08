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
    s3_secret_mount_path: str,
    output_file: Output[Dataset],
    minio_endpoint: str = "",
    minio_creds_b64: str = ""
):
    """
    Download document from MinIO/S3.

    Credentials are expected to be provided via a mounted secret that matches the
    canonical Data Processing layout (`S3_ENDPOINT_URL`, `S3_ACCESS_KEY`,
    `S3_SECRET_KEY`). The component reads credential files directly, mirroring
    the upstream Docling Kubeflow pipeline pattern. For environments where
    Kubernetes secret mounts are not available (for example KFP v2 stripping
    secret refs), provide `minio_endpoint` and `minio_creds_b64` as a fallback.
    """
    import os
    from pathlib import Path

    import boto3
    from botocore.client import Config
    
    print(f"Downloading from: {input_uri}")

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
    
    # Parse S3 URI
    if input_uri.startswith("s3://"):
        input_uri = input_uri[5:]
    
    parts = input_uri.split("/", 1)
    bucket = parts[0]
    key = parts[1] if len(parts) > 1 else ""
    
    print(f"Bucket: {bucket}, Key: {key}")
    
    # Configure S3 client for MinIO/S3
    s3_client = boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
        region_name="us-east-1",
    )
    
    # Download file
    output_path = output_file.path
    s3_client.download_file(bucket, key, output_path)
    
    file_size = os.path.getsize(output_path)
    print(f"[OK] Downloaded: {file_size} bytes to {output_path}")

