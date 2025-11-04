# KFP v2 Pipeline Design - Document Ingestion & RAG

**Date:** November 3, 2025  
**Purpose:** Custom RAG pipeline using Milvus + vLLM (Alternative to LlamaStack)

---

## Overview

With LlamaStack blocked by distribution limitations, this design provides a production-ready RAG solution using components that are **proven working** in our environment.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Document Ingestion Pipeline                          │
│                          (KFP v2 Pipeline)                               │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  1. Document Upload                │
              │     Input: PDF/DOCX/TXT            │
              │     Storage: MinIO (llama-files)   │
              └────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  2. Document Processing (Docling)  │
              │     URL: http://docling.svc:8080   │
              │     Output: Structured JSON        │
              └────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  3. Text Chunking                  │
              │     Strategy: Recursive split      │
              │     Chunk size: 512 tokens         │
              │     Overlap: 50 tokens             │
              └────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  4. Generate Embeddings            │
              │     Model: granite-embedding-125m  │
              │     Dimension: 768                 │
              │     Batch size: 32                 │
              └────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  5. Store in Milvus                │
              │     Collection: rag_documents      │
              │     Index: IVF_FLAT                │
              │     Metadata: source, page, etc    │
              └────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                        Query Pipeline                                    │
│                     (Python API Service)                                 │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  1. Query Embedding                │
              │     Same model as ingestion        │
              │     granite-embedding-125m         │
              └────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  2. Vector Search (Milvus)         │
              │     Top-K: 5 documents             │
              │     Similarity: cosine             │
              │     Filter: metadata optional      │
              └────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  3. Context Assembly               │
              │     Rerank by relevance (optional) │
              │     Format for prompt              │
              └────────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────────────────────────────┐
              │  4. LLM Inference (vLLM)           │
              │     Quantized or Full model        │
              │     OpenAI-compatible API          │
              │     Streaming response             │
              └────────────────────────────────────┘
```

---

## Component Details

### 1. Document Ingestion Pipeline (KFP v2)

**Pipeline Name:** `document-ingestion-v1`  
**Trigger:** Manual, API, or S3 event  
**Execution:** DSPA / KFP v2

#### Pipeline Parameters:
```python
@dsl.pipeline(
    name='document-ingestion-v1',
    description='Process documents and store in Milvus for RAG'
)
def document_ingestion_pipeline(
    document_uri: str,
    collection_name: str = 'rag_documents',
    chunk_size: int = 512,
    chunk_overlap: int = 50,
    batch_size: int = 32
):
    # Pipeline components defined below
    pass
```

#### Component 1: Upload to MinIO
```python
@dsl.component(
    base_image='quay.io/minio/mc:latest',
    packages_to_install=['boto3']
)
def upload_document(
    document_path: str,
    bucket: str = 'llama-files'
) -> str:
    """Upload document to MinIO and return S3 URI."""
    import boto3
    s3 = boto3.client('s3', 
        endpoint_url='http://minio.model-storage.svc:9000',
        aws_access_key_id=os.getenv('MINIO_ACCESS_KEY'),
        aws_secret_access_key=os.getenv('MINIO_SECRET_KEY')
    )
    # Upload logic
    return f"s3://{bucket}/{filename}"
```

#### Component 2: Process with Docling
```python
@dsl.component(
    base_image='registry.access.redhat.com/ubi9/python-311:latest',
    packages_to_install=['requests']
)
def process_document(
    document_uri: str
) -> dict:
    """Send document to Docling for processing."""
    import requests
    response = requests.post(
        'http://docling.private-ai-demo.svc:8080/process',
        json={'document_uri': document_uri}
    )
    return response.json()
```

#### Component 3: Chunk Text
```python
@dsl.component(
    base_image='registry.access.redhat.com/ubi9/python-311:latest',
    packages_to_install=['langchain', 'tiktoken']
)
def chunk_text(
    processed_doc: dict,
    chunk_size: int = 512,
    overlap: int = 50
) -> list:
    """Split text into overlapping chunks."""
    from langchain.text_splitter import RecursiveCharacterTextSplitter
    
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=overlap,
        separators=["\n\n", "\n", ". ", " ", ""]
    )
    
    chunks = []
    for page in processed_doc['pages']:
        page_chunks = splitter.split_text(page['text'])
        chunks.extend([{
            'text': chunk,
            'metadata': {
                'source': processed_doc['source'],
                'page': page['page_num'],
                'chunk_id': i
            }
        } for i, chunk in enumerate(page_chunks)])
    
    return chunks
```

#### Component 4: Generate Embeddings
```python
@dsl.component(
    base_image='registry.access.redhat.com/ubi9/python-311:latest',
    packages_to_install=['sentence-transformers', 'torch']
)
def generate_embeddings(
    chunks: list,
    model_name: str = 'ibm-granite/granite-embedding-125m-english',
    batch_size: int = 32
) -> list:
    """Generate embeddings using granite-embedding model."""
    from sentence_transformers import SentenceTransformer
    
    model = SentenceTransformer(model_name)
    texts = [chunk['text'] for chunk in chunks]
    
    embeddings = model.encode(
        texts,
        batch_size=batch_size,
        show_progress_bar=True,
        convert_to_numpy=True
    )
    
    for i, chunk in enumerate(chunks):
        chunk['embedding'] = embeddings[i].tolist()
    
    return chunks
```

#### Component 5: Store in Milvus
```python
@dsl.component(
    base_image='registry.access.redhat.com/ubi9/python-311:latest',
    packages_to_install=['pymilvus']
)
def store_in_milvus(
    chunks: list,
    collection_name: str = 'rag_documents'
) -> str:
    """Store embeddings in Milvus."""
    from pymilvus import connections, Collection, FieldSchema, CollectionSchema, DataType
    
    connections.connect(
        host='milvus-standalone.private-ai-demo.svc.cluster.local',
        port='19530'
    )
    
    # Prepare data
    ids = list(range(len(chunks)))
    texts = [c['text'] for c in chunks]
    embeddings = [c['embedding'] for c in chunks]
    metadata = [json.dumps(c['metadata']) for c in chunks]
    
    # Insert
    collection = Collection(collection_name)
    collection.insert([ids, texts, embeddings, metadata])
    collection.flush()
    
    return f"Inserted {len(chunks)} chunks into {collection_name}"
```

---

### 2. Query API Service

**Technology:** FastAPI  
**Deployment:** Kubernetes Deployment  
**Namespace:** private-ai-demo

#### API Endpoints:

##### POST /query
```json
{
  "query": "What are the GDPR compliance requirements?",
  "top_k": 5,
  "model": "mistral-24b-quantized",  // or "mistral-24b-full"
  "stream": true,
  "filters": {
    "source": "gdpr-regulation.pdf"  // optional
  }
}
```

##### POST /ingest
```json
{
  "document_uri": "s3://llama-files/document.pdf",
  "metadata": {
    "category": "legal",
    "language": "en"
  }
}
```

##### GET /health
```json
{
  "status": "healthy",
  "milvus": "connected",
  "vllm": "ready"
}
```

#### Implementation:
```python
from fastapi import FastAPI, HTTPException
from pymilvus import connections, Collection
from openai import OpenAI
import os

app = FastAPI(title="RAG Query API")

# Initialize connections
connections.connect(
    host='milvus-standalone.private-ai-demo.svc.cluster.local',
    port='19530'
)

vllm_client = OpenAI(
    base_url="https://mistral-24b-quantized-private-ai-demo.apps.cluster.com/v1",
    api_key="not-needed"
)

@app.post("/query")
async def query_documents(request: QueryRequest):
    # 1. Generate query embedding
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('ibm-granite/granite-embedding-125m-english')
    query_embedding = model.encode([request.query])[0].tolist()
    
    # 2. Search Milvus
    collection = Collection('rag_documents')
    collection.load()
    
    results = collection.search(
        data=[query_embedding],
        anns_field="embedding",
        param={"metric_type": "IP", "params": {"nprobe": 10}},
        limit=request.top_k,
        output_fields=["text", "metadata"]
    )
    
    # 3. Build context
    context = "\n\n".join([hit.entity.get('text') for hit in results[0]])
    
    # 4. Call vLLM
    prompt = f"""Context:
{context}

Question: {request.query}

Answer the question based on the context provided above."""
    
    response = vllm_client.chat.completions.create(
        model=request.model,
        messages=[
            {"role": "system", "content": "You are a helpful assistant that answers questions based on the provided context."},
            {"role": "user", "content": prompt}
        ],
        stream=request.stream,
        temperature=0.7,
        max_tokens=1024
    )
    
    if request.stream:
        return StreamingResponse(
            stream_response(response),
            media_type="text/event-stream"
        )
    else:
        return {
            "answer": response.choices[0].message.content,
            "sources": [
                json.loads(hit.entity.get('metadata'))
                for hit in results[0]
            ]
        }

@app.post("/ingest")
async def ingest_document(request: IngestRequest):
    # Trigger KFP pipeline
    from kfp import Client
    client = Client(host='http://ds-pipeline-dspa.private-ai-demo.svc:8888')
    
    run = client.create_run_from_pipeline_func(
        document_ingestion_pipeline,
        arguments={
            'document_uri': request.document_uri,
            'collection_name': 'rag_documents'
        }
    )
    
    return {
        "pipeline_run_id": run.run_id,
        "status": "started"
    }
```

---

## Deployment

### 1. KFP Pipeline Deployment
```bash
# Compile pipeline
python3 document_ingestion_pipeline.py

# Upload to KFP
kfp pipeline upload document-ingestion-v1.yaml

# Or use Python SDK
from kfp import Client
client = Client(host='http://ds-pipeline-dspa.private-ai-demo.svc:8888')
client.upload_pipeline('document-ingestion-v1.yaml', 'Document Ingestion v1')
```

### 2. Query API Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rag-query-api
  namespace: private-ai-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: rag-query-api
  template:
    metadata:
      labels:
        app: rag-query-api
    spec:
      containers:
      - name: api
        image: registry.redhat.io/ubi9/python-311:latest
        command: ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
        env:
        - name: MILVUS_HOST
          value: "milvus-standalone.private-ai-demo.svc.cluster.local"
        - name: VLLM_BASE_URL
          value: "https://mistral-24b-quantized-private-ai-demo.apps.cluster.com/v1"
        ports:
        - containerPort: 8000
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: rag-query-api
  namespace: private-ai-demo
spec:
  selector:
    app: rag-query-api
  ports:
  - port: 8000
    targetPort: 8000
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: rag-query-api
  namespace: private-ai-demo
spec:
  to:
    kind: Service
    name: rag-query-api
  port:
    targetPort: 8000
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

---

## Testing

### 1. Test Document Ingestion
```bash
# Upload test document
curl -X POST https://rag-query-api-private-ai-demo.apps.cluster.com/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "document_uri": "s3://llama-files/test-doc.pdf",
    "metadata": {"category": "test"}
  }'

# Check pipeline status
oc get pipelinerun -n private-ai-demo | grep document-ingestion
```

### 2. Test Query
```bash
# Non-streaming
curl -X POST https://rag-query-api-private-ai-demo.apps.cluster.com/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is GDPR?",
    "top_k": 5,
    "model": "mistral-24b-quantized",
    "stream": false
  }'

# Streaming
curl -X POST https://rag-query-api-private-ai-demo.apps.cluster.com/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is GDPR?",
    "top_k": 5,
    "model": "mistral-24b-quantized",
    "stream": true
  }'
```

---

## Monitoring

### 1. Pipeline Metrics
- KFP dashboard: Monitor pipeline runs
- Success rate, duration, resource usage
- Failed steps and retry logic

### 2. API Metrics
- Prometheus metrics: `/metrics` endpoint
- Latency, throughput, error rates
- Milvus query time, vLLM inference time

### 3. Data Quality
- Document count in Milvus
- Embedding quality checks
- Query relevance scoring

---

## Benefits of This Approach

✅ **All Components Working:** Milvus, Docling, vLLM, KFP all proven  
✅ **Production-Ready:** No distribution limitations  
✅ **Full Control:** Direct access to all components  
✅ **Scalable:** Each component scales independently  
✅ **Observable:** Full metrics and logging  
✅ **Maintainable:** Standard Python/FastAPI stack  
✅ **Red Hat Aligned:** Uses RHOAI components (KFP, vLLM)

---

## Timeline

**Phase 1: Pipeline Development** (1-2 weeks)
- Implement KFP components
- Test document ingestion flow
- Validate embeddings and storage

**Phase 2: Query API** (1 week)
- Build FastAPI service
- Implement query logic
- Test end-to-end RAG

**Phase 3: Production Hardening** (1 week)
- Add monitoring and logging
- Performance optimization
- Security review

---

## Next Steps

1. **Create KFP components** in `pipelines/rag-ingestion/`
2. **Build Query API** in `api/rag-query/`
3. **Test with sample documents**
4. **Deploy to production** via ArgoCD

---

## Conclusion

This design provides a **production-ready RAG solution** using components that are **proven working** in our environment. It avoids LlamaStack's distribution limitations while leveraging Red Hat's RHOAI platform capabilities.

**Status:** Ready to implement  
**Risk:** Low (all components verified)  
**Timeline:** 3-4 weeks to production

