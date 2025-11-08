# LlamaStack Embedding Provider Analysis

**Date:** 2025-11-06  
**Status:** INVESTIGATED  
**Component:** LlamaStack Embedding Configuration

---

## Executive Summary

**Investigation Goal:** Switch from `inline::sentence-transformers` to standalone `granite-embedding` service to prevent on-demand model loading from blocking LlamaStack API requests.

**Outcome:** **Cannot implement** with current Red Hat ET LlamaStack image due to missing `litellm` dependency.

**Current State:** Using `inline::sentence-transformers` with model caching. Acceptable performance after initial model load.

---

## Problem Statement

### Original Issue

When using `inline::sentence-transformers` provider in LlamaStack:

1. **On-Demand Loading:** Granite embedding model (500MB) loads on first request after pod restart
2. **Blocking Behavior:** ALL API requests block during model loading (2-5 minutes)
3. **Pipeline Failures:** KFP pipelines timeout waiting for LlamaStack insert operations
4. **Playground Issues:** UI stuck on "RUNNING..." because initial API calls timeout

### Impact

- **3 of 5 pipelines failed** during initial model loading phase
- **Playground unusable** during model loading
- **Poor UX** on pod restarts

---

## Attempted Solution

### Approach

Switch to standalone `granite-embedding` service (already deployed) using `remote::openai` provider:

```yaml
providers:
  inference:
    - provider_id: granite-embedding
      provider_type: remote::openai
      config:
        url: "http://granite-embedding.private-ai-demo.svc:8080/v1"
        api_token: fake
```

### Why It Failed

**Root Cause:** LlamaStack's `remote::openai` provider requires `litellm` Python module:

```python
File "/usr/local/lib/python3.11/site-packages/llama_stack/providers/remote/inference/openai/openai.py", line 20, in <module>
    from llama_stack.providers.utils.inference.litellm_openai_mixin import LiteLLMOpenAIMixin
  File "/usr/local/lib/python3.11/site-packages/llama_stack/providers/utils/inference/litellm_openai_mixin.py", line 10, in <module>
    import litellm
ModuleNotFoundError: No module named 'litellm'
```

**Image Limitation:** Red Hat ET LlamaStack image (`quay.io/redhat-et/llama:vllm-milvus-0.2.8`) does **not include** `litellm`.

---

## Current Configuration (Working)

### Provider Setup

```yaml
providers:
  inference:
    # Sentence Transformers for embeddings (inline, model cached after first load)
    # NOTE: First request after pod restart triggers 500MB model download/load (2-3 min)
    # Subsequent requests use cached model and are fast
    - provider_id: sentence-transformers
      provider_type: inline::sentence-transformers
      config: {}

models:
  # IBM Granite embedding model (768 dimensions)
  - metadata:
      embedding_dimension: 768
    model_id: ibm-granite/granite-embedding-125m-english
    model_type: embedding
    provider_id: sentence-transformers
    provider_model_id: ibm-granite/granite-embedding-125m-english
```

### Performance Characteristics

| Scenario | Behavior | Performance |
|----------|----------|-------------|
| **Fresh pod start** | Downloads & loads 500MB model | 2-5 minutes (blocks all requests) |
| **After model loaded** | Uses cached in-memory model | < 50ms per request |
| **Pod restart** | Re-downloads model (no persistent cache) | 2-5 minutes again |

### Verification

```bash
# Test LlamaStack responsiveness
oc -n private-ai-demo exec $(oc -n private-ai-demo get pods -l app=llama-stack -o name | head -1) -- \
  python3 -c "
import requests
resp = requests.get('http://localhost:8321/v1/models', timeout=10)
print(f'Status: {resp.status_code} - API responsive')
"
```

Expected output: `Status: 200 - API responsive` in < 1 second after model is loaded.

---

## Proper Solutions (Future)

### Option 1: Custom LlamaStack Image with LiteLLM ⭐ **RECOMMENDED**

**Approach:** Build custom container image based on Red Hat ET image, adding `litellm`:

```dockerfile
FROM quay.io/redhat-et/llama:vllm-milvus-0.2.8

# Install litellm to enable remote::openai provider
RUN pip install --no-cache-dir litellm

# Rest of image remains unchanged
```

**Benefits:**
- ✅ Clean separation: standalone embedding service
- ✅ No blocking on LlamaStack pod restarts
- ✅ Better resource isolation
- ✅ Follows microservices best practices

**Implementation Steps:**
1. Create `Containerfile` in `gitops/stage02-model-alignment/llama-stack/`
2. Build image: `podman build -t quay.io/YOUR_ORG/llama-stack-litellm:0.2.8`
3. Push to registry: `podman push quay.io/YOUR_ORG/llama-stack-litellm:0.2.8`
4. Update `deployment.yaml` to use custom image
5. Update `configmap.yaml` to use `remote::openai` provider

**Estimated Effort:** 2-3 hours (build, test, deploy)

---

### Option 2: Pre-load Embedding Model at Startup

**Approach:** Add init script to LlamaStack deployment that pre-loads model before server starts:

```yaml
spec:
  containers:
    - name: llamastack
      lifecycle:
        postStart:
          exec:
            command:
              - /bin/bash
              - -c
              - |
                python3 << 'EOF'
                from sentence_transformers import SentenceTransformer
                print("Pre-loading Granite embedding model...")
                model = SentenceTransformer("ibm-granite/granite-embedding-125m-english")
                print("Model loaded and cached!")
                EOF
```

**Benefits:**
- ✅ No custom image required
- ✅ Model ready before LlamaStack API starts
- ✅ Prevents blocking after startup

**Drawbacks:**
- ⚠️ Pod startup time increases by 2-3 minutes
- ⚠️ Kubernetes may kill pod if startup exceeds `startupProbe` threshold
- ⚠️ Still ties embedding to LlamaStack lifecycle

**Implementation Steps:**
1. Update `deployment.yaml` with `lifecycle.postStart` hook
2. Adjust `startupProbe` timeouts to allow for model loading
3. Test pod startup and verify model is cached

**Estimated Effort:** 1-2 hours (configure, test)

---

### Option 3: Persistent Model Cache Volume

**Approach:** Mount persistent volume to cache HuggingFace models across pod restarts:

```yaml
spec:
  volumes:
    - name: hf-cache
      persistentVolumeClaim:
        claimName: llama-stack-hf-cache
  containers:
    - name: llamastack
      env:
        - name: HF_HOME
          value: /hf-cache
      volumeMounts:
        - name: hf-cache
          mountPath: /hf-cache
```

**Benefits:**
- ✅ Model persists across pod restarts
- ✅ No re-download after first load
- ✅ Works with current image

**Drawbacks:**
- ⚠️ Requires PVC (storage cost)
- ⚠️ First load still blocks (one-time)
- ⚠️ RWO PVC limits horizontal scaling

**Implementation Steps:**
1. Create PVC for model cache (5Gi for Granite model)
2. Update deployment to mount PVC
3. Set `HF_HOME` env var
4. Trigger initial model load

**Estimated Effort:** 1 hour (PVC, deployment update)

---

## Recommendation

**For Production:** **Option 1** (Custom Image with LiteLLM)

**Reasoning:**
- Clean architecture: embedding as standalone microservice
- No blocking issues
- Better resource management
- Aligns with Red Hat best practices for cloud-native applications

**For Development/Testing:** Current configuration (inline::sentence-transformers) is acceptable
- Model caches after first load
- Playground works after initial 2-3 min wait
- Pipelines succeed after model is loaded

---

## Verification & Testing

### Test Embedding Service Independence

```bash
# 1. Test standalone granite-embedding service
oc -n private-ai-demo run test-embed --rm -i --restart=Never \
  --image=registry.access.redhat.com/ubi9/python-311:latest -- \
  python3 -c "
import urllib.request, json
req = urllib.request.Request(
    'http://granite-embedding.private-ai-demo.svc:8080/v1/embeddings',
    data=json.dumps({'input': 'test', 'model': 'ibm-granite/granite-embedding-125m-english'}).encode(),
    headers={'Content-Type': 'application/json'}
)
with urllib.request.urlopen(req, timeout=10) as resp:
    data = json.loads(resp.read())
    print(f'✅ Embedding dimension: {len(data[\"data\"][0][\"embedding\"])}')
"

# Expected: ✅ Embedding dimension: 768
```

### Test LlamaStack After Model Load

```bash
# 2. Test LlamaStack API (after initial model load)
oc -n private-ai-demo exec $(oc -n private-ai-demo get pods -l app=llama-stack -o name | head -1) -- \
  python3 -c "
import requests, time
start = time.time()
resp = requests.get('http://localhost:8321/v1/models', timeout=10)
elapsed = time.time() - start
print(f'✅ API responded in {elapsed:.2f}s' if resp.status_code == 200 else f'❌ Failed: {resp.status_code}')
"

# Expected: ✅ API responded in < 1s (after model cached)
```

### Test Vector Insert (End-to-End)

```bash
# 3. Test vector insert through LlamaStack
oc -n private-ai-demo exec $(oc -n private-ai-demo get pods -l app=llama-stack -o name | head -1) -- \
  python3 -c "
import requests
resp = requests.post(
    'http://localhost:8321/v1/vector-io/insert',
    json={
        'vector_db_id': 'rag_documents',
        'chunks': [
            {
                'content': 'This is a test chunk for embedding',
                'metadata': {'source': 'test', 'chunk_id': 0}
            }
        ]
    },
    timeout=30
)
print(f'✅ Insert succeeded' if resp.status_code == 200 else f'❌ Failed: {resp.status_code}')
"

# Expected: ✅ Insert succeeded (within 1-2 seconds after model cached)
```

---

## Related Resources

- **LlamaStack Documentation:** [Inference Providers](https://llama-stack.readthedocs.io/en/latest/providers/inference/)
- **Red Hat ET Images:** [quay.io/redhat-et/llama](https://quay.io/repository/redhat-et/llama)
- **LiteLLM Project:** [github.com/BerriAI/litellm](https://github.com/BerriAI/litellm)
- **Sentence Transformers:** [sbert.net](https://www.sbert.net/)
- **IBM Granite Embeddings:** [huggingface.co/ibm-granite/granite-embedding-125m-english](https://huggingface.co/ibm-granite/granite-embedding-125m-english)

---

## Status History

| Date | Action | Result |
|------|--------|--------|
| 2025-11-06 | Attempted switch to `remote::openai` | ❌ Failed - Missing `litellm` module |
| 2025-11-06 | Reverted to `inline::sentence-transformers` | ✅ Working - Model cached |
| 2025-11-06 | Documented limitation & solutions | 📝 Complete |

---

## Next Steps

1. ✅ **Document limitation** (this file)
2. ⏸️ **Defer custom image build** to Phase 3 or production hardening
3. ✅ **Accept current behavior** for development: 2-3 min initial wait is acceptable
4. ✅ **Monitor model load times** in telemetry
5. 📋 **Create backlog item** for Option 1 implementation in future sprint

**For now, the current configuration is sufficient for development and testing.**

