"""
KFP v2 RAG Ingestion Pipeline
Processes documents through Docling, generates embeddings, and stores in Milvus
"""

from kfp import dsl, compiler
from kfp.dsl import Dataset, Output, Input
import sys
import os
from pathlib import Path

# Base container images
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:latest"

@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["boto3", "requests"]
)
def download_from_s3(
    input_uri: str,
    minio_endpoint: str,
    aws_access_key_id: str,
    aws_secret_access_key: str,
    output_file: Output[Dataset]
):
    """Download document from MinIO/S3"""
    import boto3
    from botocore.client import Config
    import os
    
    print(f"Downloading from: {input_uri}")
    
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


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["requests"]
)
def process_with_docling(
    input_file: Input[Dataset],
    docling_url: str,
    output_markdown: Output[Dataset]
):
    """Process document with Docling to extract markdown"""
    import requests
    import json
    import time
    import os
    
    print(f"Processing document with Docling: {docling_url}")
    
    # Read input file and get filename
    filename = os.path.basename(input_file.path)
    if not filename.endswith('.pdf'):
        filename = 'document.pdf'
    
    # Submit conversion task (async endpoint)
    with open(input_file.path, "rb") as f:
        files = {"files": (filename, f, "application/pdf")}
        
        print(f"Submitting to /v1/convert/file/async...")
        response = requests.post(
            f"{docling_url}/v1/convert/file/async",
            files=files,
            params={"format": "markdown"},
            timeout=30
        )
        response.raise_for_status()
    
    result = response.json()
    task_id = result.get("task_id")
    
    if not task_id:
        raise ValueError(f"No task_id in response: {result}")
    
    print(f"Task ID: {task_id}")
    
    # Poll for completion
    max_wait = 300  # 5 minutes
    poll_interval = 2
    elapsed = 0
    
    while elapsed < max_wait:
        poll_response = requests.get(
            f"{docling_url}/v1/result/{task_id}",
            timeout=10
        )
        poll_response.raise_for_status()
        
        poll_result = poll_response.json()
        status = poll_result.get("status", "")
        
        print(f"Status: {status} (elapsed: {elapsed}s)")
        
        if status == "success":
            # Extract markdown content
            markdown_content = poll_result.get("markdown", "")
            
            # Write markdown output
            with open(output_markdown.path, "w") as f:
                f.write(markdown_content)
            
            print(f"[OK] Extracted {len(markdown_content)} characters of markdown")
            return
        elif status == "failed":
            error = poll_result.get("error", "Unknown error")
            raise RuntimeError(f"Docling conversion failed: {error}")
        
        # Continue polling
        time.sleep(poll_interval)
        elapsed += poll_interval
    
    raise TimeoutError(f"Docling task {task_id} did not complete within {max_wait}s")


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["requests", "numpy"]
)
def generate_embeddings(
    markdown_file: Input[Dataset],
    embedding_url: str,
    embedding_model: str,
    chunk_size: int,
    output_embeddings: Output[Dataset]
):
    """Generate embeddings for document chunks"""
    import requests
    import json
    import numpy as np
    
    print(f"Generating embeddings with model: {embedding_model}")
    
    # Read markdown
    with open(markdown_file.path, "r") as f:
        content = f.read()
    
    # Simple chunking by paragraphs
    chunks = [c.strip() for c in content.split("\n\n") if c.strip() and len(c.strip()) > 20]
    print(f"Created {len(chunks)} chunks")
    
    # Generate embeddings
    embeddings = []
    for i, chunk in enumerate(chunks):
        response = requests.post(
            f"{embedding_url}/embeddings",
            json={"input": chunk, "model": embedding_model},
            timeout=60
        )
        response.raise_for_status()
        
        result = response.json()
        embedding = result["data"][0]["embedding"]
        embeddings.append({
            "chunk_id": i,
            "text": chunk,
            "embedding": embedding
        })
        
        if (i + 1) % 10 == 0:
            print(f"Generated embeddings for {i + 1}/{len(chunks)} chunks")
    
    # Save as JSON
    with open(output_embeddings.path, "w") as f:
        json.dump(embeddings, f)
    
    print(f"[OK] Generated {len(embeddings)} embeddings")


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["pymilvus"]
)
def store_in_milvus(
    embeddings_file: Input[Dataset],
    milvus_uri: str,
    milvus_collection: str,
    embedding_dimension: int,
    input_uri: str  # For metadata
) -> dict:
    """Store embeddings in Milvus"""
    from pymilvus import connections, Collection, CollectionSchema, FieldSchema, DataType, utility
    import json
    
    print(f"Connecting to Milvus: {milvus_uri}")
    
    # Connect to Milvus
    connections.connect(uri=milvus_uri, timeout=30)
    
    # Load embeddings
    with open(embeddings_file.path, "r") as f:
        embeddings_data = json.load(f)
    
    # Create collection if it doesn't exist
    if not utility.has_collection(milvus_collection):
        print(f"Creating collection: {milvus_collection}")
        
        fields = [
            FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
            FieldSchema(name="text", dtype=DataType.VARCHAR, max_length=65535),
            FieldSchema(name="source", dtype=DataType.VARCHAR, max_length=512),
            FieldSchema(name="chunk_id", dtype=DataType.INT64),
            FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=embedding_dimension)
        ]
        
        schema = CollectionSchema(fields, description="RAG document collection")
        collection = Collection(name=milvus_collection, schema=schema)
        
        # Create index
        index_params = {
            "metric_type": "L2",
            "index_type": "IVF_FLAT",
            "params": {"nlist": 128}
        }
        collection.create_index("embedding", index_params)
    else:
        collection = Collection(milvus_collection)
    
    # Prepare data
    texts = [item["text"] for item in embeddings_data]
    sources = [input_uri] * len(embeddings_data)
    chunk_ids = [item["chunk_id"] for item in embeddings_data]
    embeddings = [item["embedding"] for item in embeddings_data]
    
    # Insert data
    collection.insert([texts, sources, chunk_ids, embeddings])
    collection.flush()
    
    print(f"[OK] Inserted {len(embeddings_data)} entities into {milvus_collection}")
    
    return {
        "collection": milvus_collection,
        "num_entities": len(embeddings_data),
        "source": input_uri
    }


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["pymilvus"]
)
def verify_ingestion(
    milvus_uri: str,
    milvus_collection: str,
    min_entities: int,
    store_result: dict
) -> dict:
    """Verify that documents were ingested successfully"""
    from pymilvus import connections, Collection
    
    print(f"Verifying ingestion in collection: {milvus_collection}")
    
    # Connect to Milvus
    connections.connect(uri=milvus_uri, timeout=30)
    
    # Get collection
    collection = Collection(milvus_collection)
    collection.load()
    
    # Get stats
    num_entities = collection.num_entities
    print(f"Collection stats:")
    print(f"  Total entities: {num_entities}")
    print(f"  Minimum required: {min_entities}")
    
    # Verify threshold
    success = num_entities >= min_entities
    
    if success:
        print(f"[OK] Verification PASSED: {num_entities} >= {min_entities}")
    else:
        print(f"[FAIL] Verification FAILED: {num_entities} < {min_entities}")
    
    return {
        "success": success,
        "num_entities": num_entities,
        "min_entities": min_entities,
        "collection": milvus_collection
    }


@dsl.pipeline(
    name="docling-rag-ingestion",
    description="RAG ingestion pipeline: Docling to Embeddings to Milvus"
)
def docling_rag_pipeline(
    input_uri: str = "s3://llama-files/sample/rag-mini.pdf",
    docling_url: str = "http://docling-service.private-ai-demo.svc:5001",
    embedding_url: str = "http://llamastack.private-ai-demo.svc:8321/v1",
    embedding_model: str = "ibm-granite/granite-embedding-125m-english",
    milvus_uri: str = "tcp://milvus-standalone.private-ai-demo.svc.cluster.local:19530",
    milvus_collection: str = "rag_documents",
    embedding_dimension: int = 768,
    chunk_size: int = 512,
    minio_endpoint: str = "minio.model-storage.svc:9000",
    aws_access_key_id: str = "admin",
    aws_secret_access_key: str = "minioadmin",
    min_entities: int = 10
):
    """
    RAG Ingestion Pipeline
    
    Downloads document from MinIO, processes with Docling,
    generates embeddings, stores in Milvus, and verifies ingestion.
    """
    
    # Step 1: Download from S3/MinIO
    download_task = download_from_s3(
        input_uri=input_uri,
        minio_endpoint=minio_endpoint,
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key
    )
    
    # Step 2: Process with Docling
    docling_task = process_with_docling(
        input_file=download_task.outputs["output_file"],
        docling_url=docling_url
    )
    
    # Step 3: Generate embeddings
    embedding_task = generate_embeddings(
        markdown_file=docling_task.outputs["output_markdown"],
        embedding_url=embedding_url,
        embedding_model=embedding_model,
        chunk_size=chunk_size
    )
    
    # Step 4: Store in Milvus
    store_task = store_in_milvus(
        embeddings_file=embedding_task.outputs["output_embeddings"],
        milvus_uri=milvus_uri,
        milvus_collection=milvus_collection,
        embedding_dimension=embedding_dimension,
        input_uri=input_uri
    )
    
    # Step 5: Verify ingestion
    verify_task = verify_ingestion(
        milvus_uri=milvus_uri,
        milvus_collection=milvus_collection,
        min_entities=min_entities,
        store_result=store_task.output
    )


if __name__ == "__main__":
    # Compile pipeline
    # Calculate path relative to project root
    # This script is at: stages/stage2-model-alignment/kfp/pipeline.py
    # We need to go up 3 levels to reach project root
    script_dir = Path(__file__).parent.resolve()  # .../kfp/
    stage_dir = script_dir.parent  # .../stage2-model-alignment/
    stages_dir = stage_dir.parent  # .../stages/
    project_root = stages_dir.parent  # project root
    artifacts_dir = project_root / "artifacts"
    
    # Ensure artifacts directory exists
    artifacts_dir.mkdir(exist_ok=True)
    
    output_path = artifacts_dir / "docling-rag-pipeline.yaml"
    
    compiler.Compiler().compile(
        pipeline_func=docling_rag_pipeline,
        package_path=str(output_path)
    )
    print(f"Pipeline compiled: {output_path}")
