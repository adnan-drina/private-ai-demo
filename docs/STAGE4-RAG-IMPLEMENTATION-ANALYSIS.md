# 🔍 Stage 4: RAG Implementation Analysis & Recommendations

## Your Current Implementation Status

### ✅ What You've Done

#### 1. **Updated KFP Pipeline** 
**File**: `stages/stage2-model-alignment/kfp/batch-docling-rag-pipeline.yaml`

**Key Improvements**:
- ✅ Refactored with modular components
- ✅ Added nested loop structure for better parallelization
- ✅ Optimized server-side embeddings via LlamaStack Vector IO
- ✅ Added `num_splits` parameter for parallel processing control
- ✅ Better error handling and retry logic
- ✅ Batched insertion (100 chunks at a time)
- ✅ Added `cache_buster` parameter for fresh runs

**Pipeline Version**: v1.0.2

#### 2. **New Red Hat Documentation**
Added OpenShift operational runbooks for MCP/agent demo:

| Document | Size | Purpose |
|----------|------|---------|
| `DevOps_with_OpenShift.pdf` | 7.1 MB | DevOps practices and procedures |
| `OpenShift_Container_Platform-4.20-Architecture-en-US.pdf` | 1.2 MB | Architecture reference |

**Removed**: Old `rhoai-rag-guide.pdf`

#### 3. **Pipeline Execution**
- ✅ Compiled fresh pipeline YAML
- ✅ Used OAuth token for KFP client auth
- ✅ Launched run: `data-processing-and-insertion-hqpq7`

---

## 🚨 Current Issues

### Issue #1: Pipeline Stuck (Resource Constraints)

**Status**: Pod `data-processing-and-insertion-hqpq7-system-dag-driver-2454241172` is **Pending**

**Root Cause**: Insufficient cluster resources
```
0/7 nodes are available:
  - 1 node: Insufficient memory
  - 4 nodes: Insufficient CPU  
  - 2 nodes: GPU nodes (untolerated taint)
  - 1 node: Master node (untolerated taint)
```

**Impact**: Pipeline cannot start - dag-driver pod cannot be scheduled

**Solution Options**:

#### Option A: Reduce Resource Requests (Immediate Fix)
The pipeline components request:
- CPU: 250m-1000m per component
- Memory: 256Mi-1Gi per component

With `num_splits=2`, this creates:
- 2 parallel groups
- Each group processes N PDFs sequentially
- Multiple pods running simultaneously

**Recommendation**: Reduce `num_splits` to 1:
```python
# When launching pipeline
run = client.create_run_from_pipeline_package(
    pipeline_file='batch-docling-rag-pipeline.yaml',
    arguments={
        's3_prefix': 's3://llama-files/scenario1-red-hat/',
        'vector_db_id': 'red_hat_docs',
        'num_splits': 1,  # ← Sequential processing
        'cache_buster': 'redhat-ops-runbooks-v1'
    }
)
```

#### Option B: Scale Down Other Workloads
Free up CPU by scaling down non-essential pods:
```bash
# Scale down GuideLLM workbench temporarily
oc scale deployment guidellm-workbench -n private-ai-demo --replicas=0

# Check remaining capacity
oc describe nodes | grep -A 5 "Allocated resources"
```

#### Option C: Add Worker Nodes
Request additional capacity (if possible in sandbox environment)

---

### Issue #2: Large Document Processing Time

**Documents Size**: 7.1 MB + 1.2 MB = **8.3 MB total**

**Estimated Processing Time**:
- Docling conversion: ~15-30 min for 7MB PDF
- Chunking: ~1-2 min
- LlamaStack insertion (batched): ~5-10 min
- **Total per PDF**: 20-40 minutes
- **Total for both**: 40-80 minutes

**Recommendation**: Monitor progress, expect long runtime

---

## 💡 Recommendations & Improvements

### 1. **Immediate Action**: Fix Resource Issue

**Step 1**: Cancel stuck run
```bash
oc delete workflow data-processing-and-insertion-hqpq7 -n private-ai-demo
```

**Step 2**: Free up resources
```bash
# Scale down non-essential services
oc scale deployment guidellm-workbench -n private-ai-demo --replicas=0

# Check available CPU
oc describe nodes | grep -E "cpu.*Allocated" | head -4
```

**Step 3**: Relaunch with `num_splits=1`
```python
run = client.create_run_from_pipeline_package(
    pipeline_file='batch-docling-rag-pipeline.yaml',
    arguments={
        's3_prefix': 's3://llama-files/scenario1-red-hat/',
        'vector_db_id': 'red_hat_docs',
        'chunk_size': 512,
        'num_splits': 1,  # Sequential processing
        'cache_buster': 'redhat-ops-v1',
        's3_secret_mount_path': '/mnt/secrets'
    }
)
```

### 2. **Upload Documents to S3 First**

**Current**: Documents are on local filesystem  
**Issue**: Pipeline expects documents in S3/MinIO

**Action Required**:
```bash
# Upload to MinIO
oc cp stages/stage2-model-alignment/scenario-docs/scenario1-red-hat/DevOps_with_OpenShift.pdf \
  minio-XXX:/var/minio/llama-files/scenario1-red-hat/

# Or use MinIO client
mc cp stages/stage2-model-alignment/scenario-docs/scenario1-red-hat/*.pdf \
  minio/llama-files/scenario1-red-hat/
```

**Verify**:
```bash
# List files
oc exec -it deployment/minio -n model-storage -- \
  ls -lh /var/minio/llama-files/scenario1-red-hat/
```

### 3. **Document Quality for Stage 4 MCP Demo**

**What You've Added**: OpenShift architecture and DevOps docs

**Alignment with Stage 4 Goals**:
- ✅ **Good fit** for `mcp::openshift` demo (pod troubleshooting use case)
- ✅ Operational runbooks support DevOps agent workflow
- ⚠️ **Missing** ACME calibration-specific content

**Recommendations**:

#### For MCP OpenShift Demo (Good as-is)
Current docs support this workflow:
1. Agent gets pod logs via `mcp::openshift`
2. Agent searches these OpenShift docs for solutions
3. Agent sends Slack alert via `mcp::slack`

**Perfect alignment** with the [demo notebook workflow](https://github.com/opendatahub-io/llama-stack-demos/blob/main/demos/rag_agentic/notebooks/Level6_agents_MCP_and_RAG.ipynb)!

#### For ACME Calibration Demo (Need Additional Docs)
For the calibration use case, add:
```
scenario3-acme-calibration/
├── Litho-Print-3000_User_Manual.pdf
├── Calibration_Procedures_Standard.pdf
├── Troubleshooting_Guide_Lithography.pdf
└── Equipment_Specifications.pdf
```

**Suggested**: Create two separate collections:
- `red_hat_docs` ← Your current work (OpenShift ops)
- `acme_calibration_docs` ← For equipment demo

### 4. **Pipeline Configuration Best Practices**

**Current Parameters** (good):
```yaml
s3_prefix: s3://llama-files/scenario1-red-hat/
vector_db_id: red_hat_docs  # Assuming this
chunk_size: 512
num_splits: 2  # ← Change to 1
cache_buster: ''  # ← Good for forcing fresh ingestion
```

**Recommendations**:
- ✅ Use descriptive `vector_db_id`: `red_hat_ops_runbooks` or `openshift_docs`
- ✅ Add `cache_buster` with version: `redhat-ops-v1`
- ✅ Keep `chunk_size: 512` (good for embeddings)

### 5. **Vector DB Collection Management**

**Check existing collections**:
```bash
# From LlamaStack API
curl http://llama-stack-service.private-ai-demo.svc:8321/v1/vector-dbs

# From Milvus directly
oc exec -it deployment/milvus-standalone -n private-ai-demo -- \
  python -c "from pymilvus import connections, utility; \
  connections.connect(host='localhost', port='19530'); \
  print(utility.list_collections())"
```

**Create new collection for Red Hat docs**:
```python
# Via LlamaStack API
import requests

response = requests.post(
    "http://llama-stack-service.private-ai-demo.svc:8321/v1/vector-dbs",
    json={
        "vector_db_id": "red_hat_ops_runbooks",
        "embedding_model": "nomic-embed-text-v1.5",
        "embedding_dimension": 384,
        "provider_id": "milvus"
    }
)
```

**Or use existing collection** if you want to replace content:
- Check if `red_hat_docs` exists and is suitable
- Delete old content if needed (Milvus doesn't support collection-wide delete easily)

### 6. **Monitoring Pipeline Progress**

**Watch workflow status**:
```bash
# Watch workflow progress
watch -n 10 'oc get workflow -n private-ai-demo | head -5'

# Check active pods
oc get pods -n private-ai-demo | grep data-processing

# View logs of active step
oc logs -f -n private-ai-demo -l workflows.argoproj.io/workflow=data-processing-and-insertion-hqpq7
```

**Key stages to watch**:
1. `list-pdfs-in-s3` - Discovers PDFs (should be fast)
2. `download-from-s3` - Downloads each PDF
3. `process-with-docling` - Converts to markdown (SLOWEST - 15-30 min per large PDF)
4. `chunk-markdown` - Chunks text (fast)
5. `insert-via-llamastack` - Batched insertion to Milvus (moderate)

### 7. **Testing After Ingestion**

**Verify data ingestion**:
```bash
# Test RAG search via LlamaStack
curl -X POST http://llama-stack-service.private-ai-demo.svc:8321/v1/vector-io/query \
  -H "Content-Type: application/json" \
  -d '{
    "vector_db_id": "red_hat_ops_runbooks",
    "query": "How do I troubleshoot pod failures?",
    "k": 3
  }'
```

**Test in Playground**:
1. Open RAG page
2. Select `red_hat_ops_runbooks` collection
3. Ask: "How do I debug failing pods in OpenShift?"
4. Verify relevant chunks are retrieved

### 8. **Git Commit Recommendations**

**Current Status**: Changes not committed yet

**Suggested Commit Structure**:

```bash
# Commit 1: Add new Red Hat documentation
git add stages/stage2-model-alignment/scenario-docs/scenario1-red-hat/*.pdf
git commit -m "docs(stage4): Add OpenShift ops runbooks for MCP demo

- DevOps_with_OpenShift.pdf (7.1MB)
- OpenShift_Container_Platform-4.20-Architecture-en-US.pdf (1.2MB)
- Removed outdated rhoai-rag-guide.pdf

These documents support the MCP agent demo workflow:
- Agent queries pod logs (mcp::openshift)
- Agent searches operational docs (builtin::rag)
- Agent sends alerts (mcp::slack)"

# Commit 2: Pipeline updates (if you modified Python source)
git add stages/stage2-model-alignment/kfp/batch-docling-rag-pipeline.yaml
git commit -m "feat(stage2): Update RAG pipeline to v1.0.2

Improvements:
- Add num_splits parameter for parallel control
- Optimize batching for large documents
- Better error handling and retry logic
- Support cache_buster for fresh ingestion

Pipeline now better suited for large operational docs."
```

---

## 📊 Implementation Assessment

### Strengths ✅

1. **Pipeline Design**: Excellent improvements
   - Modular components
   - Good error handling
   - Batched processing
   - Retry logic

2. **Document Selection**: Good alignment with MCP demo
   - OpenShift operational content
   - Supports DevOps troubleshooting use case
   - Real-world documentation

3. **Approach**: Following best practices
   - Using OAuth token for KFP auth
   - Fresh pipeline compilation
   - Explicit parameters

### Areas for Improvement ⚠️

1. **Resource Management**
   - Need to reduce `num_splits` or scale down other services
   - Monitor cluster capacity before large jobs

2. **S3/MinIO Upload**
   - Verify documents are in MinIO before running pipeline
   - Pipeline expects `s3://` URIs

3. **Collection Strategy**
   - Decide on collection naming
   - Document which collection supports which use case
   - Consider separate collections for different demos

4. **Documentation**
   - Add ACME-specific docs later for calibration demo
   - Keep Red Hat docs for OpenShift/DevOps demo

---

## 🎯 Next Steps (Prioritized)

### Immediate (Unblock Pipeline)
1. ✅ **Fix resource issue** - Scale to `num_splits=1`
2. ✅ **Verify S3 upload** - Ensure PDFs are in MinIO
3. ✅ **Relaunch pipeline** - Monitor progress

### Short Term (This Session)
4. ✅ **Monitor ingestion** - Watch for completion (~40-80 min)
5. ✅ **Test RAG retrieval** - Verify documents are searchable
6. ✅ **Commit changes** - Git commit with clear messages

### Medium Term (Stage 4 Continuation)
7. ⏸️ **Create ACME docs** - For calibration demo
8. ⏸️ **Implement MCP servers** - database-mcp, slack-mcp
9. ⏸️ **Extend Playground UI** - Tool selection interface

---

## 🔍 Suggested Commands

### Check Current Status
```bash
# Workflow status
oc get workflow -n private-ai-demo | grep data-processing

# Pod status
oc get pods -n private-ai-demo | grep -E "data-processing|docling"

# Resource availability
oc describe nodes | grep -A 5 "Allocated resources" | head -30
```

### Fix Resource Issue
```bash
# Delete stuck workflow
oc delete workflow data-processing-and-insertion-hqpq7 -n private-ai-demo

# Free up CPU
oc scale deployment guidellm-workbench -n private-ai-demo --replicas=0

# Check Milvus collection
oc exec -it deployment/milvus-standalone -n private-ai-demo -- \
  python -c "from pymilvus import connections, utility; \
  connections.connect(host='localhost', port='19530'); \
  print('Collections:', utility.list_collections())"
```

### Verify S3 Content
```bash
# Check MinIO pod
oc get pods -n model-storage | grep minio

# List S3 content
oc exec -it deployment/minio -n model-storage -- \
  ls -lh /var/minio/llama-files/scenario1-red-hat/
```

---

## Summary

**Your implementation is on the right track!** The pipeline updates are solid, and your document selection aligns well with the MCP OpenShift demo.

**Main blockers**:
1. Resource constraints - easy fix with `num_splits=1`
2. Need to verify S3 upload of PDFs

**Once unblocked**, you'll have a working RAG ingestion for Red Hat operational docs that perfectly supports the `mcp::openshift` + `builtin::rag` + `mcp::slack` agent workflow from the OpenDataHub demo!

---

**Status**: 🟡 **Implementation In Progress - Needs Resource Adjustment**

