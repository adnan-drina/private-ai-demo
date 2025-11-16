# Stage 4: Collection Registration Fix - Critical Discovery

**Date**: November 16, 2025 02:00 UTC  
**Issue**: Repeated 404 "Vector Store not found" failures  
**Solution**: Manual collection registration via API

---

## Critical Discovery

**Collections defined in LlamaStack ConfigMap are NOT automatically registered!**

They must be explicitly registered via the `/v1/vector_stores` API endpoint.

---

## The Problem

### Symptoms
- Pipeline repeatedly failed with `404 Not Found for /v1/vector-io/insert`
- Error message: `Vector Store 'red_hat_docs' not found`
- Failed even after:
  - ✅ Dropping and recreating collection
  - ✅ Restarting LlamaStack pod
  - ✅ Configuring `auto_id=false` in Milvus
  - ✅ Verifying ConfigMap has `vector_dbs` section

### Failed Attempts Timeline

| Time | Action | Result |
|------|--------|--------|
| 00:14 | Wiped Milvus database | Collection dropped ✅ |
| 01:00 | Launched pipeline | ❌ Failed (404 - collection not found) |
| 01:27 | Restarted LlamaStack | Collections NOT auto-registered |
| 01:28 | Relaunched pipeline | ❌ Failed (404 - collection not found) |

---

## Root Cause Analysis

### Investigation

**Checked vector stores via API**:
```bash
curl http://localhost:8321/v1/vector_stores
```

**Result**:
```json
{
  "object": "list",
  "data": [],
  "has_more": false
}
```

**Empty list!** Even though `red_hat_docs` is defined in ConfigMap:

```yaml
# gitops/stage02-model-alignment/llama-stack/configmap.yaml
vector_dbs:
  - vector_db_id: red_hat_docs
    provider_id: milvus-shared
    provider_vector_db_id: red_hat_docs
    embedding_model: ibm-granite/granite-embedding-125m-english
    embedding_dimension: 768
```

### Why This Happens

**ConfigMap `vector_dbs` section defines CONFIGURATION, not REGISTRATION.**

When you drop a collection via `DELETE /v1/vector_stores/{id}`:
1. ✅ Milvus collection is deleted
2. ✅ LlamaStack un-registers the vector store
3. ❌ Restarting LlamaStack **does NOT** re-register from config
4. ❌ Collections must be manually registered via API

**This is by design** - LlamaStack expects you to register collections programmatically, not declaratively.

---

## The Solution

### Manual Registration via API

**Register the collection**:
```bash
curl -X POST http://localhost:8321/v1/vector_stores \
  -H "Content-Type: application/json" \
  -d '{
    "name": "red_hat_docs",
    "chunking_strategy": {
      "type": "fixed_size_chunking"
    },
    "embedding_config": {
      "embedding_model": "ibm-granite/granite-embedding-125m-english",
      "vector_db_id": "red_hat_docs",
      "provider_id": "milvus-shared"
    }
  }'
```

**Response**:
```json
{
  "id": "vs_0e19961e-6541-49d8-bb99-1ea00ee7a4d2",
  "object": "vector_store",
  "created_at": 1763277935,
  "name": "red_hat_docs",
  "status": "completed",
  "metadata": {
    "provider_id": "milvus-shared"
  }
}
```

**Verify registration**:
```bash
curl http://localhost:8321/v1/vector_stores
```

**Now shows**:
```json
{
  "object": "list",
  "data": [
    {
      "id": "vs_0e19961e-6541-49d8-bb99-1ea00ee7a4d2",
      "name": "red_hat_docs",
      "status": "completed"
    }
  ]
}
```

---

## Implementation

### Commands Used (OpenShift)

```bash
# Get LlamaStack pod
LLAMA_POD=$(oc get pods -n private-ai-demo -l app=llama-stack -o jsonpath='{.items[0].metadata.name}')

# Register collection
oc exec $LLAMA_POD -n private-ai-demo -- \
  curl -s -X POST http://localhost:8321/v1/vector_stores \
  -H "Content-Type: application/json" \
  -d '{
    "name": "red_hat_docs",
    "chunking_strategy": {"type": "fixed_size_chunking"},
    "embedding_config": {
      "embedding_model": "ibm-granite/granite-embedding-125m-english",
      "vector_db_id": "red_hat_docs",
      "provider_id": "milvus-shared"
    }
  }'

# Verify
oc exec $LLAMA_POD -n private-ai-demo -- \
  curl -s http://localhost:8321/v1/vector_stores | python3 -m json.tool
```

---

## Result

**After Manual Registration**:

| Metric | Value |
|--------|-------|
| Pipeline Status | ✅ Running |
| Progress (5 min) | 16/18 tasks |
| Vector Store API | ✅ Returns registered collection |
| Insert Errors | ✅ None |
| Expected Completion | ~35-55 minutes |

**NEW Pipeline**: `data-processing-and-insertion-tvpjn`  
**Run ID**: `8a1e6f0c-e938-45c9-8645-494b757c699f`  
**Launched**: 02:00 UTC  
**Status**: ✅ Healthy

---

## Best Practices for Future

### Option 1: Register in Deployment Script

Add registration to `stages/stage2-model-alignment/deploy.sh`:

```bash
# After LlamaStack is ready
echo "Registering vector stores..."
for VECTOR_DB in red_hat_docs acme_corporate eu_ai_act; do
  oc exec deployment/llama-stack -n private-ai-demo -- \
    curl -s -X POST http://localhost:8321/v1/vector_stores \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$VECTOR_DB\",
      \"chunking_strategy\": {\"type\": \"fixed_size_chunking\"},
      \"embedding_config\": {
        \"embedding_model\": \"ibm-granite/granite-embedding-125m-english\",
        \"vector_db_id\": \"$VECTOR_DB\",
        \"provider_id\": \"milvus-shared\"
      }
    }"
done
```

### Option 2: Init Job in GitOps

Create `gitops/stage02-model-alignment/llama-stack/job-register-collections.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: llamastack-register-collections
  namespace: private-ai-demo
  annotations:
    argocd.argoproj.io/hook: PostSync
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: register
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            # Wait for LlamaStack
            until curl -s http://llama-stack-service:8321/v1/health; do
              echo "Waiting for LlamaStack..."
              sleep 5
            done
            
            # Register collections
            for VECTOR_DB in red_hat_docs acme_corporate eu_ai_act; do
              curl -X POST http://llama-stack-service:8321/v1/vector_stores \
                -H "Content-Type: application/json" \
                -d "{
                  \"name\": \"$VECTOR_DB\",
                  \"chunking_strategy\": {\"type\": \"fixed_size_chunking\"},
                  \"embedding_config\": {
                    \"embedding_model\": \"ibm-granite/granite-embedding-125m-english\",
                    \"vector_db_id\": \"$VECTOR_DB\",
                    \"provider_id\": \"milvus-shared\"
                  }
                }"
            done
```

### Option 3: Check Before Pipeline Launch

Add to `stages/stage2-model-alignment/run-batch-ingestion.sh`:

```python
# Check if collection is registered
response = requests.get(f"{llamastack_url}/v1/vector_stores")
stores = response.json().get("data", [])
store_names = [s["name"] for s in stores]

if vector_db_id not in store_names:
    print(f"Registering {vector_db_id}...")
    requests.post(
        f"{llamastack_url}/v1/vector_stores",
        json={
            "name": vector_db_id,
            "chunking_strategy": {"type": "fixed_size_chunking"},
            "embedding_config": {
                "embedding_model": "ibm-granite/granite-embedding-125m-english",
                "vector_db_id": vector_db_id,
                "provider_id": "milvus-shared"
            }
        }
    )
```

---

## Lessons Learned

1. **ConfigMap ≠ Registration**  
   Defining `vector_dbs` in ConfigMap creates configuration, not registration.

2. **Dropping = Unregistering**  
   `DELETE /v1/vector_stores/{id}` removes registration, not just data.

3. **Restart ≠ Re-registration**  
   Restarting LlamaStack pod does NOT auto-register from config.

4. **API-First Design**  
   LlamaStack expects programmatic registration, not declarative.

5. **OpenShift != Upstream**  
   This behavior may be specific to Red Hat's LlamaStack distribution.

---

## Related Issues

**Previous Failed Pipelines** (all same root cause):
- `data-processing-and-insertion-f6w9g` - Stale backup folder + unregistered collection
- `data-processing-and-insertion-kdhrl` - Missing credentials + unregistered collection
- `data-processing-and-insertion-lbgmm` - Wiped DB but collection not re-registered
- `data-processing-and-insertion-hn2rs` - Restarted LlamaStack but no auto-registration

**All fixed by**: Manual collection registration via `/v1/vector_stores` API

---

## Verification

**To check if collections are registered**:
```bash
oc exec deployment/llama-stack -n private-ai-demo -- \
  curl -s http://localhost:8321/v1/vector_stores | python3 -m json.tool
```

**Expected output**:
```json
{
  "data": [
    {"name": "red_hat_docs", "status": "completed"}
  ]
}
```

**If empty `[]`**, run manual registration before launching pipeline.

---

## Status

**Current Pipeline**: `data-processing-and-insertion-tvpjn`  
**Collection**: ✅ Registered (vs_0e19961e-6541-49d8-bb99-1ea00ee7a4d2)  
**Progress**: 16/18 tasks after 5 minutes  
**Health**: ✅ Running normally  
**Next**: Wait for completion, then validate

---

**Summary**: The repeated 404 failures were caused by collections not being automatically registered from ConfigMap after they were dropped or LlamaStack was restarted. Manual registration via `/v1/vector_stores` API fixed the issue. Future deployments should include programmatic registration in deploy scripts or init jobs.

