# Stage 2: Model Alignment - RAG Implementation

This directory contains the implementation of Retrieval-Augmented Generation (RAG) for the Private AI Demo, using Docling for document processing, LlamaStack for orchestration, and Milvus for vector storage.

## 📁 Directory Structure

```
stage2-model-alignment/
├── deploy.sh                      # Main deployment script (deploys + triggers ingestion)
├── run-batch-ingestion.sh         # Manual ingestion script for specific scenarios
├── upload-to-minio.sh             # Upload documents to MinIO utility
├── scenario-docs/                 # Source documents for ingestion
│   ├── scenario1-red-hat/         # Red Hat RHOAI RAG guide (1 PDF)
│   ├── scenario2-acme/            # ACME corporate docs (6 PDFs)
│   └── scenario3-eu-ai-act/       # EU AI Act documents (3 PDFs)
├── kfp/                           # Kubeflow Pipelines definitions
│   ├── pipeline.py                # Main pipeline definitions
│   ├── components/                # Modular KFP components
│   │   ├── chunk_markdown.py      # Chunking component
│   │   ├── download_from_s3.py    # S3 download component
│   │   ├── insert_via_llamastack.py # Milvus insertion via LlamaStack
│   │   ├── list_pdfs_in_s3.py     # S3 listing component
│   │   ├── process_with_docling.py # Docling processing component
│   │   ├── split_pdf_list.py      # PDF list splitting for parallel processing
│   │   └── verify_ingestion.py    # Ingestion verification component
│   └── utils/                     # KFP helper utilities
│       ├── kfp-api-helpers.sh     # KFP API interaction helpers
│       └── programmatic-access.sh # OAuth authentication example
└── README.md                      # This file
```

## 🚀 Quick Start

### 1. Deploy Stage 2 Infrastructure

```bash
./deploy.sh
```

This script provides **one-click deployment**:

1. **Deploys all infrastructure:**
   - Docling service (PDF processing)
   - LlamaStack (RAG orchestration)
   - Guardrails Orchestrator (safety shields + policy enforcement)
   - LlamaStack Playground UI
   - Milvus vector database
   - KFP Data Science Pipelines

2. **Automatically uploads documents to MinIO:**
   - Scans `scenario-docs/` for PDF files
   - Uploads all documents to corresponding S3 paths
   - Skips upload if MinIO already has content

3. **Automatically triggers ingestion:**
   - Launches batch ingestion for all 3 scenarios
   - Creates pipeline runs in KFP
   - Populates Milvus collections with embeddings

**Result:** Run `./deploy.sh` once and get a fully operational RAG system with data!

### 2. Re-upload Documents (Optional)

The `deploy.sh` script automatically uploads documents from `scenario-docs/` to MinIO. However, if you need to upload additional documents or replace existing ones:

```bash
# Upload a single document
./upload-to-minio.sh /path/to/document.pdf s3://llama-files/scenario2-acme/document.pdf

# Upload entire scenario
for pdf in scenario-docs/scenario2-acme/*.pdf; do
  filename=$(basename "$pdf")
  ./upload-to-minio.sh "$pdf" "s3://llama-files/scenario2-acme/$filename"
done
```

### 3. Manual Ingestion (Optional)

The `deploy.sh` script automatically uploads documents and triggers ingestion. However, if you need to manually re-run ingestion for a specific scenario:

```bash
./run-batch-ingestion.sh <scenario>
```

Available scenarios:
- `acme` - ACME Corporate lithography documentation (6 PDFs → ~32 chunks)
- `redhat` - Red Hat OpenShift AI RAG guide (1 PDF → ~135 chunks)
- `eu-ai-act` - EU AI Act official documents (3 PDFs → ~953 chunks)

### 4. Guardrails Configuration

The Guardrails Orchestrator is fully declarative via GitOps. Before deploying you must provide secrets in the project `.env` (see `docs/SETUP.md`):

```bash
export GUARDRAILS_OPENAI_API_KEY=...
./deploy.sh  # Creates secret + syncs GitOps manifests
```

Configuration files live in `gitops/stage02-model-alignment/guardrails/`:

- `guardrails-configmap.yaml` – detector presets (PII + prompt-injection)
- `guardrails-orchestrator.yaml` – runtime definition + OTEL telemetry
- `guardrails-route.yaml` – external access for policy testing

The LlamaStack Playground reads the Guardrails route to enforce policies in the RAG UI.

**Examples:**
```bash
# Re-run ingestion for ACME scenario
./run-batch-ingestion.sh acme

# Re-run ingestion for all scenarios
for scenario in redhat acme eu-ai-act; do
  ./run-batch-ingestion.sh $scenario
done
```

## 📊 Pipeline Architecture

The batch ingestion pipeline follows this flow:

```
┌─────────────────┐
│  List PDFs      │  List all PDFs from S3 prefix
│  from S3        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Split into     │  Divide PDFs into groups for parallel processing
│  Groups         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  ParallelFor    │  Process each group in parallel
│  (Groups)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  ParallelFor    │  Process each PDF in parallel
│  (PDFs)         │
└────────┬────────┘
         │
         ├────────────────────────────────────────┐
         ▼                                        ▼
┌─────────────────┐                     ┌─────────────────┐
│  Download       │                     │  Process with   │
│  from S3        │────────────────────▶│  Docling        │
└─────────────────┘                     └────────┬────────┘
                                                  │
                                                  ▼
                                         ┌─────────────────┐
                                         │  Chunk          │
                                         │  Markdown       │
                                         └────────┬────────┘
                                                  │
                                                  ▼
                                         ┌─────────────────┐
                                         │  Insert via     │
                                         │  LlamaStack     │
                                         └─────────────────┘
```

### Key Features:
- **Parallel Processing**: PDFs are split into groups and processed in parallel for optimal throughput
- **Server-Side Embeddings**: LlamaStack handles embeddings using Granite model
- **Automatic Metadata**: Document ID, source URI, chunk index, and token count automatically added
- **Caching Disabled**: Each run is fresh (no cached results)
- **HNSW Indexing**: Milvus uses HNSW index for fast similarity search

## 🔧 Upload Documents to MinIO

```bash
# Upload a single document
./upload-to-minio.sh /path/to/document.pdf s3://llama-files/scenario2-acme/document.pdf

# Upload all PDFs from a directory
for pdf in scenario-docs/scenario2-acme/*.pdf; do
  filename=$(basename "$pdf")
  ./upload-to-minio.sh "$pdf" "s3://llama-files/scenario2-acme/$filename"
done
```

This utility handles document uploads to MinIO. All other operations (schema management, testing, ingestion) are handled by the main scripts or through the UI.

## 📚 Documentation

For detailed documentation, see:
- `docs/03-STAGE2-RAG/STAGE2-README.md` - Comprehensive Stage 2 overview
- `docs/03-STAGE2-RAG/PIPELINE-NAMING-VERSIONING.md` - Pipeline naming & versioning conventions
- `docs/03-STAGE2-RAG/PER-DOCUMENT-INGESTION.md` - Per-document ingestion guide
- `docs/03-STAGE2-RAG/KFP-BEST-PRACTICES-IMPLEMENTATION.md` - KFP implementation patterns
- `docs/03-STAGE2-RAG/FINAL-STATUS-2025-11-07.md` - Final implementation status

## 🎯 Current Status

**Production Ready** ✅

- ✅ Infrastructure deployed via GitOps
- ✅ Automated ingestion on first deploy
- ✅ 10 PDFs → 1,120 chunks in Milvus
- ✅ RAG retrieval working
- ✅ LlamaStack Playground UI operational
- ✅ All three scenarios validated

### Milvus Collections

| Collection | Documents | Chunks | Status |
|------------|-----------|--------|--------|
| `red_hat_docs` | 1 PDF | 135 | ✅ Ready |
| `acme_corporate` | 6 PDFs | 32 | ✅ Ready |
| `eu_ai_act` | 3 PDFs | 953 | ✅ Ready |

### Access Points

- **LlamaStack Playground**: https://llamastack-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com
- **KFP UI**: https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com
- **LlamaStack API**: http://llama-stack-service.private-ai-demo.svc:8321

## 🔍 Troubleshooting

### Pipeline Not Running?

Check caching is disabled:
```bash
# Verify cache_buster parameter is changing
grep "cache_buster" run-batch-ingestion.sh
```

### No Data in Milvus?

1. Check LlamaStack logs:
   ```bash
   oc logs -n private-ai-demo deployment/llama-stack -f
   ```

2. Verify data in Milvus:
   ```bash
   oc exec -n private-ai-demo deployment/milvus-standalone -- \
     python3 -c "from pymilvus import connections, Collection; connections.connect(host='localhost', port='19530'); print(Collection('acme_corporate').num_entities)"
   ```

### MinIO Upload Failing?

Check credentials and use the upload utility:
```bash
# Verify MinIO credentials
oc get secret minio-credentials -n model-storage -o jsonpath='{.data.MINIO_ROOT_USER}' | base64 -d

# Upload using the utility script
./upload-to-minio.sh /path/to/document.pdf s3://llama-files/scenario2-acme/document.pdf
```

### Need to Reset Milvus Collections?

Drop and recreate collections using kubectl:
```bash
# Delete a collection
oc exec -n private-ai-demo deployment/milvus-standalone -- \
  python3 -c "from pymilvus import connections, utility; connections.connect(host='localhost', port='19530'); utility.drop_collection('acme_corporate')"

# Collection will be auto-recreated by LlamaStack provider on next insert
```

## 📞 Support

For issues or questions, refer to the comprehensive documentation in `docs/03-STAGE2-RAG/`.

