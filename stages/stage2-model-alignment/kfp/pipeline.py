from kfp import dsl

# Import components (relative imports supported when compiling in this repo)
from components.docling_parse import docling_parse_op
from components.docling_chunk import docling_chunk_op
from components.embed_chunks import embed_chunks_op
from components.index_to_milvus import index_to_milvus_op
from components.verify_ingestion import verify_ingestion_op


@dsl.pipeline(name="docling-rag-pipeline-v2")
def docling_rag_pipeline(
    input_uri: str,
    docling_url: str = "http://shared-docling-service.ai-infrastructure.svc:5001",
    chunk_size: int = 512,
    chunk_overlap: int = 50,
    embedding_url: str = "http://granite-embedding.ai-infrastructure.svc.cluster.local/v1",
    embedding_model: str = "ibm-granite/granite-embedding-125m-english",
    milvus_uri: str = "tcp://milvus-standalone.private-ai-demo.svc.cluster.local:19530",
    milvus_collection: str = "rag_documents_v2",
    embedding_dimension: int = 768,
):
    # Parse with Docling
    parsed = docling_parse_op(input_uri=input_uri, docling_url=docling_url)

    # Chunk Markdown
    chunks = docling_chunk_op(
        in_markdown=parsed.outputs["out_markdown"],
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
    )

    # Embed chunks
    vectors = embed_chunks_op(
        chunks_jsonl=chunks.outputs["out_chunks"],
        embedding_url=embedding_url,
        model=embedding_model,
    )

    # Index into Milvus
    index = index_to_milvus_op(
        vectors_jsonl=vectors.outputs["out_vectors"],
        milvus_uri=milvus_uri,
        collection_name=milvus_collection,
        embedding_dimension=embedding_dimension,
    )
    
    # Verify ingestion
    verify = verify_ingestion_op(
        milvus_uri=milvus_uri,
        collection_name=milvus_collection,
        min_chunks=10,
    )
    verify.after(index)


if __name__ == "__main__":
    # Optional helper: compile from CLI
    from kfp import compiler

    compiler.Compiler().compile(
        pipeline_func=docling_rag_pipeline,
        package_path="artifacts/docling-rag-pipeline.yaml",
    )


