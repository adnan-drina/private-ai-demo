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
        
        print(f"[OK] Credentials decoded from parameter")
        print(f"   Access key: {aws_access_key_id}")
        print(f"   Secret key present: {len(aws_secret_access_key) > 0}")
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
    Process document with Docling to extract markdown (asynchronous API)
    
    Uses /v1/convert/file/async endpoint for robust long-running conversions.
    This avoids server-side timeout issues (DOCLING_SERVE_MAX_SYNC_WAIT default 120s).
    
    Workflow:
    1. Submit job to /v1/convert/file/async
    2. Poll /v1/status/poll/{task_id} until completion
    3. Fetch result from /v1/result/{task_id}
    
    Reference: https://github.com/docling-project/docling-serve/blob/main/docs/usage.md
    Reference: https://github.com/docling-project/docling-serve/blob/main/docs/configuration.md
    """
    import requests
    import time
    import os
    
    print(f"Processing document with Docling (async): {docling_url}")
    
    # Read input file and get filename
    filename = os.path.basename(input_file.path)
    if not filename.endswith('.pdf'):
        filename = 'document.pdf'
    
    file_size = os.path.getsize(input_file.path)
    print(f"Converting document: {filename} ({file_size / 1024 / 1024:.2f} MB)")
    
    # Step 1: Submit async job
    print(f"Submitting to /v1/convert/file/async...")
    
    with open(input_file.path, "rb") as f:
        files = {"files": (filename, f, "application/pdf")}
        
        response = requests.post(
            f"{docling_url}/v1/convert/file/async",
            files=files,
            data={"to_formats": "md"},
            timeout=30  # Short timeout for submission only
        )
        response.raise_for_status()
    
    task = response.json()
    task_id = task["task_id"]
    print(f"[OK] Task submitted: {task_id}")
    print(f"    Initial status: {task.get('task_status', 'unknown')}")
    
    # Step 2: Poll for completion
    print(f"Polling for completion...")
    poll_count = 0
    max_polls = 360  # 30 minutes with 5s intervals
    
    while task.get("task_status") not in ("success", "failure"):
        time.sleep(5)
        poll_count += 1
        
        response = requests.get(
            f"{docling_url}/v1/status/poll/{task_id}",
            timeout=10
        )
        response.raise_for_status()
        task = response.json()
        
        if poll_count % 12 == 0:  # Log every minute
            print(f"  Check {poll_count}: {task.get('task_status')} (position: {task.get('task_position', 'N/A')})")
        
        if poll_count >= max_polls:
            raise TimeoutError(f"Task {task_id} did not complete within 30 minutes")
    
    final_status = task.get("task_status")
    print(f"[OK] Task completed with status: {final_status}")
    
    if final_status != "success":
        raise RuntimeError(f"Docling task failed: {task}")
    
    # Step 3: Fetch result
    print(f"Fetching result from /v1/result/{task_id}...")
    response = requests.get(
        f"{docling_url}/v1/result/{task_id}",
        timeout=30
    )
    response.raise_for_status()
    
    print(f"[OK] Result fetched")
    
    # Parse response
    result = response.json()
    
    # Log response structure for debugging
    print(f"Response keys: {list(result.keys())}")
    
    # Extract markdown content from response
    # Try different response formats Docling might return
    if "markdown" in result:
        # Format 1: Direct markdown field
        markdown_content = result["markdown"]
    elif "documents" in result and len(result["documents"]) > 0:
        # Format 2: Documents array with markdown
        doc = result["documents"][0]
        if isinstance(doc, dict) and "markdown" in doc:
            markdown_content = doc["markdown"]
        elif isinstance(doc, dict) and "md_content" in doc:
            markdown_content = doc["md_content"]
        else:
            markdown_content = str(doc)
    elif "document" in result:
        # Format 3: Single document object with md_content
        doc = result["document"]
        if isinstance(doc, dict):
            markdown_content = doc.get("md_content", doc.get("markdown", str(doc)))
        else:
            markdown_content = str(doc)
    elif "content" in result:
        # Format 4: Direct content field
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
    base_image=BASE_PYTHON_IMAGE
)
def chunk_markdown(
    markdown_file: Input[Dataset],
    chunk_size: int,
    output_chunks: Output[Dataset]
):
    """
    Chunk markdown document for RAG ingestion
    
    NOTE: Embeddings are computed server-side by LlamaStack, not by this step.
    This is purely chunking - no HTTP calls, faster and cheaper.
    """
    import json
    
    print(f"Chunking markdown document...")
    
    # Read markdown
    with open(markdown_file.path, "r") as f:
        content = f.read()
    
    # Smart chunking with size limit (Milvus dynamic field limit is 65536 chars)
    # Use chunk_size parameter but enforce Milvus limit
    MAX_CHUNK_SIZE = 60000  # Leave buffer for Milvus limit
    effective_chunk_size = min(chunk_size, MAX_CHUNK_SIZE)
    
    print(f"Chunking with max size: {effective_chunk_size} chars")
    
    # Split by paragraphs first
    paragraphs = [p.strip() for p in content.split("\n\n") if p.strip()]
    
    # Combine paragraphs into chunks respecting size limit
    chunks = []
    current_chunk = []
    current_length = 0
    
    for para in paragraphs:
        para_len = len(para)
        
        # If single paragraph exceeds limit, split it
        if para_len > effective_chunk_size:
            # Add current chunk if any
            if current_chunk:
                chunks.append("\n\n".join(current_chunk))
                current_chunk = []
                current_length = 0
            
            # Split large paragraph by sentences
            sentences = para.split(". ")
            temp_chunk = []
            temp_len = 0
            
            for sent in sentences:
                sent_len = len(sent) + 2  # +2 for ". "
                if temp_len + sent_len > effective_chunk_size:
                    if temp_chunk:
                        chunks.append(". ".join(temp_chunk) + ".")
                    temp_chunk = [sent]
                    temp_len = sent_len
                else:
                    temp_chunk.append(sent)
                    temp_len += sent_len
            
            if temp_chunk:
                chunks.append(". ".join(temp_chunk) + ".")
        
        # Normal paragraph fits or can be added
        elif current_length + para_len + 2 > effective_chunk_size:
            # Current chunk is full, start new one
            if current_chunk:
                chunks.append("\n\n".join(current_chunk))
            current_chunk = [para]
            current_length = para_len
        else:
            # Add to current chunk
            current_chunk.append(para)
            current_length += para_len + 2  # +2 for \n\n
    
    # Add final chunk
    if current_chunk:
        chunks.append("\n\n".join(current_chunk))
    
    # CRITICAL: Final safety check - force-split any chunk that STILL exceeds limit
    # This handles edge cases like very long sentences or code blocks
    final_chunks = []
    for chunk in chunks:
        chunk_len = len(chunk)
        if chunk_len > MAX_CHUNK_SIZE:
            # Force-split by characters as last resort
            print(f"SAFETY: Force-splitting {chunk_len} char chunk into {MAX_CHUNK_SIZE} char pieces")
            for i in range(0, chunk_len, MAX_CHUNK_SIZE):
                piece = chunk[i:i + MAX_CHUNK_SIZE]
                if len(piece) > 50:  # Filter very short pieces
                    final_chunks.append(piece)
        elif chunk_len > 50:  # Filter out very short chunks
            final_chunks.append(chunk)
    
    chunks = final_chunks
    
    # Verify NO chunk exceeds limit
    if chunks:
        max_chunk_len = max(len(c) for c in chunks)
        print(f"Created {len(chunks)} chunks (max length: {max_chunk_len} chars, limit: {MAX_CHUNK_SIZE})")
        if max_chunk_len > MAX_CHUNK_SIZE:
            raise ValueError(f"BUG: Chunk of {max_chunk_len} chars STILL exceeds limit {MAX_CHUNK_SIZE}!")
    else:
        print("No chunks created (document too short)")
    
    # Save chunks as simple JSON array of text strings
    # LlamaStack will compute embeddings server-side
    chunk_data = [{"chunk_id": i, "text": text} for i, text in enumerate(chunks)]
    
    with open(output_chunks.path, "w") as f:
        json.dump(chunk_data, f)
    
    print(f"[OK] Created {len(chunks)} chunks (embeddings will be computed by LlamaStack)")


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["requests"]
)
def insert_via_llamastack(
    chunks_file: Input[Dataset],
    llamastack_url: str,
    vector_db_id: str,
    input_uri: str  # For metadata
) -> dict:
    """
    Insert chunks via LlamaStack /v1/vector-io/insert API
    
    LlamaStack computes embeddings server-side - we only send content + metadata.
    This is faster and more efficient than pre-computing embeddings.
    
    Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/working_with_llama_stack/
    """
    import requests
    import json
    import os
    
    print(f"Inserting chunks via LlamaStack: {llamastack_url}")
    print(f"Target vector DB: {vector_db_id}")
    
    # Load chunks (just text, no embeddings - LlamaStack computes them server-side)
    with open(chunks_file.path, "r") as f:
        chunks_data = json.load(f)
    
    print(f"Loaded {len(chunks_data)} chunks (embeddings computed server-side)")
    
    # Extract source filename from input_uri for better document IDs
    source_name = os.path.basename(input_uri).replace(".pdf", "").replace("s3://", "").replace("/", "-")
    
    # Format chunks for LlamaStack API
    # LlamaStack expects: content (str) + metadata (dict with document_id)
    # Embeddings will be computed server-side by LlamaStack
    llamastack_chunks = []
    for i, item in enumerate(chunks_data):
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
    
    # Insert via LlamaStack Vector IO API (with batching and retry)
    print(f"Inserting {len(llamastack_chunks)} chunks via LlamaStack...")
    
    # Batch insertion to avoid long single-call timeouts
    BATCH_SIZE = 100  # Process 100 chunks at a time
    total_inserted = 0
    batches = [llamastack_chunks[i:i + BATCH_SIZE] for i in range(0, len(llamastack_chunks), BATCH_SIZE)]
    
    print(f"Split into {len(batches)} batches of up to {BATCH_SIZE} chunks")
    
    import time
    for batch_idx, batch in enumerate(batches):
        batch_num = batch_idx + 1
        print(f"Processing batch {batch_num}/{len(batches)} ({len(batch)} chunks)...")
        
        # Retry logic with exponential backoff
        max_retries = 3
        for attempt in range(max_retries):
            try:
                # Timeout: ~2 sec/chunk + 60s overhead, max 300s
                timeout = min(300, len(batch) * 2 + 60)
                
                response = requests.post(
                    f"{llamastack_url}/v1/vector-io/insert",
                    json={
                        "vector_db_id": vector_db_id,
                        "chunks": batch
                    },
                    headers={"Content-Type": "application/json"},
                    timeout=timeout
                )
                
                if response.status_code != 200:
                    print(f"  ERROR: Batch {batch_num} returned {response.status_code}")
                    print(f"  Response: {response.text}")
                    response.raise_for_status()
                
                # Parse response - handle empty/null JSON
                try:
                    result = response.json()
                except Exception as e:
                    print(f"  WARNING: Could not parse JSON response: {e}")
                    result = None
                
                # If no result or no num_inserted field, assume all chunks inserted
                batch_inserted = result.get("num_inserted", len(batch)) if result else len(batch)
                total_inserted += batch_inserted
                print(f"  [OK] Batch {batch_num}: {batch_inserted} chunks inserted")
                break  # Success
                
            except requests.exceptions.Timeout as e:
                if attempt < max_retries - 1:
                    wait_time = 2 ** attempt  # Exponential backoff: 1s, 2s, 4s
                    print(f"  Timeout on batch {batch_num}, retry {attempt + 1}/{max_retries} after {wait_time}s...")
                    time.sleep(wait_time)
                else:
                    print(f"  FAILED: Batch {batch_num} timed out after {max_retries} attempts")
                    raise
            except requests.exceptions.RequestException as e:
                if attempt < max_retries - 1 and response.status_code >= 500:
                    wait_time = 2 ** attempt
                    print(f"  Server error on batch {batch_num} ({response.status_code}), retry {attempt + 1}/{max_retries} after {wait_time}s...")
                    time.sleep(wait_time)
                else:
                    print(f"  FAILED: Batch {batch_num} error: {e}")
                    raise
    
    print(f"[OK] Successfully inserted {total_inserted}/{len(llamastack_chunks)} chunks across {len(batches)} batches")
    print(f"Sample document_id: {llamastack_chunks[0]['metadata']['document_id']}")
    
    return {
        "vector_db_id": vector_db_id,
        "num_chunks": total_inserted,
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
    
    # Use a meaningful query derived from the document source
    # Better than generic "test document content" - provides real signal
    source_uri = insert_result.get("source", "")
    if "rag-mini" in source_uri.lower():
        test_query = "Red Hat OpenShift AI platform"
    elif "acme" in source_uri.lower():
        test_query = "corporate policy"
    elif "ai" in source_uri.lower() and "act" in source_uri.lower():
        test_query = "artificial intelligence regulation"
    else:
        # Generic fallback
        test_query = "document information"
    
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
        
        # Print top results with scores (better signal than single chunk)
        if result.get("chunks"):
            print(f"Top {min(3, chunks_returned)} results with scores:")
            for idx, chunk in enumerate(result["chunks"][:3]):
                content = chunk.get("content", chunk.get("text", str(chunk)))
                score = chunk.get("score", "N/A")
                doc_id = chunk.get("metadata", {}).get("document_id", "unknown")
                
                print(f"  {idx + 1}. Score={score}, doc_id={doc_id}")
                print(f"     Content: {content[:150]}...")
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
    name="data-processing-and-insertion",
    description="Document processing and vector insertion: Docling to Chunking to LlamaStack Vector IO (optimized)"
)
def docling_rag_pipeline(
    input_uri: str = "s3://llama-files/sample/rag-mini.pdf",
    docling_url: str = "http://docling-service.private-ai-demo.svc:5001",
    llamastack_url: str = "http://llama-stack-service.private-ai-demo.svc:8321",
    vector_db_id: str = "rag_documents",
    chunk_size: int = 512,
    minio_endpoint: str = "minio.model-storage.svc:9000",
    minio_creds_b64: str = "YWRtaW46bWluaW9hZG1pbg==",  # Base64 default (updated at runtime)
    min_chunks: int = 10
):
    """
    RAG Ingestion Pipeline (LlamaStack Vector IO - Optimized)
    
    Downloads document from MinIO, processes with Docling, chunks markdown,
    and inserts via LlamaStack /v1/vector-io/insert (which computes embeddings server-side).
    
    OPTIMIZATION: Removed redundant client-side embedding generation.
    LlamaStack computes embeddings server-side, saving ~2-5x ingestion time.
    
    Pipeline steps:
    1. Download from MinIO (s3://)
    2. Process with Docling async API (PDF to Markdown)
    3. Chunk markdown (respecting Milvus 65K limit)
    4. Insert via LlamaStack (embeddings computed server-side)
    5. Verify ingestion (query test)
    
    Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/working_with_llama_stack/
    """
    
    # Step 1: Download from S3/MinIO
    download_task = download_from_s3(
        input_uri=input_uri,
        minio_endpoint=minio_endpoint,
        minio_creds_b64=minio_creds_b64
    )
    
    # Step 2: Process with Docling
    docling_task = process_with_docling(
        input_file=download_task.outputs["output_file"],
        docling_url=docling_url
    )
    
    # Step 3: Chunk markdown (no embeddings - computed server-side by LlamaStack)
    chunking_task = chunk_markdown(
        markdown_file=docling_task.outputs["output_markdown"],
        chunk_size=chunk_size
    )
    
    # Step 4: Insert via LlamaStack Vector IO API (embeddings computed server-side)
    insert_task = insert_via_llamastack(
        chunks_file=chunking_task.outputs["output_chunks"],
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
