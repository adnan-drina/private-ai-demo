from kfp.dsl import component, Output, Metrics


@component(
    base_image="registry.access.redhat.com/ubi9/python-311:1-77",
    packages_to_install=["pymilvus==2.4.6"],
)
def verify_ingestion_op(
    milvus_uri: str = "tcp://milvus-standalone.private-ai-demo.svc.cluster.local:19530",
    collection_name: str = "rag_documents_v2",
    min_chunks: int = 10,
    metrics: Output[Metrics] = None,
):
    """
    Verify ingestion by querying Milvus collection count and asserting minimum threshold.
    
    - milvus_uri: Milvus connection URI
    - collection_name: Collection to verify
    - min_chunks: Minimum expected chunk count
    - Emits metrics: chunk_count, verification_status
    """
    from pymilvus import connections, Collection
    
    print(f"🔍 Connecting to Milvus at {milvus_uri}")
    connections.connect(alias="default", uri=milvus_uri)
    
    print(f"📊 Verifying collection '{collection_name}'")
    coll = Collection(collection_name)
    coll.load()
    count = coll.num_entities
    
    print(f"   Found {count} entities in collection")
    
    if count < min_chunks:
        raise RuntimeError(
            f"❌ Verification failed: {count} chunks < {min_chunks} minimum threshold"
        )
    
    # Log metrics for KFP UI
    metrics.log_metric("chunk_count", count)
    metrics.log_metric("verification_status", 1.0)  # 1.0 = success
    metrics.log_metric("min_threshold", min_chunks)
    
    print(f"✅ Verification passed: {count} chunks ingested (>= {min_chunks} threshold)")

