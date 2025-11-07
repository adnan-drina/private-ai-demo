"""
Insert chunks via LlamaStack Vector IO API

This component inserts document chunks into Milvus via LlamaStack's /v1/vector-io/insert API.
LlamaStack computes embeddings server-side using the configured embedding model.

Includes batching and exponential backoff retry logic for reliability.
"""

from kfp import dsl
from kfp.dsl import Dataset, Input

# Base container images
# Pinned to specific version for reproducibility (per KFP best practices)
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:1-77"


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
    # LlamaStack expects: content (str) + metadata (dict with document_id AND token_count)
    # Embeddings will be computed server-side by LlamaStack
    #
    # CRITICAL: RAG tool requires 'token_count' in metadata to calculate context window usage
    # Without it, RAG queries fail with KeyError: 'token_count'
    llamastack_chunks = []
    for i, item in enumerate(chunks_data):
        content = item.get("text", item.get("content", ""))
        
        # Calculate token count (rough estimation: ~4 chars per token)
        # This is used by LlamaStack RAG tool to track context window usage
        # More accurate: use tiktoken, but simple estimation is sufficient
        token_count = len(content) // 4
        
        chunk = {
            "content": content,
            "metadata": {
                "document_id": f"{source_name}-chunk-{i}",
                "source": input_uri,
                "chunk_index": i,
                "chunk_id": item.get("chunk_id", i),  # Keep original for reference
                "token_count": token_count  # Required by RAG tool
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

