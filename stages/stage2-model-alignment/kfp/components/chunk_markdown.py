"""
Chunk markdown document for RAG ingestion

This component splits markdown into manageable chunks for vector storage.
Respects Milvus field size limits and handles edge cases robustly.

NOTE: Embeddings are computed server-side by LlamaStack, not by this component.
"""

from kfp import dsl
from kfp.dsl import Dataset, Output, Input

# Base container images
# Pinned to specific version for reproducibility (per KFP best practices)
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:1-77"


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

