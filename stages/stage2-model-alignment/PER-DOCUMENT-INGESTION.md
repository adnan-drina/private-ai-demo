# Per-Document Pipeline Ingestion

**Recommended approach for production RAG ingestion**

## Overview

This launcher submits **one pipeline run per document** instead of using `ParallelFor` loops. This provides:

✅ **Better UI visibility** - Each document is a top-level run  
✅ **Cleaner components** - No complex loop logic  
✅ **Controlled concurrency** - Limit concurrent runs (2-4 recommended)  
✅ **Individual tracking** - Monitor each document's progress separately  
✅ **Cleaner failure handling** - Failed documents don't affect others  

## Quick Start

```bash
# Process all ACME documents (max 2 concurrent)
./launch-per-document-ingestion.py --scenario acme

# Process Red Hat docs with higher concurrency  
./launch-per-document-ingestion.py --scenario red-hat --max-concurrent 4

# Dry run to see what would be submitted
./launch-per-document-ingestion.py --scenario eu-ai-act --dry-run
```

## When to Use

### ✅ Use Per-Document Launcher (Recommended)

- **Production ingestion** of scenario documents
- **Large document sets** (10+ PDFs)
- When you need **per-document visibility** in UI
- When you want **controlled concurrency**
- For **scheduled/automated** ingestion

### ⚠️ Use Batch Pipeline (ParallelFor)

- **Ad-hoc testing** of small batches (2-5 PDFs)
- **Quick validation** of pipeline changes
- When UI clutter from many runs is acceptable
- **Small folders** only (cap parallelism to 2-3)

## Architecture

### Workflow

```
Launcher Script (Local)
  │
  ├─→ Discovers all PDFs in S3 path
  │
  ├─→ For each PDF:
  │   │
  │   ├─→ Submit pipeline run
  │   │   (Wait if at max concurrency)
  │   │
  │   └─→ Run includes:
  │       ├─ download-from-s3
  │       ├─ process-with-docling (async)
  │       ├─ chunk-markdown
  │       ├─ insert-via-llamastack
  │       └─ verify-ingestion
  │
  └─→ Monitor active runs
      (Remove completed from active pool)
```

### Dashboard View

Each document gets its own top-level run:

```
Runs:
  ├─ acme-ACME_01_DFO_Calibration_SOP-20251107-124500
  ├─ acme-ACME_02_Lithography_Control_Plan-20251107-124505
  ├─ acme-ACME_03_Tool_Health_FMEA-20251107-124510
  └─ ...
```

vs. Batch Pipeline (ParallelFor):

```
Runs:
  └─ acme-batch-20251107-124500
      ├─ process-each-pdf (loop)
      │   ├─ [0] → ACME_01...
      │   ├─ [1] → ACME_02...
      │   └─ [2] → ACME_03...
```

## Configuration

### Scenarios

Three pre-configured scenarios:

| Scenario | Vector DB | S3 Path |
|----------|-----------|---------|
| `red-hat` | `red_hat_docs` | `s3://llama-files/scenario1-red-hat/` |
| `acme` | `acme_corporate` | `s3://llama-files/scenario2-acme/` |
| `eu-ai-act` | `eu_ai_act` | `s3://llama-files/scenario3-eu-ai-act/` |

### Parameters

All parameters use correct types (no string conversion issues):

```python
{
    "input_uri": "s3://llama-files/scenario2-acme/doc.pdf",  # str
    "docling_url": "http://docling-service.private-ai-demo.svc:5001",  # str
    "llamastack_url": "http://llama-stack-service.private-ai-demo.svc:8321",  # str
    "vector_db_id": "acme_corporate",  # str
    "chunk_size": 512,  # int (not string!)
    "minio_endpoint": "minio.model-storage.svc:9000",  # str
    "minio_creds_b64": "<base64>",  # str
    "min_chunks": 10  # int (not string!)
}
```

### Concurrency Control

```python
--max-concurrent 2  # Default: Safe for Docling/LlamaStack capacity
--max-concurrent 3  # Higher: Faster but more load
--max-concurrent 4  # Maximum recommended
```

**Rationale:**
- Docling async API can handle 2-3 concurrent extractions
- LlamaStack Vector IO insertion is fast
- Higher concurrency = more cluster resources

## Usage Examples

### Example 1: Process ACME Documents

```bash
# 1. Upload documents to MinIO
./upload-to-minio.sh ~/docs/ACME_01.pdf s3://llama-files/scenario2-acme/ACME_01.pdf
./upload-to-minio.sh ~/docs/ACME_02.pdf s3://llama-files/scenario2-acme/ACME_02.pdf
# ... etc

# 2. Launch per-document ingestion
./launch-per-document-ingestion.py --scenario acme

# Output:
# ════════════════════════════════════════════════════════════════
# 🚀 Per-Document Pipeline Launcher
# ════════════════════════════════════════════════════════════════
# 
# Scenario: acme
# Description: ACME Corporate lithography system documentation
# S3 Prefix: s3://llama-files/scenario2-acme/
# Vector DB: acme_corporate
# Max Concurrent: 2
# 
# 🔍 Discovering PDFs in s3://llama-files/scenario2-acme/...
# ✅ Found 6 PDF(s):
#    1. ACME_01_DFO_Calibration_SOP.pdf
#    2. ACME_02_Lithography_Control_Plan.pdf
#    ... etc
#
# 🚀 Submitting 6 pipeline run(s)...
#    1/6 Submitting: ACME_01_DFO_Calibration_SOP.pdf
#       ✅ Run ID: abc-123
#    2/6 Submitting: ACME_02_Lithography_Control_Plan.pdf
#       ✅ Run ID: def-456
#    ... etc
```

### Example 2: Dry Run

```bash
# See what would be processed without submitting
./launch-per-document-ingestion.py --scenario acme --dry-run

# Output shows discovered PDFs but doesn't submit runs
```

### Example 3: Higher Concurrency

```bash
# Process with 4 concurrent runs (faster, more resources)
./launch-per-document-ingestion.py --scenario red-hat --max-concurrent 4
```

## Uploading Documents

Before running ingestion, upload documents to MinIO:

```bash
# Single document
./upload-to-minio.sh ~/docs/document.pdf s3://llama-files/scenario2-acme/document.pdf

# Multiple documents (bash loop)
for pdf in ~/docs/acme/*.pdf; do
  filename=$(basename "$pdf")
  ./upload-to-minio.sh "$pdf" "s3://llama-files/scenario2-acme/$filename"
done
```

## Monitoring

### Dashboard

Each run appears as a top-level entry:

```
https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/#/runs
```

Filter by:
- **Experiment**: "RAG Ingestion Experiments"
- **Run name prefix**: "acme-", "red-hat-", "eu-ai-act-"

### CLI Monitoring

```bash
# Watch active runs
oc get pods -n private-ai-demo -w | grep pipeline

# Check specific run logs
oc logs -n private-ai-demo <pod-name> -c main

# Query LlamaStack for ingested documents
curl -s http://llama-stack-service.private-ai-demo.svc:8321/v1/vector-io/query \
  -H "Content-Type: application/json" \
  -d '{
    "vector_db_id": "acme_corporate",
    "query": "calibration procedure",
    "params": {"top_k": 5}
  }'
```

## Validation

After ingestion completes:

### 1. Check Pipeline Dashboard

✅ All runs show "Succeeded"  
✅ No failed tasks  
✅ Each verify-ingestion step passed  

### 2. Query LlamaStack Playground

```
https://llama-stack-playground.private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com
```

1. Select collection (e.g., `acme_corporate`)
2. Enter test query
3. Verify relevant chunks are returned

### 3. Check Milvus Collection

```python
from pymilvus import connections, Collection

connections.connect("default", host="milvus-standalone.private-ai-demo.svc", port="19530")
collection = Collection("acme_corporate")
print(f"Total entities: {collection.num_entities}")
```

## Troubleshooting

### No PDFs Found

```
❌ No PDFs found in s3://llama-files/scenario2-acme/
```

**Solution**: Upload documents to MinIO first
```bash
./upload-to-minio.sh <file.pdf> s3://llama-files/scenario2-acme/<filename>.pdf
```

### Parameter Type Error

```
Error: input parameter chunk_size requires type double or integer
```

**Solution**: The launcher already passes correct types. This error shouldn't occur.  
If it does, check `pipeline.py` parameter type annotations.

### Connection Errors

```
Error connecting to KFP
```

**Solution**: Ensure you're logged into OpenShift
```bash
oc whoami  # Should show your username
oc login --token=<token> --server=<server>
```

### Too Many Concurrent Runs

```
⏳ Waiting for slot (4/2 active)...
```

**Normal**: The launcher is controlling concurrency. Wait for runs to complete.

## Best Practices

### 1. Use Semantic Version Names

The launcher uses the v1.0.0 version by default:

```bash
--pipeline-id 88397afe-c279-46c4-ae03-9ed25ed7a253  # data-processing-and-insertion
--version-id fd3bc949-7dad-45ad-92c7-b349d5ef56a7   # v1.0.0
```

### 2. Organize Documents by Scenario

```
llama-files/
  ├── scenario1-red-hat/
  │   ├── rhoai-rag-guide.pdf
  │   └── ...
  ├── scenario2-acme/
  │   ├── ACME_01_DFO_Calibration_SOP.pdf
  │   └── ...
  └── scenario3-eu-ai-act/
      ├── eu-ai-act-official-journal.pdf
      └── ...
```

### 3. Start with Dry Run

Always test with `--dry-run` first to verify PDF discovery:

```bash
./launch-per-document-ingestion.py --scenario acme --dry-run
```

### 4. Monitor First Run

Watch the first document's run to completion before submitting large batches.

### 5. Clean Up Failed Runs

If runs fail, investigate and clean up before resubmitting:

```bash
# Delete failed runs from UI or CLI
oc delete pods -n private-ai-demo -l pipelines.kubeflow.org/pipelinename=data-processing-and-insertion
```

## Comparison: Per-Document vs Batch

| Aspect | Per-Document (Recommended) | Batch (ParallelFor) |
|--------|----------------------------|---------------------|
| **UI Visibility** | ✅ One run per document | ⚠️ All docs in one run |
| **Failure Isolation** | ✅ Failed doc doesn't affect others | ❌ One failure fails batch |
| **Concurrency Control** | ✅ Launcher controls (2-4) | ⚠️ Fixed in pipeline (2-3) |
| **Dashboard Clutter** | ⚠️ Many top-level runs | ✅ Single run entry |
| **Use Case** | ✅ Production, large sets | ✅ Ad-hoc, small batches |
| **Complexity** | ✅ Simple pipeline, smart launcher | ⚠️ Complex loop in pipeline |
| **Retry Logic** | ✅ Easy to retry individual docs | ❌ Must retry entire batch |

## References

- **KFP User Guides**: https://www.kubeflow.org/docs/components/pipelines/user-guides/
- **Data Handling**: https://www.kubeflow.org/docs/components/pipelines/user-guides/data-handling/
- **Use Caching**: https://www.kubeflow.org/docs/components/pipelines/user-guides/core-functions/#use-caching
- **Control Flow**: https://www.kubeflow.org/docs/components/pipelines/user-guides/core-functions/#control-flow

---

**Last Updated**: 2025-11-07  
**Status**: Production Ready  
**Approach**: Per-Document Submission (Recommended)

