from kfp.dsl import component, Input, Output, Dataset


@component(
    base_image="registry.access.redhat.com/ubi9/python-311:1-77",
    packages_to_install=["requests==2.32.3"],
)
def embed_chunks_op(
    chunks_jsonl: Input[Dataset],
    embedding_url: str = "http://granite-embedding.ai-infrastructure.svc.cluster.local/v1",
    model: str = "ibm-granite/granite-embedding-125m-english",
    batch_size: int = 16,
    out_vectors: Output[Dataset] = None,
):
    """
    Call an OpenAI-compatible embeddings endpoint to embed chunk contents.
    Input: JSONL with fields {chunk_id, content, ...}
    Output: JSONL with fields {chunk_id, embedding}
    """
    import json
    import requests

    def request_embeddings(texts):
        url = f"{embedding_url}/embeddings"
        payload = {"model": model, "input": texts}
        r = requests.post(url, json=payload, timeout=60)
        r.raise_for_status()
        return r.json()

    # Read chunks
    records = []
    with open(chunks_jsonl.path, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            records.append(json.loads(line))

    # Batch embed
    outputs = []
    for i in range(0, len(records), batch_size):
        batch = records[i : i + batch_size]
        texts = [r.get("content", "") for r in batch]
        resp = request_embeddings(texts)
        vectors = resp.get("data", [])
        for j, rec in enumerate(batch):
            emb = vectors[j].get("embedding") if j < len(vectors) else None
            outputs.append({"chunk_id": rec.get("chunk_id"), "embedding": emb})

    # Write vectors
    with open(out_vectors.path, "w", encoding="utf-8") as out:
        for v in outputs:
            out.write(json.dumps(v) + "\n")

    print(f"✅ Embedded {len(outputs)} chunks → {out_vectors.path}")


