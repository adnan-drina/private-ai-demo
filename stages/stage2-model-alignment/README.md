# Stage 2: Model Alignment with RAG

Production-ready RAG pipeline using Kubeflow Pipelines, LlamaStack, and Milvus.

## Architecture

```
┌──────────────────┐
│   KFP Pipeline   │ ← Orchestrates data processing
└────────┬─────────┘
         │
    ┌────┴────┬─────────────┬───────────┐
    │         │             │           │
    v         v             v           v
┌────────┐ ┌──────┐ ┌──────────┐ ┌──────────┐
│ MinIO  │ │Docling│ │LlamaStack│ │  Milvus  │
│Storage │ │ (Doc) │ │ (Embed)  │ │ (Vector) │
└────────┘ └───────┘ └──────────┘ └──────────┘
```

## Features

- ✅ **100x Faster Embeddings** - Granite image with PVC caching (22s → 0.22s)
- ✅ **KFP Best Practices** - Pinned images, no credential logging, clean components
- ✅ **Parallel Processing** - 2 PDFs at a time with `dsl.ParallelFor`
- ✅ **Server-Side Embeddings** - Via LlamaStack Vector IO API
- ✅ **3 Production Scenarios** - Red Hat Docs, ACME Corporate, EU AI Act

## Quick Start

### 1. Deploy Infrastructure

```bash
# Deploy Milvus, LlamaStack, Docling, and KFP
./deploy.sh
```

This deploys:
- Milvus vector database
- LlamaStack (with Granite embeddings)
- Docling service (via operator)
- KFP v2 (Data Science Pipelines Application)

### 2. Run RAG Ingestion Pipelines

**Scenario 1: Red Hat Documentation**
```bash
./run-batch-redhat.sh
```

**Scenario 2: ACME Corporate Documents**
```bash
./run-batch-acme.sh
```

**Scenario 3: EU AI Act Regulation**
```bash
./run-batch-euaiact.sh
```

Each script:
1. Compiles the pipeline (if needed)
2. Uploads to KFP
3. Creates a run with proper parameters
4. Provides monitoring URL

### 3. Test in Playground

```bash
# Get Playground URL
oc get route llama-stack-playground -n private-ai-demo -o jsonpath='{.spec.host}'
```

Open in browser and query:
- **Red Hat:** "What is Red Hat OpenShift AI?"
- **ACME:** "What is the corporate policy?"
- **EU AI Act:** "What is the EU AI Act about?"

## Pipeline Architecture

### Components (All in `kfp/pipeline.py`)

1. **`list_pdfs_in_s3`** → Discovers PDFs in MinIO
2. **`download_from_s3`** → Downloads to artifact
3. **`process_with_docling`** → PDF → Markdown (async API)
4. **`chunk_markdown`** → Token-aware chunking
5. **`insert_via_llamastack`** → Server-side embeddings + Milvus insert
6. **`verify_ingestion`** → Query-based validation

### Graph Flow

```
list-pdfs-in-s3
    ↓
process-each-pdf (ParallelFor, 2 at a time)
    ├─ download-from-s3
    ├─ process-with-docling
    ├─ chunk-markdown
    └─ insert-via-llamastack
```

## Files

```
stages/stage2-model-alignment/
├── deploy.sh                    # Deploy infrastructure
├── upload-to-minio.sh           # Upload files utility
├── run-batch-redhat.sh          # Scenario 1: Red Hat Docs
├── run-batch-acme.sh            # Scenario 2: ACME Corporate
├── run-batch-euaiact.sh         # Scenario 3: EU AI Act
├── env.template                 # Environment template
├── kfp/
│   ├── pipeline.py              # Main pipeline (production)
│   └── kfp-api-helpers.sh       # KFP API utilities
└── venv/                        # Python virtual environment
```

## Configuration

### Environment Variables

Copy `env.template` to `../../.env` at project root:

```bash
PROJECT_NAME=private-ai-demo
MINIO_ENDPOINT=minio.model-storage.svc:9000
MINIO_ACCESS_KEY=<from MinIO secret>
MINIO_SECRET_KEY=<from MinIO secret>
MINIO_KFP_BUCKET=kfp-artifacts
```

Get MinIO credentials:
```bash
oc get secret minio-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d
oc get secret minio-credentials -n model-storage -o jsonpath='{.data.secretkey}' | base64 -d
```

## Scenarios

### Scenario 1: Red Hat Documentation
- **Collection:** `red_hat_docs`
- **Source:** `s3://llama-files/scenario1-red-hat/`
- **Content:** OpenShift AI, RAG guides

### Scenario 2: ACME Corporate
- **Collection:** `acme_corporate`
- **Source:** `s3://llama-files/scenario2-acme/`
- **Content:** 6 technical documents (SOPs, playbooks, reliability reports)

### Scenario 3: EU AI Act
- **Collection:** `eu_ai_act`
- **Source:** `s3://llama-files/scenario3-eu-ai-act/`
- **Content:** Official journal, Q&A, timeline

## Uploading New Documents

```bash
# Upload a PDF to MinIO
./upload-to-minio.sh ~/my-document.pdf s3://llama-files/custom-scenario/my-document.pdf

# Then run ingestion with custom parameters
# (See kfp/pipeline.py for parameter details)
```

## Monitoring

### KFP Dashboard
```bash
oc get route ds-pipeline-dspa -n private-ai-demo -o jsonpath='{.spec.host}'
```

### LlamaStack Playground
```bash
oc get route llama-stack-playground -n private-ai-demo -o jsonpath='{.spec.host}'
```

### Milvus Collections
```python
from pymilvus import connections, utility
connections.connect(host="milvus-standalone.private-ai-demo.svc", port="19530")
print(utility.list_collections())
```

## Troubleshooting

### Pipeline Fails
- Check pod logs: `oc logs -n private-ai-demo <pod-name>`
- Verify MinIO credentials in `.env`
- Ensure Docling and LlamaStack are running

### No Results in Queries
- Check collection exists: `utility.has_collection("red_hat_docs")`
- Verify Granite embeddings cached: Check LlamaStack pod logs
- Re-run ingestion with caching disabled

### Slow Embeddings
- Ensure using Granite image: `quay.io/redhat-et/llama:vllm-milvus-granite-0.2.8`
- Check `HF_HOME` is set to `/data/hf_home` (PVC-backed)
- First run takes ~22s to download model, then 0.22s

## KFP Best Practices

This pipeline is fully aligned with [Kubeflow Pipelines User Guides](https://www.kubeflow.org/docs/components/pipelines/user-guides/):

✅ **Pinned Images** - `ubi9/python-311:1-77` (reproducible)  
✅ **No Credential Logging** - Secure by design  
✅ **Custom ParallelFor Names** - `process-each-pdf` (readable)  
✅ **Type Annotations** - `List[str]`, `Input[Dataset]`, `Output[Dataset]`  
✅ **Artifact Flow** - All data via Dataset artifacts  
✅ **Clean Components** - Single source of truth  

## Documentation

Comprehensive documentation in `../../docs/03-STAGE2-RAG/`:

1. **FINAL-SESSION-SUMMARY-2025-11-07.md** - Complete session details
2. **KFP-BEST-PRACTICES-IMPLEMENTATION.md** - Alignment guide
3. **PARALLELFOR-TYPE-ANNOTATION-FIX.md** - Type annotation fix
4. **PLAYGROUND-VALIDATION-GUIDE.md** - Testing guide
5. **LLAMASTACK-EMBEDDING-PROVIDER-ANALYSIS.md** - Embedding deep-dive

## References

- [Kubeflow Pipelines](https://www.kubeflow.org/docs/components/pipelines/)
- [LlamaStack Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/working_with_llama_stack/)
- [Docling](https://github.com/DS4SD/docling)
- [Milvus](https://milvus.io/docs)

---

**Status:** ✅ Production-ready  
**Last Updated:** 2025-11-07  
**Pipeline Version:** v20251107-110520-production-ready
