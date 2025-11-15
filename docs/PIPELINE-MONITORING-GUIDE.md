# Pipeline Monitoring Guide

Quick reference for monitoring RAG pipeline execution.

---

## Current Pipeline

**Workflow**: `data-processing-and-insertion-kdhrl`  
**Run ID**: `7955f7f5-8858-49ba-ae02-5258b5418215`  
**Namespace**: `private-ai-demo`

---

## Option 1: CLI - Tail Active Logs (Recommended)

**Command**:
```bash
oc logs -f data-processing-and-insertion-kdhrl-retry-system-container-impl-378685746 -n private-ai-demo
```

**What you'll see**:
```
Processing batch 3/119 (100 chunks)...
  [OK] Batch 3: 100 chunks inserted
Processing batch 4/119 (100 chunks)...
  [OK] Batch 4: 100 chunks inserted
...
```

**To stop**: Press `Ctrl+C`

**Find latest running pod**:
```bash
oc get pods -n private-ai-demo | grep data-processing-and-insertion-kdhrl | grep Running
```

---

## Option 2: CLI - Watch Workflow Status

**Command**:
```bash
watch -n 10 'oc get workflow data-processing-and-insertion-kdhrl -n private-ai-demo'
```

**What you'll see**:
```
NAME                                  STATUS    AGE   MESSAGE
data-processing-and-insertion-kdhrl   Running   25m   
```

Updates every 10 seconds.

**One-time check**:
```bash
oc get workflow data-processing-and-insertion-kdhrl -n private-ai-demo
```

---

## Option 3: Web UI - Kubeflow Pipelines Dashboard

**URL**:
```
https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/#/runs/details/7955f7f5-8858-49ba-ae02-5258b5418215
```

**Features**:
- ✅ Visual pipeline graph
- ✅ Real-time step progress
- ✅ Logs for each step
- ✅ Input/output artifacts
- ✅ Parameter values
- ✅ Execution metrics

**Navigation**:
1. Go to KFP Dashboard
2. Click "Runs" in left sidebar
3. Find run: `data-processing-and-insertion`
4. Click on run to see details

---

## Option 4: Web UI - OpenShift Console

**Pod Logs URL**:
```
https://console-openshift-console.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/k8s/ns/private-ai-demo/pods/data-processing-and-insertion-kdhrl-retry-system-container-impl-378685746/logs
```

**Navigation**:
1. OpenShift Console → **Workloads** → **Pods**
2. Set namespace: `private-ai-demo`
3. Search: `data-processing-and-insertion-kdhrl`
4. Filter: **Running** status
5. Click pod name → **Logs** tab
6. Enable "Follow" to auto-scroll

---

## Option 5: Check Component-Specific Logs

### List All Pipeline Pods
```bash
oc get pods -n private-ai-demo | grep data-processing-and-insertion-kdhrl
```

### Component Logs

**List PDFs Step**:
```bash
oc logs data-processing-and-insertion-kdhrl-<pod-id> -n private-ai-demo | grep -A 10 "list-pdfs"
```

**Download Step**:
```bash
oc logs data-processing-and-insertion-kdhrl-<pod-id> -n private-ai-demo | grep -A 10 "download"
```

**Docling Processing Step**:
```bash
oc logs data-processing-and-insertion-kdhrl-<pod-id> -n private-ai-demo | grep -A 10 "Docling"
```

**Insert Step** (current):
```bash
oc logs -f data-processing-and-insertion-kdhrl-retry-system-container-impl-378685746 -n private-ai-demo
```

---

## What to Look For

### ✅ Success Indicators

**List PDFs**:
```
[OK] Found 2 PDF files:
  - DevOps_with_OpenShift.pdf
  - OpenShift_Container_Platform-4.20-Architecture-en-US.pdf
```

**Download**:
```
[OK] Downloaded: 7456789 bytes to /path/to/file.pdf
```

**Docling**:
```
[OK] Task completed with status: success
[OK] Extracted 245678 characters of markdown
```

**Chunking**:
```
Created 11866 chunks (max length: 512 chars, limit: 60000)
[OK] Created 11866 chunks (embeddings will be computed by LlamaStack)
```

**Insertion**:
```
Processing batch 3/119 (100 chunks)...
  [OK] Batch 3: 100 chunks inserted
...
[OK] Successfully inserted 11866/11866 chunks across 119 batches
```

### ❌ Error Indicators

**404 Not Found**:
```
botocore.exceptions.ClientError: An error occurred (404)
```
→ File missing from MinIO

**Pydantic Validation Error**:
```
{'loc': ['stored_chunk_id'], 'msg': 'Input should be a valid string'}
```
→ Milvus `auto_id` configuration issue

**OOMKilled**:
```
Exit code: 137
```
→ Docling ran out of memory (should not happen with 16Gi)

**Connection Refused**:
```
ConnectionRefusedError: [Errno 111] Connection refused
```
→ LlamaStack or Docling service down

**Timeout**:
```
Timeout on batch X, retry Y/5 after Zs...
```
→ Expected for large batches, will retry automatically

---

## Pipeline Progress Stages

| Stage | Duration | What's Happening |
|-------|----------|------------------|
| 1. List PDFs | ~1 min | Discover files in MinIO |
| 2. Download | ~2 min | Download PDFs from MinIO |
| 3. Docling | ~15-30 min | Convert PDF → Markdown (CPU intensive) |
| 4. Chunk | ~2 min | Split markdown into chunks |
| 5. Insert | **~20-40 min** | Insert chunks + compute embeddings (CURRENT) |

**Total**: 40-60 minutes

---

## Current Status Commands

### Quick Status Check
```bash
# Workflow phase
oc get workflow data-processing-and-insertion-kdhrl -n private-ai-demo -o jsonpath='{.status.phase}'

# Progress
oc get workflow data-processing-and-insertion-kdhrl -n private-ai-demo -o jsonpath='{.status.progress}'

# Combined
oc get workflow data-processing-and-insertion-kdhrl -n private-ai-demo
```

### Check for Errors
```bash
# Find error pods
oc get pods -n private-ai-demo | grep data-processing-and-insertion-kdhrl | grep -E "Error|Failed"

# Check last error
ERROR_POD=$(oc get pods -n private-ai-demo | grep data-processing-and-insertion-kdhrl | grep Error | tail -1 | awk '{print $1}')
oc logs $ERROR_POD -n private-ai-demo --tail=50
```

### Monitor Infrastructure

**Docling**:
```bash
oc get pods -n private-ai-demo -l app=docling
oc top pod -n private-ai-demo -l app=docling
```

**LlamaStack**:
```bash
oc get pods -n private-ai-demo -l app=llama-stack
oc logs -f deployment/llama-stack -n private-ai-demo --tail=20
```

**Milvus**:
```bash
oc get pods -n private-ai-demo | grep milvus
```

---

## After Pipeline Completion

### Verify Success
```bash
# Check workflow completed
oc get workflow data-processing-and-insertion-kdhrl -n private-ai-demo

# Expected output:
# STATUS: Succeeded
```

### Test RAG Retrieval
```bash
# Query vector store
oc exec deployment/llama-stack -n private-ai-demo -- \
  curl -s -X POST http://localhost:8321/v1/vector_stores/red_hat_docs/query \
  -H "Content-Type: application/json" \
  -d '{"query": "OpenShift", "limit": 3}' | python3 -m json.tool
```

### Access Playground
```
https://llama-stack-playground-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/rag
```

---

## Troubleshooting

### Pipeline Stuck
```bash
# Check if pod is running
oc get pods -n private-ai-demo | grep data-processing-and-insertion-kdhrl | grep Running

# Check pod events
oc describe pod <pod-name> -n private-ai-demo | tail -20

# Check resource usage
oc top pod <pod-name> -n private-ai-demo
```

### Logs Not Showing
```bash
# Check pod status
oc get pod <pod-name> -n private-ai-demo

# Check container status
oc get pod <pod-name> -n private-ai-demo -o jsonpath='{.status.containerStatuses[*].state}'

# Try previous container logs (if restarted)
oc logs <pod-name> -n private-ai-demo --previous
```

### Pipeline Failed
```bash
# Get failure reason
oc get workflow data-processing-and-insertion-kdhrl -n private-ai-demo -o json | \
  jq -r '.status.nodes | to_entries[] | select(.value.phase == "Failed") | .value.message'

# Check all error pods
oc get pods -n private-ai-demo | grep data-processing-and-insertion-kdhrl | grep Error
```

---

## Related Documentation

- [Pipeline Failure Analysis](./STAGE4-RAG-PIPELINE-FAILURE-ANALYSIS.md)
- [Next Steps After RAG](./STAGE4-NEXT-STEPS-AFTER-RAG.md)
- [Milvus Fix Summary](./STAGE4-RAG-MILVUS-FIX-SUMMARY.md)

---

**Last Updated**: 2025-11-16 00:16 UTC  
**Pipeline**: `data-processing-and-insertion-kdhrl`  
**Status**: Running (batch 3/119)

