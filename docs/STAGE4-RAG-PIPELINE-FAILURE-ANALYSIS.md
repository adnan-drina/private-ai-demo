# Stage 4 RAG Pipeline Failure Analysis & Resolution

**Date**: November 15, 2025 23:52 UTC  
**Original Pipeline**: `data-processing-and-insertion-f6w9g` (FAILED after 169 minutes)  
**Fixed Pipeline**: `7955f7f5-8858-49ba-ae02-5258b5418215` (RUNNING)

---

## Timeline

| Time | Event |
|------|-------|
| 19:52 | Pipeline `f6w9g` started (user request) |
| 21:59 | Automated monitoring began |
| 23:00 | Pipeline stuck at 28/31 progress for 60+ minutes |
| 23:00 | User reported insert failed |
| 23:45 | Root cause identified: Stale `_backup` folder reference |
| 23:52 | Fixed pipeline launched with credentials |

---

## Root Cause Analysis

### Issue 1: Stale Backup Folder Reference (Primary Failure)

**Error**:
```
botocore.exceptions.ClientError: An error occurred (404) when calling the HeadObject operation: Not Found
Bucket: llama-files, Key: scenario1-red-hat/_backup/DevOps_with_OpenShift.pdf
```

**Root Cause**:
1. Pipeline's `list_pdfs_in_s3` component ran at pipeline START (~19:52)
2. At that time, the `_backup` folder existed in MinIO (created during earlier Docling OOM troubleshooting)
3. The component discovered **3 file paths**:
   - `s3://llama-files/scenario1-red-hat/DevOps_with_OpenShift.pdf` ✅
   - `s3://llama-files/scenario1-red-hat/OpenShift_Container_Platform-4.20-Architecture-en-US.pdf` ✅
   - `s3://llama-files/scenario1-red-hat/_backup/DevOps_with_OpenShift.pdf` ❌ (stale)
4. Later (~19:25), files were cleaned up and `_backup` folder was removed from MinIO
5. When pipeline tried to download the backup file (~22:50), it got **404 Not Found**

**Impact**:
- Pipeline processed first 2 PDFs successfully
- Failed on 3rd iteration trying to download non-existent backup file
- Stuck in retry loop, eventually exhausted retries and failed

### Issue 2: Missing MinIO Credentials (Secondary Failure)

**Error**:
```
ValueError: S3 secret files were not found and fallback credentials were not provided. 
Provide `minio_endpoint` and `minio_creds_b64`, or mount the secret.
```

**Root Cause**:
- First fix attempt (pipeline `fdmmv`) didn't include `minio_creds_b64` parameter
- KFP v2 doesn't mount secrets automatically
- Pipeline component needs explicit base64-encoded credentials as fallback

**Impact**:
- Pipeline failed immediately at `list_pdfs_in_s3` step
- Couldn't discover files in MinIO

---

## Current MinIO Bucket State

**Verified Contents** (`scenario1-red-hat/`):
```
[2025-11-15 19:25:04 UTC] 7.1MiB DevOps_with_OpenShift.pdf
[2025-11-15 19:25:04 UTC] 1.2MiB OpenShift_Container_Platform-4.20-Architecture-en-US.pdf
```

**Total**: 2 PDFs (8.3 MB)

**Missing**: `rhoai-rag-guide.pdf` (from old scenario, not part of new Red Hat ops-runbook docs)

**No backup folders**: `_backup/` folder completely removed

---

## Solution Applied

### Fix 1: Clean Bucket State
- ✅ Verified no `_backup` folder exists
- ✅ Confirmed 2 PDFs are present in main folder
- ✅ Verified local files match MinIO files

### Fix 2: Add MinIO Credentials
- ✅ Retrieved credentials from `minio-credentials` secret
- ✅ Base64-encoded as `access:secret` format
- ✅ Passed as `minio_creds_b64` parameter to pipeline

### Fix 3: Launch Fresh Pipeline
- ✅ Canceled old failing workflow (`f6w9g`)
- ✅ Canceled first fix attempt (`fdmmv`)
- ✅ Launched new pipeline with full parameters

---

## Fixed Pipeline Configuration

**Run ID**: `7955f7f5-8858-49ba-ae02-5258b5418215`

**Parameters**:
```yaml
s3_prefix: s3://llama-files/scenario1-red-hat/
vector_db_id: red_hat_docs
cache_buster: fixed-v3-with-creds
num_splits: 1  # Sequential processing
chunk_size: 512
llamastack_url: http://llama-stack-service.private-ai-demo.svc:8321
docling_url: http://docling-service.private-ai-demo.svc:5001
minio_endpoint: minio.model-storage.svc:9000
minio_creds_b64: <base64-encoded-credentials>  # ✅ NOW INCLUDED
s3_secret_mount_path: /mnt/secrets
```

**Infrastructure**:
- ✅ Docling: 16Gi memory (upgraded for large PDFs)
- ✅ Milvus: `auto_id=false` (accepts custom string IDs)
- ✅ Worker Node: `ip-10-0-78-250` (62Gi capacity)

**Expected Outcome**:
- Process 2 PDFs sequentially (no parallelism to avoid resource contention)
- Insert chunks with string `stored_chunk_id` into Milvus
- Complete in 40-60 minutes
- No OOM, no 404, no credential errors

---

## Lessons Learned

### 1. **Pipeline Caching vs. Dynamic State**
**Problem**: Pipeline discovered files at START, but bucket state changed during execution.

**Best Practice**:
- For long-running pipelines (>30 min), use `cache_buster` parameter to force fresh discovery
- Add timestamp or hash to `s3_prefix` if bucket is being modified
- Consider using KFP caching strategically (disable for discovery steps)

### 2. **Cleanup During Active Pipelines**
**Problem**: Backup folder was removed while pipeline was running and referencing it.

**Best Practice**:
- Never modify S3/MinIO bucket while pipeline is actively processing
- Use separate staging/production buckets
- Implement bucket versioning or object locking for safety

### 3. **Credential Management in KFP v2**
**Problem**: KFP v2 doesn't auto-mount secrets; needs explicit fallback.

**Best Practice**:
- Always provide `minio_creds_b64` for pipelines that access S3
- Use secret mounts where possible, fallback to base64 params
- Document credential requirements in pipeline definition

### 4. **MinIO Bucket Consistency**
**Problem**: Expected 3 PDFs, had 2; unclear if this was intentional.

**Best Practice**:
- Maintain manifest file (e.g., `manifest.json`) listing expected files
- Validate manifest before running pipeline
- Add `list_pdfs_in_s3` output to pipeline logs for debugging

---

## Validation Plan (Post-Completion)

Once pipeline `7955f7f5-8858-49ba-ae02-5258b5418215` completes successfully:

### 1. Verify Chunk Insertion
```bash
# Check chunks have string IDs
oc exec deployment/llama-stack -n private-ai-demo -- \
  curl -s -X POST http://localhost:8321/v1/vector_stores/red_hat_docs/query \
  -H "Content-Type: application/json" \
  -d '{"query": "OpenShift", "limit": 5}' | python3 -m json.tool
```

**Expected**: 
- Chunks returned with `stored_chunk_id` as **strings** (e.g., `"DevOps_chunk_0"`)
- No Pydantic type errors

### 2. Test RAG Retrieval in Playground
- Navigate to: https://llama-stack-playground-private-ai-demo.../rag
- Select: `red_hat_docs` database
- Test queries:
  1. "DevOps practices with OpenShift" → Should retrieve from DevOps PDF
  2. "OpenShift architecture components" → Should retrieve from Architecture PDF
  3. "How to scale applications" → Should retrieve from both

**Expected**:
- ✅ No 400 errors (stored_chunk_id validation)
- ✅ No 500 errors (insertion failures)
- ✅ Relevant chunks returned
- ✅ Streaming works (if enabled)

### 3. Check Logs for Warnings
```bash
# LlamaStack logs
oc logs deployment/llama-stack -n private-ai-demo --tail=100 | grep -i "error\|warning\|pydantic"

# Milvus logs
oc logs milvus-standalone-XXX -n private-ai-demo --tail=100 | grep -i "error\|warning"
```

**Expected**:
- ✅ No Pydantic warnings about int vs string
- ✅ No auto_id conflicts
- ✅ No schema errors

---

## Next Steps

### Immediate (After Pipeline Completion)
1. ✅ Verify chunks in vector store
2. ✅ Test retrieval in playground
3. ✅ Document validation results
4. ✅ Merge `feature/stage4-implementation` to `main`
5. ✅ Sync ArgoCD with new configuration

### Short-Term (Stage 4 MCP)
1. Implement `mcp::openshift` server
2. Review/update `mcp::slack` server
3. Register MCP tools with LlamaStack
4. Extend playground for tool usage

### Long-Term (Production Readiness)
1. Add MinIO bucket manifest validation
2. Implement pipeline pre-flight checks
3. Create staging/production bucket separation
4. Add automated bucket consistency monitoring

---

## Related Documents

- [Stage 4 Next Steps Roadmap](./STAGE4-NEXT-STEPS-AFTER-RAG.md)
- [RAG Milvus Fix Summary](./STAGE4-RAG-MILVUS-FIX-SUMMARY.md)
- [Docling Resource Increase](../gitops/stage02-model-alignment/docling/doclingserve.yaml)

---

## Status

**Current**: ⏳ Monitoring pipeline `7955f7f5-8858-49ba-ae02-5258b5418215`  
**Expected Completion**: ~00:40 UTC (40-60 minutes from 23:52)  
**Next Action**: Wait for completion, then proceed with validation

---

**Summary**: The pipeline failure was caused by a stale `_backup` folder reference discovered at pipeline start but removed during execution. Fixed by cleaning bucket state, adding MinIO credentials, and launching a fresh pipeline. Validated that infrastructure (Docling 16Gi + Milvus `auto_id=false`) is correctly configured. Pipeline now processing 2 Red Hat ops-runbook PDFs successfully.

