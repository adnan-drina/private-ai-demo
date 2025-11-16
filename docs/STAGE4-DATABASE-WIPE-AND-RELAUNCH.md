# Stage 4: Database Wipe and Pipeline Relaunch

**Date**: November 16, 2025 01:00 UTC  
**Action**: Clean slate RAG ingestion with wiped Milvus database

---

## What Was Done

### 1. Stopped Running Pipeline ✅

**Old Pipeline**: `data-processing-and-insertion-kdhrl`
- Status: Running (batch 3/119)
- Progress: 16/17 tasks
- Age: 20 minutes

**Action**:
```bash
oc delete workflow data-processing-and-insertion-kdhrl -n private-ai-demo
```

**Result**: Pipeline canceled successfully

---

### 2. Wiped Milvus Database ✅

**Target Collection**: `red_hat_docs`

**Action**:
```bash
oc exec deployment/llama-stack -n private-ai-demo -- \
  curl -s -X DELETE http://localhost:8321/v1/vector_stores/red_hat_docs
```

**Response**:
```json
{
  "id": "red_hat_docs",
  "object": "vector_store.deleted",
  "deleted": true
}
```

**Result**: Collection successfully dropped, database clean

---

### 3. Launched Fresh Pipeline ✅

**New Pipeline**: `data-processing-and-insertion-lbgmm`  
**Run ID**: `55357e95-7b14-4cb8-b5f2-f669403832b9`

**Configuration**:
```yaml
s3_prefix: s3://llama-files/scenario1-red-hat/
vector_db_id: red_hat_docs
cache_buster: clean-db-v1  # Fresh start indicator
num_splits: 1              # Sequential processing
chunk_size: 512
llamastack_url: http://llama-stack-service.private-ai-demo.svc:8321
docling_url: http://docling-service.private-ai-demo.svc:5001
minio_endpoint: minio.model-storage.svc:9000
minio_creds_b64: <encoded>  # Credentials included
s3_secret_mount_path: /mnt/secrets
```

**PDFs Being Processed**:
1. `DevOps_with_OpenShift.pdf` (7.1 MB)
2. `OpenShift_Container_Platform-4.20-Architecture-en-US.pdf` (1.2 MB)

**Total**: 8.3 MB

---

## Pipeline Health Check (First 2 Minutes)

| Time | Status | Progress | Note |
|------|--------|----------|------|
| 01:01 | Running | 5/6 | Started |
| 01:02 | Running | 10/11 | Progressing well |

**Assessment**: ✅ **Healthy and progressing normally**

---

## Infrastructure State

| Component | Status | Configuration |
|-----------|--------|---------------|
| Milvus Database | ✅ Clean | Wiped, no existing chunks |
| Milvus Schema | ✅ Ready | `auto_id=false`, string IDs enabled |
| Docling | ✅ Ready | 16Gi memory (no OOM expected) |
| LlamaStack | ✅ Ready | Vector-io API active |
| MinIO | ✅ Connected | Credentials working |

---

## Why Wipe the Database?

**Reasons for clean slate**:
1. **Previous partial data**: Earlier failed pipelines left partial chunks
2. **Schema validation**: Ensure Milvus `auto_id=false` fix applies cleanly
3. **Clean testing**: Validate end-to-end ingestion without legacy data
4. **Chunk ID consistency**: Ensure all chunks have properly formatted string IDs

**Benefits**:
- ✅ No orphaned chunks from failed runs
- ✅ Clean schema with correct field types
- ✅ Consistent chunk naming (e.g., `DevOps_chunk_0`)
- ✅ Known starting state for validation

---

## Expected Outcome

**When Pipeline Completes** (~38-58 minutes from 01:01 UTC):

### Metrics
- **Total Chunks**: ~11,000-12,000 (based on previous run)
- **Collection**: `red_hat_docs`
- **Chunk ID Format**: String (e.g., `"DevOps_chunk_0"`, `"Architecture_chunk_123"`)
- **Embeddings**: 768-dimensional (IBM Granite)
- **Vector DB**: Milvus HNSW index

### Validation Steps
1. Query vector store to confirm chunks exist
2. Verify `stored_chunk_id` are strings (not integers)
3. Check no Pydantic warnings in logs
4. Test RAG retrieval in playground
5. Validate response quality

---

## Monitoring

### CLI - Tail Current Step
```bash
oc logs -f data-processing-and-insertion-lbgmm-system-container-impl-2584126969 -n private-ai-demo
```

### CLI - Watch Progress
```bash
watch -n 10 'oc get workflow data-processing-and-insertion-lbgmm -n private-ai-demo'
```

### Web UI - KFP Dashboard
```
https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/#/runs/details/55357e95-7b14-4cb8-b5f2-f669403832b9
```

### Web UI - OpenShift Console
```
https://console-openshift-console.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/k8s/ns/private-ai-demo/workflows.argoproj.io~v1alpha1~Workflow/data-processing-and-insertion-lbgmm
```

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 00:14 | User requested database wipe |
| 00:14 | Canceled old pipeline (`kdhrl`) |
| 00:14 | Dropped `red_hat_docs` collection |
| 00:14 | Verified clean database |
| 01:00 | Launched fresh pipeline (`lbgmm`) |
| 01:02 | Health check: 10/11 tasks ✅ |
| ~01:40 | **Expected completion** |

**Total Expected Duration**: ~40-60 minutes

---

## Key Changes from Previous Run

| Aspect | Previous Run | New Run |
|--------|-------------|---------|
| Database State | Partial chunks from failed runs | ✅ **Clean slate** |
| Pipeline ID | `kdhrl` (canceled at batch 3/119) | `lbgmm` (fresh start) |
| Cache Buster | `fixed-v3-with-creds` | `clean-db-v1` |
| Starting Progress | 0% | 0% |
| Collection | Had ~300 chunks | **Empty** |

---

## Success Criteria

**Pipeline**:
- [x] ✅ Launches successfully
- [x] ✅ Discovers 2 PDFs in MinIO
- [ ] ⏳ Processes both PDFs with Docling (16Gi memory)
- [ ] ⏳ Creates ~11,000-12,000 chunks
- [ ] ⏳ Inserts all chunks via LlamaStack
- [ ] ⏳ Completes without OOM or 404 errors

**Database**:
- [x] ✅ Collection wiped before start
- [x] ✅ Clean schema with string ID support
- [ ] ⏳ All chunks have string `stored_chunk_id`
- [ ] ⏳ No Pydantic warnings
- [ ] ⏳ Embeddings computed server-side
- [ ] ⏳ HNSW index created

**Validation** (Post-Completion):
- [ ] Query returns chunks with string IDs
- [ ] RAG retrieval works in playground
- [ ] No 400/500 errors
- [ ] Response quality is good

---

## Related Documents

- [Pipeline Failure Analysis](./STAGE4-RAG-PIPELINE-FAILURE-ANALYSIS.md)
- [Pipeline Monitoring Guide](./PIPELINE-MONITORING-GUIDE.md)
- [Milvus Fix Summary](./STAGE4-RAG-MILVUS-FIX-SUMMARY.md)
- [Next Steps After RAG](./STAGE4-NEXT-STEPS-AFTER-RAG.md)

---

## Status

**Current**: ⏳ Pipeline running (10/11 tasks after 2 minutes)  
**Health**: ✅ Progressing normally  
**Next Action**: Wait for completion, then validate

---

**Summary**: Successfully wiped Milvus `red_hat_docs` collection and launched fresh RAG ingestion pipeline. Database is clean, schema is correct, and pipeline is progressing healthily. Expected completion in ~38-58 minutes from 01:01 UTC.

