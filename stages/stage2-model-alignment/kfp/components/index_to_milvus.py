from kfp.dsl import component, Input, Dataset


@component(
    base_image="registry.access.redhat.com/ubi9/python-311:1-77",
    packages_to_install=["pymilvus==2.4.6"],
)
def index_to_milvus_op(
    vectors_jsonl: Input[Dataset],
    milvus_uri: str = "tcp://milvus-standalone.private-ai-demo.svc.cluster.local:19530",
    collection_name: str = "rag_documents_v2",
    embedding_dimension: int = 768,
):
    """
    Create a Milvus collection if needed and insert vectors.
    Input JSONL records: {chunk_id, embedding}
    """
    import json
    from pymilvus import connections, utility, FieldSchema, CollectionSchema, DataType, Collection

    connections.connect(alias="default", uri=milvus_uri)

    # Ensure collection exists
    if not utility.has_collection(collection_name):
        fields = [
            FieldSchema(name="chunk_id", dtype=DataType.VARCHAR, is_primary=True, max_length=128),
            FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=embedding_dimension),
        ]
        schema = CollectionSchema(fields=fields, description="RAG chunks embeddings")
        coll = Collection(name=collection_name, schema=schema)
        # Create default index on vector
        coll.create_index(
            field_name="embedding",
            index_params={"index_type": "HNSW", "metric_type": "COSINE", "params": {"M": 8, "efConstruction": 64}},
        )
    else:
        coll = Collection(collection_name)

    # Read vectors and insert
    ids = []
    vecs = []
    with open(vectors_jsonl.path, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            rec = json.loads(line)
            chunk_id = rec.get("chunk_id")
            emb = rec.get("embedding")
            if chunk_id and isinstance(emb, list) and emb:
                ids.append(chunk_id)
                vecs.append(emb)

    if ids:
        coll.insert([ids, vecs])
        coll.flush()

    print(f"✅ Inserted {len(ids)} vectors into Milvus collection '{collection_name}'")


