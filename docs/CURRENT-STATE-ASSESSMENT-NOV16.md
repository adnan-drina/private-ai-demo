# Current State Assessment - November 16, 2025

**Branch**: `feature/stage4-implementation`  
**Assessment Time**: After latest uncommitted changes  
**Status**: 🟡 **MIXED STATE** - Partially reverted, but inconsistent

---

## 🚨 **CRITICAL FINDING: Hybrid Configuration**

Your current changes have created a **hybrid/mixed state** that won't work:

| Component | Current State | Should Be (v0.2.8) | Status |
|-----------|---------------|-------------------|--------|
| **LlamaStack Image** | v0.2.8 | v0.2.8 | ✅ CORRECT |
| **API Version** | `version: '2'` | `version: '2'` | ✅ CORRECT |
| **Milvus Schema Config** | v0.3.0 overrides | No overrides | ❌ WRONG |
| **Pipeline Component** | Has `stored_chunk_id` | No `stored_chunk_id` | ❌ WRONG |
| **Compiled Pipeline YAML** | Has `stored_chunk_id` | No `stored_chunk_id` | ❌ WRONG |

---

## 📊 **What Happened**

Looking at your git diff, you:

1. ✅ **Correctly** reverted the **image** to v0.2.8:
   ```yaml
   image: "quay.io/redhat-et/llama:vllm-milvus-granite-0.2.8"
   ```

2. ❌ **Incorrectly** RE-ADDED the v0.3.0 Milvus schema overrides:
   ```yaml
   # BEFORE (Correct for v0.2.8):
   # Schema: Int64 PK (auto_id=true), vector (HNSW indexed), dynamic fields
   # Do NOT override text_field or id_field - provider manages these
   
   # AFTER (Your change - v0.3.0 workaround):
   # Schema: VarChar PK (stored_chunk_id), vector (HNSW indexed), dynamic fields
   # FIXED: Disabled auto_id to accept custom string IDs from ingestion pipeline
   id_field: "stored_chunk_id"
   text_field: "content"
   auto_id: false  # CRITICAL: Accept custom string IDs instead of auto-generating integers
   ```

3. ❌ **Did not remove** `stored_chunk_id` from pipeline:
   - Still present in `batch-docling-rag-pipeline.yaml` (5 occurrences)
   - Still present in component logic

---

## ⚠️ **Why This Won't Work**

### **The Problem**:

```
v0.2.8 Image + v0.3.0 Config = INCOMPATIBLE
```

**Detailed Breakdown**:

| Layer | What It Expects | What It Gets | Result |
|-------|----------------|--------------|--------|
| **LlamaStack v0.2.8** | Integer `chunk_id` (auto-generated) | String `stored_chunk_id` (from pipeline) | ❌ Type mismatch |
| **Milvus (via v0.2.8)** | Auto-generate integer PK | Told `auto_id: false`, expect string | ❌ Schema conflict |
| **Pipeline** | Sends `stored_chunk_id` as string | v0.2.8 expects no explicit ID | ❌ Field ignored or rejected |

**Expected Failures**:
1. Pipeline insert may **silently ignore** `stored_chunk_id` (v0.2.8 doesn't use it)
2. Milvus will **auto-generate integer IDs anyway** (v0.2.8 behavior)
3. Retrieval will **fail** because chunk IDs don't match what's expected
4. Collections may **not register** correctly due to schema mismatch

---

## ✅ **What You Got Right**

1. **Image Revert** ✅
   - Switched from `llama-stack-custom:latest` (v0.3.0rc3) → `quay.io/redhat-et/llama:vllm-milvus-granite-0.2.8`
   - This is the foundation of the fix

2. **API Version** ✅
   - ConfigMap explicitly sets `version: '2'`
   - References v0.2.11 docs (correct)

3. **Deleted TrustyAI Wrapper** ✅
   - `configmap-sitecustomize.yaml` deleted (324 lines)
   - No longer trying to load v0.3.0 providers

4. **Added Startup Probe Patch** ✅
   - `patch-startup-probe.yaml` increases failureThreshold to 30
   - Gives LlamaStack more time to start (good for v0.2.8 image)

5. **PVC StorageClass** ✅
   - Added `storageClassName: gp3-csi`
   - Ensures consistent storage provisioning

---

## ❌ **What's Still Wrong**

### **1. ConfigMap Milvus Schema Overrides** 🔴 **CRITICAL**

**File**: `gitops/stage02-model-alignment/llama-stack/configmap.yaml` (lines 64-75)

**Current** (WRONG - v0.3.0 workaround):
```yaml
vector_io:
  # Schema: VarChar PK (stored_chunk_id), vector (HNSW indexed), dynamic fields
  # FIXED: Disabled auto_id to accept custom string IDs from ingestion pipeline
  - provider_id: milvus-shared
    provider_type: remote::milvus
    config:
      token: ""
      uri: "tcp://milvus-standalone.private-ai-demo.svc.cluster.local:19530"
      # Field mappings - Use custom string IDs
      # Override default schema to accept stored_chunk_id as string PK
      id_field: "stored_chunk_id"
      text_field: "content"
      auto_id: false  # CRITICAL: Accept custom string IDs instead of auto-generating integers
      embedding_dimension: 768
      metric_type: "L2"
      search_params:
        metric_type: "L2"
        params:
          ef: 64
      collections:
        - vector_db_id: acme_corporate
          provider_vector_db_id: acme_corporate
        - vector_db_id: red_hat_docs
          provider_vector_db_id: red_hat_docs
        - vector_db_id: eu_ai_act
          provider_vector_db_id: eu_ai_act
      kvstore:
        type: sqlite
        path: /data/milvus_kv.db
```

**Should Be** (CORRECT for v0.2.8):
```yaml
vector_io:
  # Milvus in private-ai-demo - optimized with HNSW index
  # Reference: https://llama-stack.readthedocs.io/en/v0.2.11/providers/vector_io/milvus.html
  # Schema: Int64 PK (auto_id=true), vector (HNSW indexed), dynamic fields
  - provider_id: milvus-shared
    provider_type: remote::milvus
    config:
      uri: "tcp://milvus-standalone.private-ai-demo.svc.cluster.local:19530"
      # Field mappings - LET PROVIDER OWN THE SCHEMA
      # Provider creates: chunk_id (PK), vector, chunk_content (JSON)
      # Do NOT override text_field or id_field - provider manages these
      embedding_dimension: 768
      metric_type: "L2"
      # Search params aligned with HNSW index (M=16, efConstruction=200)
      search_params:
        metric_type: "L2"
        params:
          ef: 64
      # Collection mappings (scenario-specific)
      collections:
        - vector_db_id: acme_corporate
          provider_vector_db_id: acme_corporate
        - vector_db_id: red_hat_docs
          provider_vector_db_id: red_hat_docs
        - vector_db_id: eu_ai_act
          provider_vector_db_id: eu_ai_act
```

**Key Changes Needed**:
- ❌ **Remove**: `token: ""` (not needed)
- ❌ **Remove**: `id_field: "stored_chunk_id"`
- ❌ **Remove**: `text_field: "content"`
- ❌ **Remove**: `auto_id: false`
- ❌ **Remove**: `kvstore:` section (not needed)
- ✅ **Update** comment: `Int64 PK (auto_id=true)` (not `VarChar PK`)

---

### **2. Pipeline Component** 🔴 **CRITICAL**

**Issue**: Pipeline still generates and sends `stored_chunk_id` (v0.3.0 behavior)

**Evidence**: 5 occurrences of `stored_chunk_id` in compiled YAML

**Action Required**: 
1. Edit `stages/stage2-model-alignment/kfp/components/insert_via_llamastack.py`
2. Remove lines ~103-109:
   ```python
   # DELETE THIS:
   chunk_id_str = f"{source_name}_chunk_{i}"
   
   llamastack_chunks.append({
       "content": content_text,
       "metadata": metadata_dict,
       "stored_chunk_id": chunk_id_str  # DELETE THIS LINE
   })
   ```

3. Replace with simple v0.2.x format:
   ```python
   # v0.2.x - provider auto-generates IDs
   llamastack_chunks.append({
       "content": content_text,
       "metadata": metadata_dict
       # NO stored_chunk_id - provider manages this
   })
   ```

4. Recompile pipeline:
   ```bash
   cd stages/stage2-model-alignment/kfp
   kfp dsl compile --py batch-docling-rag-pipeline.py --output batch-docling-rag-pipeline.yaml
   ```

---

## 📋 **Corrected Action Plan**

### **Step 1: Revert ConfigMap to v0.2.8** (3 minutes)

```bash
cd /Users/adrina/Sandbox/private-ai-demo

# Undo the wrong changes
git checkout HEAD -- gitops/stage02-model-alignment/llama-stack/configmap.yaml

# Verify it's back to v0.2.x format
grep "auto_id\|id_field\|text_field" gitops/stage02-model-alignment/llama-stack/configmap.yaml
# Should return: (no matches)
```

**Alternative**: Manually edit `configmap.yaml` and remove lines 69-75:
- Delete `token: ""`
- Delete `id_field: "stored_chunk_id"`
- Delete `text_field: "content"`
- Delete `auto_id: false`
- Delete `kvstore:` section (lines 91-93)
- Update comment on line 64: `Int64 PK (auto_id=true)`

---

### **Step 2: Fix Pipeline Component** (5 minutes)

```bash
# Option A: If component file exists
vi stages/stage2-model-alignment/kfp/components/insert_via_llamastack.py
# Remove stored_chunk_id generation and assignment

# Option B: If component is inline in pipeline Python
vi stages/stage2-model-alignment/kfp/batch-docling-rag-pipeline.py
# Find the insert_via_llamastack function
# Remove stored_chunk_id logic
```

---

### **Step 3: Recompile Pipeline** (2 minutes)

```bash
cd stages/stage2-model-alignment/kfp

kfp dsl compile \
  --py batch-docling-rag-pipeline.py \
  --output batch-docling-rag-pipeline.yaml

# Verify no stored_chunk_id in compiled YAML
grep -c "stored_chunk_id" batch-docling-rag-pipeline.yaml
# Expected: 0 (no matches)
```

---

### **Step 4: Commit the CORRECT Changes** (2 minutes)

```bash
cd /Users/adrina/Sandbox/private-ai-demo

git add gitops/stage02-model-alignment/llama-stack/configmap.yaml
git add stages/stage2-model-alignment/kfp/batch-docling-rag-pipeline.yaml

# Also commit the good changes
git add gitops/stage02-model-alignment/llama-stack/patch-startup-probe.yaml
git add gitops/stage02-model-alignment/llama-stack/pvc.yaml
git add gitops/stage02-model-alignment/llama-stack/kustomization.yaml

git commit -m "fix: Complete v0.2.8 alignment - remove v0.3.0 schema overrides

COMPLETE FIX:
- ConfigMap: Remove auto_id=false, id_field, text_field (v0.3.0 workarounds)
- Pipeline: Remove stored_chunk_id generation (v0.2.x auto-generates)
- PVC: Add gp3-csi storageClassName
- Startup probe: Increase failureThreshold to 30

NOW ALIGNED:
✅ Image: v0.2.8
✅ API: version 2
✅ Config: No schema overrides (provider-managed)
✅ Pipeline: No stored_chunk_id (provider-managed)

SCHEMA:
- v0.2.8 uses: Int64 PK (auto-generated), not VarChar
- Provider manages: chunk_id, vector, chunk_content"
```

---

### **Step 5: Wipe Milvus** (1 minute)

```bash
# Drop all collections (mixed v0.3.0/v0.2.8 data)
oc exec -it deployment/llama-stack -n private-ai-demo -- \
  curl -X DELETE http://localhost:8321/v1/vector-dbs/red_hat_docs

oc exec -it deployment/llama-stack -n private-ai-demo -- \
  curl -X DELETE http://localhost:8321/v1/vector-dbs/acme_corporate

oc exec -it deployment/llama-stack -n private-ai-demo -- \
  curl -X DELETE http://localhost:8321/v1/vector-dbs/eu_ai_act
```

---

### **Step 6: Deploy v0.2.8 LlamaStack** (5 minutes)

```bash
cd /Users/adrina/Sandbox/private-ai-demo

# Apply corrected configuration
oc apply -f gitops/stage02-model-alignment/llama-stack/configmap.yaml
oc apply -f gitops/stage02-model-alignment/llama-stack/pvc.yaml
oc apply -k gitops/stage02-model-alignment/llama-stack/

# Delete old pod (force image pull + new config)
oc delete pod -l app=llama-stack -n private-ai-demo

# Wait for new pod
oc wait --for=condition=Ready pod -l app=llama-stack -n private-ai-demo --timeout=300s

# Verify version and health
LLAMA_POD=$(oc get pods -l app=llama-stack -n private-ai-demo --no-headers | awk '{print $1}')
oc exec $LLAMA_POD -n private-ai-demo -- curl -s http://localhost:8321/health
```

---

### **Step 7: Run RAG Pipeline** (30-60 minutes)

```bash
cd stages/stage2-model-alignment

# Get OAuth token
export KFP_TOKEN=$(oc whoami -t)

# Launch fixed pipeline
./run-batch-ingestion.sh red_hat_docs \
  s3://llama-files/scenario1-red-hat/ \
  "v0.2.8-complete-alignment"

# Monitor
watch -n 10 'oc get workflow -n private-ai-demo | tail -5'
```

---

### **Step 8: Validate Retrieval** (5 minutes)

```bash
# Test v0.2.x /v1/vector-io/query API
oc exec -it deployment/llama-stack -n private-ai-demo -- \
  curl -X POST http://localhost:8321/v1/vector-io/query \
  -H "Content-Type: application/json" \
  -d '{
    "vector_db_id": "red_hat_docs",
    "query": "What is OpenShift?",
    "k": 3
  }'

# Expected response:
# {
#   "chunks": [
#     {
#       "chunk_id": 123,  # Integer (NOT string)
#       "content": "...",
#       "metadata": {...},
#       "score": 0.85
#     },
#     ...
#   ]
# }
```

---

## 🎯 **What's Left To Do (Priority Order)**

| # | Task | File | Est. Time | Status |
|---|------|------|-----------|--------|
| 1 | **Revert ConfigMap** | `configmap.yaml` | 3 min | ❌ **MUST DO** |
| 2 | **Fix Pipeline Component** | `insert_via_llamastack.py` | 5 min | ❌ **MUST DO** |
| 3 | **Recompile Pipeline** | `batch-docling-rag-pipeline.yaml` | 2 min | ❌ **MUST DO** |
| 4 | **Commit Correct Changes** | Multiple files | 2 min | ❌ **MUST DO** |
| 5 | **Wipe Milvus** | via `oc exec` | 1 min | ❌ **MUST DO** |
| 6 | **Deploy v0.2.8** | Apply manifests | 5 min | ❌ **MUST DO** |
| 7 | **Run Pipeline** | Launch KFP | 30-60 min | ⏳ **WAIT** |
| 8 | **Validate Retrieval** | Test API | 5 min | ⏳ **WAIT** |

**Total Time**: ~1-2 hours (including pipeline execution)

---

## ✅ **When Complete, You'll Have**

1. ✅ LlamaStack v0.2.8 image (RHOAI 2.25 compatible)
2. ✅ API version 2 configuration
3. ✅ No schema overrides (provider-managed IDs)
4. ✅ Pipeline not sending custom IDs
5. ✅ Clean Milvus database (integer IDs)
6. ✅ Working RAG ingestion
7. ✅ Working RAG retrieval
8. ✅ Simplified configuration (no wrapper code)

---

## 🔍 **How to Verify You're Done**

Run this verification script:

```bash
cd /Users/adrina/Sandbox/private-ai-demo

echo "VERIFICATION CHECKLIST:"
echo ""

echo "1. Image is v0.2.8?"
grep "vllm-milvus-granite-0.2.8" gitops/stage02-model-alignment/llama-stack/llamastack-distribution.yaml && echo "  ✅ YES" || echo "  ❌ NO"

echo ""
echo "2. API version is 2?"
grep "version: '2'" gitops/stage02-model-alignment/llama-stack/configmap.yaml && echo "  ✅ YES" || echo "  ❌ NO"

echo ""
echo "3. ConfigMap has NO schema overrides?"
grep -E "auto_id|id_field|text_field" gitops/stage02-model-alignment/llama-stack/configmap.yaml && echo "  ❌ STILL HAS OVERRIDES" || echo "  ✅ CLEAN"

echo ""
echo "4. Pipeline has NO stored_chunk_id?"
grep "stored_chunk_id" stages/stage2-model-alignment/kfp/batch-docling-rag-pipeline.yaml && echo "  ❌ STILL HAS IT" || echo "  ✅ CLEAN"

echo ""
echo "5. PVC has storageClassName?"
grep "storageClassName: gp3-csi" gitops/stage02-model-alignment/llama-stack/pvc.yaml && echo "  ✅ YES" || echo "  ❌ NO"

echo ""
echo "ALL CHECKS MUST PASS ✅"
```

---

## 📝 **Summary**

**Current Status**: 🟡 **30% Complete**

| Aspect | Status | Notes |
|--------|--------|-------|
| Image | ✅ GOOD | v0.2.8 |
| API Version | ✅ GOOD | '2' |
| ConfigMap Schema | ❌ BAD | Has v0.3.0 overrides |
| Pipeline | ❌ BAD | Has stored_chunk_id |
| PVC | ✅ GOOD | Added storageClassName |
| Startup Probe | ✅ GOOD | Increased failureThreshold |

**Next Action**: Revert ConfigMap changes (remove v0.3.0 schema overrides)

---

**Document Created**: November 16, 2025  
**Status**: 🟡 **ACTION REQUIRED** - See Step 1 above

