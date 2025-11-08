"""
Verify ingestion by querying LlamaStack Vector IO API

This component validates that chunks were successfully inserted and can be retrieved
by performing a test query against the vector database.
"""

from kfp import dsl

# Base container images
# Pinned to specific version for reproducibility (per KFP best practices)
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:1-77"


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

