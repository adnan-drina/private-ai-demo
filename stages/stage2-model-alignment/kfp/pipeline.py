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
    """
    Process document with Docling to extract markdown (asynchronous)
    
    Uses /v1/convert/file/async endpoint for reliable processing of large PDFs.
    Polls /v1/result/{task_id} until completion.
    
    Reference: https://github.com/docling-project/docling-serve
    """
    import requests
    import json
    import os
    import time
    
    print(f"Processing document with Docling (async): {docling_url}")
    
    # Read input file and get filename
    filename = os.path.basename(input_file.path)
    if not filename.endswith('.pdf'):
        filename = 'document.pdf'
    
    print(f"Converting document: {filename}")
    
    # Step 1: Submit async conversion request
    with open(input_file.path, "rb") as f:
        files = {"files": (filename, f, "application/pdf")}
        
        print(f"Calling /v1/convert/file/async...")
        response = requests.post(
            f"{docling_url}/v1/convert/file/async",
            files=files,
            params={"format": "markdown"},
            timeout=30  # Short timeout for submission
        )
        response.raise_for_status()
    
    # Parse submission response
    submit_result = response.json()
    
    if "task_id" not in submit_result:
        raise ValueError(f"No task_id in response: {submit_result}")
    
    task_id = submit_result["task_id"]
    print(f"Task submitted: {task_id}")
    
    # Step 2: Poll for result
    max_wait = 600  # 10 minutes max
    poll_interval = 5  # Start with 5 seconds
    elapsed = 0
    
    while elapsed < max_wait:
        print(f"Polling result... (elapsed: {elapsed}s)")
        
        result_response = requests.get(
            f"{docling_url}/v1/result/{task_id}",
            timeout=30
        )
        result_response.raise_for_status()
        result = result_response.json()
        
        status = result.get("status", "unknown")
        print(f"  Status: {status}")
        
        if status == "success":
            print(f"[OK] Conversion completed")
            break
        elif status == "failed":
            error = result.get("error", "Unknown error")
            raise RuntimeError(f"Docling conversion failed: {error}")
        elif status in ["pending", "processing"]:
            # Continue polling
            time.sleep(poll_interval)
            elapsed += poll_interval
            # Exponential backoff up to 30s
            poll_interval = min(poll_interval * 1.2, 30)
        else:
            print(f"WARNING: Unknown status '{status}', continuing to poll")
            time.sleep(poll_interval)
            elapsed += poll_interval
    
    if elapsed >= max_wait:
        raise TimeoutError(f"Docling conversion timed out after {max_wait}s")
    
    # Step 3: Extract markdown content
    print(f"Response keys: {list(result.keys())}")
    
    # Try different response formats
    if "markdown" in result:
        markdown_content = result["markdown"]
    elif "result" in result and isinstance(result["result"], dict) and "markdown" in result["result"]:
        markdown_content = result["result"]["markdown"]
    elif "documents" in result and len(result["documents"]) > 0:
        doc = result["documents"][0]
        if isinstance(doc, dict):
            markdown_content = doc.get("markdown", doc.get("md_content", str(doc)))
        else:
            markdown_content = str(doc)
    elif "document" in result:
        doc = result["document"]
        if isinstance(doc, dict):
            markdown_content = doc.get("md_content", doc.get("markdown", str(doc)))
        else:
            markdown_content = str(doc)
    elif "content" in result:
        markdown_content = result["content"]
    else:
        # Fallback: stringify result and warn
        markdown_content = str(result)
        print(f"WARNING: Unexpected response format, stringifying result!")
        print(f"Response keys: {list(result.keys())}")
        print(f"Sample: {str(result)[:500]}")
    
    # Write markdown output
    with open(output_markdown.path, "w") as f:
        f.write(markdown_content)
    
    print(f"[OK] Extracted {len(markdown_content)} characters of markdown")
    print(f"Preview: {markdown_content[:200]}...")


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
    packages_to_install=["requests"]
)
def insert_via_llamastack(
    embeddings_file: Input[Dataset],
    llamastack_url: str,
    vector_db_id: str,
    input_uri: str  # For metadata
) -> dict:
    """
    Insert chunks via LlamaStack /v1/vector-io/insert API
    
    This follows Red Hat RHOAI 2.25 best practices by using LlamaStack's
    Vector IO API instead of direct Milvus writes. LlamaStack manages
    the schema and ensures compatibility.
    
    Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/working_with_llama_stack/
    """
    import requests
    import json
    import os
    
    print(f"Inserting chunks via LlamaStack: {llamastack_url}")
    print(f"Target vector DB: {vector_db_id}")
    
    # Load embeddings data
    with open(embeddings_file.path, "r") as f:
        embeddings_data = json.load(f)
    
    print(f"Loaded {len(embeddings_data)} chunks from pipeline")
    
    # Extract source filename from input_uri for better document IDs
    source_name = os.path.basename(input_uri).replace(".pdf", "").replace("s3://", "").replace("/", "-")
    
    # Format chunks for LlamaStack API
    # LlamaStack expects: content (str) + metadata (dict with document_id)
    llamastack_chunks = []
    for i, item in enumerate(embeddings_data):
        chunk = {
            "content": item.get("text", item.get("content", "")),
            "metadata": {
                "document_id": f"{source_name}-chunk-{i}",
                "source": input_uri,
                "chunk_index": i,
                "chunk_id": item.get("chunk_id", i)  # Keep original for reference
            }
        }
        llamastack_chunks.append(chunk)
    
    # Insert via LlamaStack Vector IO API
    print(f"Calling POST {llamastack_url}/v1/vector-io/insert...")
    
    response = requests.post(
        f"{llamastack_url}/v1/vector-io/insert",
        json={
            "vector_db_id": vector_db_id,
            "chunks": llamastack_chunks
        },
        headers={"Content-Type": "application/json"},
        timeout=300  # 5 minutes for large batches
    )
    
    # Check response
    if response.status_code != 200:
        print(f"ERROR: LlamaStack returned {response.status_code}")
        print(f"Response: {response.text}")
        response.raise_for_status()
    
    print(f"[OK] Successfully inserted {len(llamastack_chunks)} chunks into {vector_db_id}")
    print(f"Sample document_id: {llamastack_chunks[0]['metadata']['document_id']}")
    
    return {
        "vector_db_id": vector_db_id,
        "num_chunks": len(llamastack_chunks),
        "source": input_uri,
        "status": "success"
    }


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["requests"]
)
def verify_ingestion(
    llamastack_url: str,
    vector_db_id: str,
    min_chunks: int,
    insert_result: dict
) -> dict:
    """
    Verify ingestion by querying LlamaStack Vector IO API
    
    Tests that chunks can be retrieved via /v1/vector-io/query
    """
    import requests
    import json
    
    print(f"Verifying ingestion in vector DB: {vector_db_id}")
    print(f"Insert result: {insert_result}")
    
    # Test query to verify chunks are retrievable
    test_query = "test document content"
    
    print(f"Testing retrieval with query: '{test_query}'")
    
    response = requests.post(
        f"{llamastack_url}/v1/vector-io/query",
        json={
            "vector_db_id": vector_db_id,
            "query": test_query,
            "params": {"top_k": 5}
        },
        headers={"Content-Type": "application/json"},
        timeout=60
    )
    
    if response.status_code != 200:
        print(f"ERROR: Query failed with status {response.status_code}")
        print(f"Response: {response.text}")
        return {
            "success": False,
            "error": f"Query failed: {response.status_code}",
            "vector_db_id": vector_db_id
        }
    
    result = response.json()
    chunks_returned = len(result.get("chunks", []))
    
    print(f"Query returned {chunks_returned} chunks")
    
    # Verify we got results
    num_chunks = insert_result.get("num_chunks", 0)
    success = chunks_returned > 0 and num_chunks >= min_chunks
    
    print(f"Ingestion verification:")
    print(f"  Chunks inserted: {num_chunks}")
    print(f"  Chunks retrieved: {chunks_returned}")
    print(f"  Minimum required: {min_chunks}")
    
    if success:
        print(f"[OK] Verification PASSED")
        
        # Print sample chunk
        if result.get("chunks"):
            sample_chunk = result["chunks"][0]
            print(f"Sample retrieved chunk (first 100 chars):")
            print(f"  {sample_chunk[:100]}...")
    else:
        print(f"[FAIL] Verification FAILED")
    
    return {
        "success": success,
        "num_chunks_inserted": num_chunks,
        "num_chunks_retrieved": chunks_returned,
        "min_chunks": min_chunks,
        "vector_db_id": vector_db_id
    }


@dsl.pipeline(
    name="docling-rag-ingestion",
    description="RAG ingestion pipeline: Docling to Embeddings to LlamaStack Vector IO"
)
def docling_rag_pipeline(
    input_uri: str = "s3://llama-files/sample/rag-mini.pdf",
    docling_url: str = "http://docling-service.private-ai-demo.svc:5001",
    embedding_url: str = "http://granite-embedding.private-ai-demo.svc/v1",
    embedding_model: str = "ibm-granite/granite-embedding-125m-english",
    llamastack_url: str = "http://llama-stack-service.private-ai-demo.svc:8321",
    vector_db_id: str = "rag_documents",
    embedding_dimension: int = 768,
    chunk_size: int = 512,
    minio_endpoint: str = "minio.model-storage.svc:9000",
    aws_access_key_id: str = "admin",
    aws_secret_access_key: str = "minioadmin",
    min_chunks: int = 10
):
    """
    RAG Ingestion Pipeline (LlamaStack Vector IO)
    
    Downloads document from MinIO, processes with Docling,
    generates embeddings, inserts via LlamaStack /v1/vector-io/insert,
    and verifies retrieval.
    
    This implementation follows Red Hat RHOAI 2.25 best practices by
    using LlamaStack's Vector IO API instead of direct Milvus writes.
    LlamaStack manages the schema and ensures compatibility.
    
    Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/working_with_llama_stack/
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
    
    # Step 4: Insert via LlamaStack Vector IO API
    insert_task = insert_via_llamastack(
        embeddings_file=embedding_task.outputs["output_embeddings"],
        llamastack_url=llamastack_url,
        vector_db_id=vector_db_id,
        input_uri=input_uri
    )
    
    # Step 5: Verify ingestion via LlamaStack query
    verify_task = verify_ingestion(
        llamastack_url=llamastack_url,
        vector_db_id=vector_db_id,
        min_chunks=min_chunks,
        insert_result=insert_task.output
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
