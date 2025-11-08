"""
Insert chunks via LlamaStack Vector IO API.

This component follows the ingestion contract documented in:
- Red Hat OpenShift AI “Deploying a RAG stack in a data science project” (Docling sample).
- Milvus + LlamaStack integration guide.

Chunks are sent with structured metadata (dict, not JSON string) so the provider can
serialize fields appropriately for Milvus. Embeddings are generated server-side.
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
    # Reference: https://llama-stack.readthedocs.io/en/v0.2.11/providers/vector_io/milvus.html
    # Reference: https://milvus.io/docs/llama_stack_with_milvus.md
    #
    # Milvus schema: Int64 PK (auto_id=true), vector, content (VarChar), metadata (JSON)
    # Provider generates PK and vector; we supply content + metadata as a dictionary.
    #
    # Chunk structure:
    #   - content: string (chunk text) -> mapped to Milvus 'content' field
    #   - metadata: dict -> provider serializes for Milvus 'metadata' field
    #
    # NO id field needed - Milvus auto-generates Int64 PK.
    llamastack_chunks = []
    skipped_chunks = 0
    min_len = None
    max_len = None
    for i, item in enumerate(chunks_data):
        content_text = item.get("text") or item.get("content") or ""
        if not isinstance(content_text, str):
            content_text = str(content_text)
        stripped = content_text.strip()
        if not stripped:
            skipped_chunks += 1
            print(f"[SKIP] Chunk {i} empty after stripping; raw length={len(content_text)}")
            continue
        content_text = stripped
        
        # Calculate token count (rough estimation: ~4 chars per token)
        token_count = len(content_text) // 4
        
        metadata_dict = {
            "document_id": source_name,
            "chunk_index": int(i),
            "chunk_id": int(item.get("chunk_id", i)),
            "source_uri": input_uri,
            "token_count": int(token_count),
            "character_count": len(content_text),
        }

        extra_metadata = item.get("metadata")
        if isinstance(extra_metadata, dict):
            metadata_dict.update(extra_metadata)

        text_len = len(content_text)
        min_len = text_len if min_len is None else min(min_len, text_len)
        max_len = text_len if max_len is None else max(max_len, text_len)

        llamastack_chunks.append({
            "content": content_text,
            "metadata": metadata_dict  # Must be dict - LlamaStack API requires it
        })

    if skipped_chunks:
        print(f"Skipped {skipped_chunks} chunk(s) with empty content.")
    if llamastack_chunks:
        print(f"Prepared {len(llamastack_chunks)} chunk(s); content length range {min_len}-{max_len}.")
    
    # Insert via LlamaStack Vector IO API (with batching and retry)
    print(f"Inserting {len(llamastack_chunks)} chunks via LlamaStack...")
    
    # Batch insertion to avoid long single-call timeouts
    BATCH_SIZE = 100  # Process 100 chunks at a time
    total_inserted = 0
    batches = [llamastack_chunks[i:i + BATCH_SIZE] for i in range(0, len(llamastack_chunks), BATCH_SIZE)]
    
    print(f"Split into {len(batches)} batch(es) of up to {BATCH_SIZE} chunks")
    
    import time
    for batch_idx, batch in enumerate(batches):
        batch_num = batch_idx + 1
        print(f"Processing batch {batch_num}/{len(batches)} ({len(batch)} chunks)...")

        # Validate batch content before calling LlamaStack
        for chunk_meta in batch:
            content_val = chunk_meta.get("content")
            if not isinstance(content_val, str) or not content_val.strip():
                raise ValueError(
                    f"Chunk missing content prior to insert (batch {batch_num}): {chunk_meta.get('metadata')}"
                )
        
        # Retry logic with exponential backoff (per Milvus guidance: up to 5 retries)
        max_retries = 5
        response = None
        for attempt in range(max_retries):
            try:
                # Timeout: ~3 sec/chunk + 120s overhead, max 600s
                timeout = min(600, len(batch) * 3 + 120)
                
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
                
                batch_inserted = result.get("num_inserted", len(batch)) if result else len(batch)
                total_inserted += batch_inserted
                print(f"  [OK] Batch {batch_num}: {batch_inserted} chunks inserted")
                break  # Success
                
            except requests.exceptions.Timeout:
                if attempt < max_retries - 1:
                    wait_time = min(30, 2 ** attempt)  # 1,2,4,8,16 (cap at 30s)
                    print(f"  Timeout on batch {batch_num}, retry {attempt + 1}/{max_retries} after {wait_time}s...")
                    time.sleep(wait_time)
                else:
                    print(f"  FAILED: Batch {batch_num} timed out after {max_retries} attempts")
                    raise
            except requests.exceptions.RequestException as e:
                status_info = ""
                if response is not None:
                    status_info = f" (status {response.status_code})"
                if attempt < max_retries - 1:
                    wait_time = min(30, 2 ** attempt)
                    print(f"  Request error on batch {batch_num}{status_info}: {e}. Retry {attempt + 1}/{max_retries} after {wait_time}s...")
                    time.sleep(wait_time)
                else:
                    print(f"  FAILED: Batch {batch_num} error after retries: {e}")
                    raise
    
    print(f"[OK] Successfully inserted {total_inserted}/{len(llamastack_chunks)} chunks across {len(batches)} batches")
    if llamastack_chunks:
        print(f"Sample document_id: {llamastack_chunks[0]['metadata'].get('document_id')}")
    
    return {
        "vector_db_id": vector_db_id,
        "num_chunks": total_inserted,
        "source": input_uri,
        "status": "success"
    }

