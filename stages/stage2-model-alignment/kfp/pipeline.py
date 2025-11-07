"""
KFP v2 RAG Ingestion Pipelines - Orchestration

This file contains ONLY pipeline orchestration logic.
Individual components are in kfp/components/ directory.

Architecture follows KFP best practices:
- Small, focused, reusable components in separate files
- Pipeline composition via artifact passing (Input/Output[Dataset])
- Control flow with dsl.ParallelFor for batch processing
- Selective caching disabled on side-effect operations (insert)

References:
- KFP User Guides: https://www.kubeflow.org/docs/components/pipelines/user-guides/
- Create Components: https://www.kubeflow.org/docs/components/pipelines/user-guides/create-components/
- Control Flow: https://www.kubeflow.org/docs/components/pipelines/user-guides/core-functions/#control-flow
"""

from kfp import dsl, compiler
from pathlib import Path

# Import components from separate files
# This follows KFP's recommended pattern: small, reusable building blocks
from components.list_pdfs_in_s3 import list_pdfs_in_s3
from components.download_from_s3 import download_from_s3
from components.process_with_docling import process_with_docling
from components.chunk_markdown import chunk_markdown
from components.insert_via_llamastack import insert_via_llamastack
from components.verify_ingestion import verify_ingestion


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
    # CRITICAL: Disable caching to ensure data is always inserted (even if inputs haven't changed)
    # This prevents issues when Milvus is reset but pipeline inputs remain the same
    insert_task.set_caching_options(False)
    
    # Step 5: Verify ingestion via LlamaStack query
    verify_task = verify_ingestion(
        llamastack_url=llamastack_url,
        vector_db_id=vector_db_id,
        min_chunks=min_chunks,
        insert_result=insert_task.output
    )


@dsl.pipeline(
    name="batch-data-processing",
    description="Smart batch processing: Auto-discover PDFs in S3 path and process them all"
)
def batch_docling_rag_pipeline(
    s3_prefix: str = "s3://llama-files/sample/",
    docling_url: str = "http://docling-service.private-ai-demo.svc:5001",
    llamastack_url: str = "http://llama-stack-service.private-ai-demo.svc:8321",
    vector_db_id: str = "rag_documents",
    chunk_size: int = 512,
    minio_endpoint: str = "minio.model-storage.svc:9000",
    minio_creds_b64: str = "YWRtaW46bWluaW9hZG1pbg=="
):
    """
    Smart Batch RAG Ingestion Pipeline
    
    Automatically discovers all PDF files in the given S3 prefix and processes them
    into a single vector DB collection. Perfect for scenarios where you have multiple
    documents in a folder that all belong to the same collection.
    
    Features:
    - Auto-discovery: Just provide an S3 folder path, no need to list individual files
    - Parallel processing: Configurable parallelism (default: 2 PDFs at a time)
    - Single collection: All discovered PDFs are ingested into one collection
    
    Parameters:
        s3_prefix: S3 folder path containing PDFs (e.g. "s3://llama-files/scenario2-acme/")
        vector_db_id: Target collection name (all docs go here)
    
    Configuration:
        Parallelism: Fixed at 2 PDFs processed simultaneously (good balance for Docling load)
    
    Examples:
        # Process all ACME documents into acme_corporate collection
        s3_prefix="s3://llama-files/scenario2-acme/"
        vector_db_id="acme_corporate"
        
        # Process all EU AI Act documents
        s3_prefix="s3://llama-files/scenario3-eu-ai-act/"
        vector_db_id="eu_ai_act"
    
    Pipeline Flow:
    1. Discover all PDFs in s3_prefix (list_pdfs_in_s3)
    2. For each PDF (parallel, configurable):
       a. Download from MinIO
       b. Process with Docling (PDF → Markdown)
       c. Chunk markdown
       d. Insert into collection via LlamaStack
    
    Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/working_with_llama_stack/
    """
    
    # Step 1: Discover all PDFs in the S3 prefix
    list_task = list_pdfs_in_s3(
        s3_prefix=s3_prefix,
        minio_endpoint=minio_endpoint,
        minio_creds_b64=minio_creds_b64
    )
    
    # Step 2: Process each discovered PDF
    # ParallelFor creates a sub-DAG for each item in the list
    # Parallelism=2: process 2 PDFs simultaneously (good balance for Docling)
    with dsl.ParallelFor(
        items=list_task.output,
        parallelism=2,
        name="process-each-pdf"  # Custom name for better readability in UI
    ) as input_uri:
        
        # Download document
        download_task = download_from_s3(
            input_uri=input_uri,
            minio_endpoint=minio_endpoint,
            minio_creds_b64=minio_creds_b64
        )
        
        # Process with Docling
        docling_task = process_with_docling(
            input_file=download_task.outputs["output_file"],
            docling_url=docling_url
        )
        
        # Chunk markdown
        chunking_task = chunk_markdown(
            markdown_file=docling_task.outputs["output_markdown"],
            chunk_size=chunk_size
        )
        
        # Insert into shared collection
        insert_task = insert_via_llamastack(
            chunks_file=chunking_task.outputs["output_chunks"],
            llamastack_url=llamastack_url,
            vector_db_id=vector_db_id,
            input_uri=input_uri
        )
        # CRITICAL: Disable caching to ensure data is always inserted
        insert_task.set_caching_options(False)


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
