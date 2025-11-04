# LlamaStack Stage 2 Deployment - Current Status

## Summary
✅ MinIO bootstrap successful (llama-files bucket created)  
✅ Secrets configured (llama-files-credentials)  
✅ Service port aligned (8321)  
✅ Config path explicit (LLAMA_STACK_CONFIG)  
❌ LlamaStack pod failing due to rh-dev distribution limitations  

## Issues Discovered

### 1. Files API Not Available
- **Tried:** `remote::s3-files` provider → ValueError: Provider not available
- **Tried:** `inline::files` provider → ValueError: Provider not available  
- **Result:** Files API disabled completely

### 2. RAG Runtime Depends on Files API
- `inline::rag-runtime` requires Files API
- **Result:** RAG runtime disabled

### 3. Prompts API Not Available
- Even without prompts in APIs list, system tries to initialize it
- Permission error trying to write to `/opt/app-root/src/.llama/distributions/`
- When configured: KeyError: Api.prompts not in provider registry
- **Result:** Cannot configure prompts provider

### 4. Two ReplicaSets Active
- **Why:** Rolling update stuck due to crashing pods
- Old ReplicaSet (7cbd4f6d56) - 161m old
- New ReplicaSet (57667696db) - 18m old
- Both maintain 1 replica while trying to achieve desired state
- **Will resolve:** Once pods become healthy, old ReplicaSet scales to 0

## Root Cause
The `rh-dev` distribution (registry.redhat.io/rhoai/odh-llama-stack-core-rhel9@sha256:86f8d82f...) 
has severe API/provider limitations:

- ❌ No Files API providers
- ❌ No prompts API
- ❌ RAG runtime requires Files API
- ❌ Permission issues with default paths

## What's Working
✅ MinIO (llama-files bucket)
✅ Secrets management
✅ Port configuration (8321)
✅ vLLM inference providers (external HTTPS)
✅ Milvus vector database
✅ Docling document processing
✅ KFP v2 (DSPA)

## What's NOT Working
❌ LlamaStack pod (CrashLoopBackOff)
❌ Files API
❌ RAG tooling
❌ Agent prompts management

## Recommendation
1. Contact Red Hat support for:
   - Correct Files API provider type for rh-dev distribution
   - Prompts API availability/configuration
   - Expected API surface in rh-dev vs other distributions

2. Consider alternative approach:
   - Use Milvus directly for vector operations
   - Build custom RAG pipeline in KFP
   - Skip LlamaStack until distribution matures

3. Current best option for this demo:
   - Focus on Stage 1 (vLLM models working perfectly)
   - Use KFP for document ingestion → Milvus
   - Query Milvus + vLLM directly (no LlamaStack middle layer)

