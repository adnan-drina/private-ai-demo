# ✅ RAG Ingestion: New Red Hat Documents Processing

**Date**: November 15, 2025  
**Status**: ✅ **IN PROGRESS - ALL 3 PDFs DISCOVERED**  
**Run ID**: `3dd4fa7a-d63b-4221-8b34-28c3389235ec`  
**Workflow**: `data-processing-and-insertion-6lztk`

---

## 🎉 Success: Files Uploaded & Pipeline Running

### ✅ Confirmed: All 3 PDFs Discovered

From the workflow logs, the pipeline successfully discovered and is processing:

1. ✅ **DevOps_with_OpenShift.pdf** (7.1 MB) - NEW Red Hat DevOps guide
2. ✅ **OpenShift_Container_Platform-4.20-Architecture-en-US.pdf** (1.2 MB) - NEW Architecture reference
3. ✅ **rhoai-rag-guide.pdf** (0.2 MB) - Existing RAG guide

**Log Evidence**:
```json
"pdf_uris":[
  "s3://llama-files/scenario1-red-hat/DevOps_with_OpenShift.pdf",
  "s3://llama-files/scenario1-red-hat/OpenShift_Container_Platform-4.20-Architecture-en-US.pdf",
  "s3://llama-files/scenario1-red-hat/rhoai-rag-guide.pdf"
]
```

---

## 📊 Current Status

### Pipeline Progress
- **Workflow**: `data-processing-and-insertion-6lztk`
- **Status**: Running
- **Progress**: 6/7 tasks completed
- **Age**: ~2 minutes
- **Current Phase**: Processing PDFs with Docling

### Completed Tasks
- ✅ `list-pdfs-in-s3` - Discovery complete (found 3 PDFs)
- ✅ `split-pdf-list` - Split into 1 group (sequential)
- ✅ Root driver tasks
- ⏳ `download-from-s3` - In progress
- ⏳ `process-with-docling` - In progress
- ⏳ `chunk-markdown` - Pending
- ⏳ `insert-via-llamastack` - Pending

---

## 📁 File Upload Process

### Method Used: Helper Pod with boto3

**Steps Completed**:
1. ✅ Created Python helper pod with boto3
2. ✅ Copied local PDFs to pod
3. ✅ Uploaded to MinIO via boto3 S3 client
4. ✅ Verified uploads in MinIO
5. ✅ Cleaned up helper pod
6. ✅ Launched fixed pipeline

**MinIO Location**: `s3://llama-files/scenario1-red-hat/`

**Files in MinIO**:
```
scenario1-red-hat/
├── DevOps_with_OpenShift.pdf (7.1 MB)
├── OpenShift_Container_Platform-4.20-Architecture-en-US.pdf (1.2 MB)
└── rhoai-rag-guide.pdf (0.2 MB)
```

---

## ⏱️ Expected Timeline

### Phase 1: Discovery (Complete) ✅
- **Duration**: 1-2 minutes
- **Status**: Complete
- **Result**: 3 PDFs discovered

### Phase 2: Download (In Progress) ⏳
- **Duration**: ~1-2 minutes per PDF
- **Status**: Running
- **Current**: Downloading from MinIO

### Phase 3: Docling Processing (Next) 🔄
- **Duration**: 15-30 minutes per large PDF
- **Bottleneck**: This is the slowest phase
- **DevOps PDF**: ~20-30 minutes (7.1 MB)
- **Architecture PDF**: ~10-15 minutes (1.2 MB)
- **RAG Guide**: ~3-5 minutes (0.2 MB)
- **Total Docling time**: ~30-50 minutes

### Phase 4: Chunking (Pending) ⏳
- **Duration**: ~1-2 minutes per document
- **Fast**: Simple text processing

### Phase 5: Insertion with FIX (Pending) ⏳
- **Duration**: ~5-10 minutes total
- **Method**: Batched (100 chunks/batch)
- **Critical**: WITH `stored_chunk_id` fix ✅
- **Expected chunks**: ~1000-2000 total from all 3 PDFs

### Total Expected Duration
**40-80 minutes** from start to completion

---

## 🔧 Fix Applied

### stored_chunk_id Field Added ✅

**What Was Fixed**:
- Previously: Chunks inserted without `stored_chunk_id` → Retrieval failed with 400 error
- Now: Each chunk gets unique string ID → Retrieval will work

**Chunk ID Format**:
```python
chunk_id_str = f"{source_name}_chunk_{i}"

Examples:
- "DevOps_with_OpenShift_chunk_0"
- "DevOps_with_OpenShift_chunk_1"
- "OpenShift_Container_Platform-4.20-Architecture-en-US_chunk_0"
- "rhoai-rag-guide_chunk_0"
```

**Expected Output**:
- Each chunk will have a unique, human-readable string ID
- LlamaStack Pydantic validation will pass
- RAG retrieval will work without errors

---

## 🔍 Monitoring

### Dashboard
```
https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/#/runs/details/3dd4fa7a-d63b-4221-8b34-28c3389235ec
```

### Command Line
```bash
# Watch progress
watch -n 10 'oc get workflow data-processing-and-insertion-6lztk -n private-ai-demo'

# Detailed status
oc get workflow data-processing-and-insertion-6lztk -n private-ai-demo -o json | \
  jq '{status: .status.phase, progress: .status.progress}'

# View logs
oc logs -f -l workflows.argoproj.io/workflow=data-processing-and-insertion-6lztk -n private-ai-demo
```

### Progress Indicators

**What to Watch For**:
1. **Download phase**: Fast (~2 min)
2. **Docling phase**: Slow (~30-50 min) - this is normal!
3. **Chunking phase**: Fast (~3 min)
4. **Insertion phase**: Moderate (~10 min)

**Signs of Success**:
- No pod failures
- Progress counter incrementing
- Workflow status: "Running"
- Eventually: "Succeeded"

**Signs of Issues**:
- Workflow status: "Failed"
- Repeated pod restarts
- Error messages in logs

---

## ✅ After Completion Testing

### 1. Verify Collection
```bash
# Check collection exists
curl -s http://llama-stack-service.private-ai-demo.svc:8321/v1/vector-dbs | \
  jq '.vector_dbs[] | select(.identifier=="red_hat_docs")'
```

### 2. Test Retrieval (Playground)
```
URL: https://llama-stack-playground-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/rag

Steps:
1. Select collection: red_hat_docs
2. Test queries:
   - "How do I troubleshoot pod failures in OpenShift?"
   - "What is the OpenShift architecture?"
   - "Explain DevOps practices for OpenShift"
3. Expected: ✅ Chunks returned (no 400 error!)
```

### 3. Test Retrieval (API)
```bash
curl -X POST http://llama-stack-service.private-ai-demo.svc:8321/v1/vector-io/query \
  -H "Content-Type: application/json" \
  -d '{
    "vector_db_id": "red_hat_docs",
    "query": "How do I debug failing pods in OpenShift?",
    "k": 5
  }' | jq '.chunks[] | {
    stored_chunk_id,
    document: .metadata.document_id,
    preview: (.content | .[0:150])
  }'
```

**Expected Output**:
```json
{
  "stored_chunk_id": "DevOps_with_OpenShift_chunk_42",
  "document": "DevOps_with_OpenShift",
  "preview": "To troubleshoot pod failures in OpenShift, first check the pod status..."
}
```

### 4. Verify Chunk IDs Are Strings
```bash
curl -s -X POST http://llama-stack-service.private-ai-demo.svc:8321/v1/vector-io/query \
  -H "Content-Type: application/json" \
  -d '{"vector_db_id": "red_hat_docs", "query": "test", "k": 1"}' | \
  jq '.chunks[0].stored_chunk_id'

# Should output: "DevOps_with_OpenShift_chunk_0" (string with quotes)
# NOT: 307 (integer without quotes)
```

---

## 📊 Expected Results

### Collection Contents

After successful ingestion, `red_hat_docs` collection will contain:

| Document | Size | Estimated Chunks | Topics |
|----------|------|------------------|--------|
| DevOps_with_OpenShift.pdf | 7.1 MB | ~800-1200 | DevOps practices, CI/CD, automation |
| OpenShift_Container_Platform-4.20-Architecture-en-US.pdf | 1.2 MB | ~200-400 | Architecture, components, design |
| rhoai-rag-guide.pdf | 0.2 MB | ~50-100 | RAG implementation, best practices |
| **Total** | **8.5 MB** | **~1050-1700** | **OpenShift operations & architecture** |

### Use Case Alignment

These documents **perfectly support** the Stage 4 MCP agent demo:

**Scenario**: OpenShift DevOps Troubleshooting Agent
```
1. Agent queries pod logs (mcp::openshift)
2. Agent searches these operational docs (builtin::rag)
3. Agent sends alert (mcp::slack)
```

**Example Flow**:
```
User: "My pod is failing to start, can you help?"

Agent:
1. Calls mcp::openshift → Gets pod logs
2. Calls builtin::rag → Searches "DevOps_with_OpenShift.pdf"
3. Finds troubleshooting steps
4. Calls mcp::slack → Sends alert to team
5. Returns solution to user
```

---

## 🔄 What's Different From Previous Run

### Previous Run (data-processing-and-insertion-7c4mw)
- ❌ Processed: Only `rhoai-rag-guide.pdf`
- ❌ Reason: New PDFs not uploaded to MinIO
- ✅ Validated: `stored_chunk_id` fix works

### Current Run (data-processing-and-insertion-6lztk)
- ✅ Processing: All 3 PDFs (DevOps, Architecture, RAG Guide)
- ✅ Reason: Files uploaded to MinIO successfully
- ✅ Fix Applied: `stored_chunk_id` field included
- ✅ Expected: Full ingestion of Red Hat operational docs

---

## 📝 Implementation Notes

### Upload Method: Helper Pod + boto3

**Why This Approach**:
- ✅ Works around `oc cp` tar limitation in MinIO pod
- ✅ Uses native S3 API (boto3)
- ✅ Reliable and verifiable
- ✅ Scriptable for automation

**Process**:
```python
1. Create pod with python-311 image
2. Install boto3
3. Copy local PDFs to pod
4. Upload via boto3 S3 client to MinIO
5. Verify uploads
6. Clean up pod
```

**Reusable Pattern**:
This approach can be used for future uploads without MinIO web UI access.

---

## 🎯 Next Steps

### Immediate (Wait for Completion)
1. ⏳ Monitor pipeline (40-80 minutes)
2. ⏳ Watch for "Succeeded" status
3. ✅ Test retrieval in playground
4. ✅ Verify chunk IDs are strings

### After Success
5. ⏸️ Commit file upload automation
6. ⏸️ Document upload procedure
7. ⏸️ Continue with Stage 4 MCP implementation

### If Issues Occur
- Check logs for specific errors
- Verify MinIO connectivity
- Check resource constraints
- Review Docling timeout settings

---

## 📚 Documentation References

- **Fix Analysis**: `docs/STAGE4-RAG-RETRIEVAL-FIX.md`
- **Previous Success**: `docs/STAGE4-RAG-INGESTION-SUCCESS.md`
- **Fix Applied**: `docs/STAGE4-RAG-FIX-APPLIED.md`
- **Implementation**: `docs/STAGE4-RAG-IMPLEMENTATION-ANALYSIS.md`

---

## ✨ Summary

**Status**: ✅ **All 3 PDFs discovered and processing**

**Files**:
- ✅ DevOps_with_OpenShift.pdf (7.1 MB)
- ✅ OpenShift_Container_Platform-4.20-Architecture-en-US.pdf (1.2 MB)
- ✅ rhoai-rag-guide.pdf (0.2 MB)

**Fix**: ✅ `stored_chunk_id` field applied

**Expected**: 40-80 minutes to completion

**Result**: Working RAG retrieval for OpenShift operational knowledge

---

**Document Status**: ✅ Upload Complete, Pipeline Running  
**Branch**: `feature/stage4-implementation`  
**Last Update**: November 15, 2025 17:32 UTC

