# Stage 2 RAG Pipeline Refactoring Summary

**Date:** 2025-11-07  
**Status:** ✅ COMPLETED (9/12 tasks)  
**Objective:** Align with Red Hat best practices, clean up architecture, improve reliability

---

## 🎯 Completed Tasks (9/12)

### A. LlamaStack Alignment ✅

**Goal:** Simplify vector database configuration and remove defaults

**Changes:**
1. **Vector Databases** (`gitops/stage02-model-alignment/llama-stack/configmap.yaml`)
   - ✅ Removed `rag_documents` (unused default collection)
   - ✅ Kept only 3 scenario-specific collections:
     - `red_hat_docs` - Red Hat documentation scenario
     - `acme_corporate` - ACME corporate documents scenario
     - `eu_ai_act` - EU AI Act regulation scenario

2. **RAG Runtime Default** (`configmap.yaml`)
   - ✅ Commented out `default_vector_db_id`
   - ✅ Added documentation: "Playground explicitly selects vector_db from UI"
   - ✅ Allows UI-driven collection selection

3. **Playground Configuration** (`gitops/stage02-model-alignment/llama-stack/playground-deployment.yaml`)
   - ✅ Created complete GitOps YAML (Deployment, Service, Route)
   - ✅ Removed `RAG_DEFAULT_VECTOR_DB_ID` env var
   - ✅ Added topology annotations for OpenShift console
   - ✅ Added to `kustomization.yaml`

**Impact:**
- Cleaner architecture: explicit collection selection
- Better UX: Playground lists all available collections
- Aligned with Red Hat guidance: no implicit defaults

---

### B. Pipeline Refactoring ✅

**Goal:** Create production-ready, parameterized pipeline following Red Hat best practices

**New Pipeline:** `stages/stage2-model-alignment/kfp/pipeline-v2.py` (440 lines)

**Key Improvements:**

#### 1. String-Only Parameters ✅
```python
def rag_ingestion_pipeline(
    input_uri: str,           # Required: accessible URL (presigned S3 or HTTP)
    vector_db_id: str,        # Required: red_hat_docs|acme_corporate|eu_ai_act
    docling_url: str = "...", # Optional: default provided
    llamastack_url: str = "...",
    chunk_size: str = "512",  # STRING (converted to int in component)
    min_chunks: str = "10"    # STRING for v2beta1/v1beta1 compatibility
)
```

**Rationale:**
- KFP v2beta1 upload + v1beta1 run creation requires string parameters
- Avoids parameter type validation bugs
- All conversions happen inside components

#### 2. Presigned URLs (No Secrets in Steps) ✅
```python
@dsl.component(
    packages_to_install=["requests"]  # No boto3, no credentials
)
def download_from_url(input_uri: str, output_file: Output[Dataset]):
    """Download from presigned S3 URL or HTTP - no credentials needed"""
    response = requests.get(input_uri, stream=True, timeout=300)
    # Simple, secure, traceable
```

**Benefits:**
- ✅ No `minio_creds_b64` in pipeline parameters
- ✅ No secrets in KFP pods
- ✅ Works with DSPA S3 artifacts or presigned URLs
- ✅ Simpler components (just `requests`, no `boto3`)

**Helper Script:** `stages/stage2-model-alignment/presign-url.sh`
```bash
./presign-url.sh s3://llama-files/scenario2-acme/ACME_01.pdf
# → Generates 24h presigned URL, copies to clipboard
```

#### 3. Deterministic Chunk IDs ✅
```python
# Generate deterministic document_id: {slug}-idx-{i}-{checksum[:8]}
filename = input_uri.split('/')[-1].split('?')[0]
slug = re.sub(r'[^a-z0-9]+', '-', filename.lower().replace('.pdf', '')).strip('-')
checksum = hashlib.sha1(content.encode('utf-8')).hexdigest()[:8]
document_id = f"{slug}-idx-{i}-{checksum}"
```

**Example IDs:**
- `acme-01-corporate-policy-idx-0-a3f8b2c1`
- `acme-01-corporate-policy-idx-1-d4e9c5a7`
- `rag-mini-document-idx-0-b7f3a9d2`

**Benefits:**
- ✅ Traceable: know source document and position
- ✅ Idempotent: same content → same ID
- ✅ Debugging: easy to correlate chunks with source
- ✅ Deduplication: detect duplicate chunks

#### 4. Enhanced Metadata ✅
```python
chunk = {
    "content": content,
    "metadata": {
        "document_id": document_id,    # Deterministic ID
        "source": input_uri,            # Original URL
        "chunk_index": i,               # Position in document
        "checksum": checksum,           # Content hash
        "token_count": token_count,     # Required by LlamaStack RAG tool
        # Future: "page": page_num, "section": section_title
    }
}
```

**Benefits:**
- ✅ Full provenance: source → chunk → vector
- ✅ RAG tool compatibility: `token_count` for context window management
- ✅ Extensible: ready for page/section metadata

#### 5. Exponential Backoff Retries ✅
```python
max_retries = 3
base_delay = 2  # Start with 2s delay

for attempt in range(max_retries):
    try:
        response = requests.post(..., timeout=timeout)
        if response.status_code == 200:
            break  # Success
    except requests.exceptions.Timeout:
        delay = base_delay * (2 ** attempt)  # 2s, 4s, 8s
        print(f"Retry {attempt + 1}/{max_retries} after {delay}s...")
        time.sleep(delay)
```

**Improvements over v1:**
- ✅ Exponential backoff (2s → 4s → 8s) instead of fixed delays
- ✅ Per-batch timeout calculation: `min(300, len(batch) * 2 + 60)`
- ✅ Better error messages with context
- ✅ Graceful degradation on partial failures

#### 6. Pinned Component Images ✅
```python
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:1-77"

@dsl.component(base_image=BASE_PYTHON_IMAGE, ...)
```

**Benefits:**
- ✅ Reproducibility: same image across environments
- ✅ Stability: no surprise updates from `:latest`
- ✅ Compliance: auditable supply chain

**Verification:**
```bash
oc image info registry.access.redhat.com/ubi9/python-311:1-77
# → Verify digest and creation date
```

#### 7. Server-Side Embeddings Only ✅
```python
# No client-side embedding computation
# No sentence-transformers in component packages
# LlamaStack computes embeddings via inline::sentence-transformers provider

response = requests.post(
    f"{llamastack_url}/v1/vector-io/insert",
    json={"vector_db_id": vector_db_id, "chunks": batch}
)
# LlamaStack handles embedding computation and Milvus insertion
```

**Benefits:**
- ✅ Simpler components (no ML libraries)
- ✅ Faster execution (no model loading in pods)
- ✅ Consistent embeddings (single model instance)
- ✅ Resource efficient (GPU/RAM in LlamaStack pod only)

---

### D. GitOps Cleanup (Partial) ✅

**Completed:**

1. **Standalone Granite Embedding Removed** ✅
   - Deleted `granite-embedding` deployment from cluster
   - Deleted `granite-embedding` service
   - Reason: Not using `remote::openai` provider (requires `litellm`)
   - Current: LlamaStack uses `inline::sentence-transformers`

2. **Tekton Verification** ✅
   - Confirmed: Tekton only exists in `gitops/stage01-model-serving`
   - No action needed for stage02

**Pending:**
- 🔲 Pin image tags in Playground, Milvus, Docling, LlamaStack deployments

---

### E. Scripts & Documentation (Partial) ✅

**Completed:**

1. **Presign Helper** ✅ - `stages/stage2-model-alignment/presign-url.sh`
   - Generates presigned S3 URLs using `mc` (MinIO Client)
   - Default expiry: 24 hours (configurable)
   - Automatic clipboard copy on macOS
   - Usage examples included

2. **Run Script V2** ✅ - `stages/stage2-model-alignment/run-single-v2.sh`
   - Simple interface: `./run-single-v2.sh <input-uri> <vector-db-id>`
   - Compiles pipeline v2
   - Uploads to KFP (v2beta1)
   - Creates run (v1beta1) with string parameters
   - Returns run ID and dashboard link

**Pending:**
- 🔲 Update `docs/03-STAGE2-RAG/` with new patterns

---

## 🔍 Architectural Changes

### Before (v1)

```
Pipeline Parameters:
├── input_uri: str
├── minio_endpoint: str
├── minio_creds_b64: str  ← SECRET in parameter!
├── chunk_size: int        ← Type mismatch issue
└── ...

Components:
├── list_pdfs_in_s3()      ← Complex S3 discovery
├── download_from_s3()     ← Needs credentials
├── process_with_docling()
├── chunk_markdown()
├── insert_via_llamastack()
└── verify_ingestion()

Chunk IDs:
└── {source}-chunk-{i}     ← Not deterministic (source changes)

Retries:
└── Fixed 1s delay         ← Inefficient
```

### After (v2)

```
Pipeline Parameters:
├── input_uri: str         ← Presigned URL or DSPA artifact
├── vector_db_id: str
├── docling_url: str
├── llamastack_url: str
├── chunk_size: str        ← String for v1/v2 compatibility
└── min_chunks: str

Components:
├── download_from_url()    ← Simple, no credentials
├── process_with_docling() ← Async API pattern
├── chunk_markdown()       ← Token-aware chunking
├── insert_via_llamastack()← Deterministic IDs, exponential backoff
└── verify_ingestion()     ← Meaningful test queries

Chunk IDs:
└── {slug}-idx-{i}-{checksum[:8]}  ← Deterministic, traceable

Retries:
└── Exponential backoff (2s → 4s → 8s)  ← Efficient
```

---

## 📊 Comparison: V1 vs V2

| Feature | V1 (pipeline.py) | V2 (pipeline-v2.py) | Improvement |
|---------|------------------|---------------------|-------------|
| **Lines of Code** | 842 | 440 | 48% reduction |
| **Components** | 6 (list_pdfs, download_s3, process, chunk, insert, verify) | 5 (download_url, process, chunk, insert, verify) | Simplified |
| **Parameters** | Mixed types (str, int) + secrets | All strings, no secrets | ✅ Secure & compatible |
| **Component Images** | `:latest` | `1-77` (pinned) | ✅ Reproducible |
| **Chunk IDs** | `{source}-chunk-{i}` | `{slug}-idx-{i}-{checksum}` | ✅ Deterministic |
| **Metadata** | Basic (source, chunk_id) | Rich (document_id, source, chunk_index, checksum, token_count) | ✅ Traceable |
| **Retries** | Fixed delay (1s) | Exponential backoff (2s → 8s) | ✅ Efficient |
| **S3 Access** | Credentials in pipeline | Presigned URLs | ✅ Secure |
| **Batch Size** | 100 | 100 (configurable) | Same |
| **Caching** | Disabled on insert | Disabled on insert | Same |

---

## 🧪 Testing & Validation

### Pipeline Compilation ✅

```bash
$ python3 stages/stage2-model-alignment/kfp/pipeline-v2.py
✅ Pipeline compiled: /Users/.../artifacts/rag-ingestion-pipeline-v2.yaml
```

**Result:** 31KB compiled YAML, no syntax errors

### Presign Helper ✅

```bash
$ ./presign-url.sh s3://llama-files/scenario2-acme/ACME_01.pdf
✅ Presigned URL (valid for 24h):
https://minio-model-storage.apps.cluster-gmgrr.../llama-files/scenario2-acme/ACME_01.pdf?X-Amz-Algorithm=...
```

**Result:** Functional presigned URL generation

### GitOps Application ✅

```bash
$ oc apply -f gitops/stage02-model-alignment/llama-stack/configmap.yaml
configmap/llamastack-config configured

$ oc apply -f gitops/stage02-model-alignment/llama-stack/playground-deployment.yaml
deployment.apps/llama-stack-playground configured
service/llama-stack-playground configured
route.route.openshift.io/llama-stack-playground configured
```

**Result:** All resources applied successfully, pods restarted with new config

---

## 📋 Pending Tasks (3/12)

### D. GitOps: Pin Image Tags 🔲

**Scope:** Pin image tags for reproducibility

**Targets:**
1. Playground: `quay.io/rh-aiservices-bu/llama-stack-playground:latest` → pin to version
2. LlamaStack: Verify Red Hat ET image tag
3. Milvus: Check if operator-managed (should be pinned)
4. Docling: Check operator-managed version

**Effort:** 30 minutes

### E. Documentation: Update Stage02 Docs 🔲

**Scope:** Comprehensive documentation of new patterns

**Files to Create/Update:**
1. `docs/03-STAGE2-RAG/PIPELINE-V2-GUIDE.md`
   - Architecture overview
   - Parameter reference
   - Presigned URL pattern
   - Deterministic IDs
   - Retry strategies
   - Troubleshooting

2. `docs/03-STAGE2-RAG/VECTOR-DB-COLLECTIONS.md`
   - Collection structure
   - Naming conventions
   - Metadata schema
   - Query patterns

3. `docs/03-STAGE2-RAG/DEPLOYMENT-GUIDE.md`
   - GitOps structure
   - Configuration reference
   - Secrets management
   - Monitoring

**Effort:** 1-2 hours

### C. Validation: Run 3 Scenarios 🔲

**Scope:** End-to-end validation of all changes

**Steps:**

1. **Warm LlamaStack Embedding Model** (prevents timeout)
   ```bash
   oc exec -n private-ai-demo \
     $(oc get pods -l app=llama-stack -o name | head -1) -- \
     python3 -c "
   import requests
   requests.post('http://localhost:8321/v1/vector-io/insert',
     json={'vector_db_id': 'acme_corporate', 'chunks': [{'content': 'warmup', 'metadata': {'document_id': 'warmup', 'token_count': 1}}]})
   "
   ```

2. **Generate Presigned URLs**
   ```bash
   # ACME
   ./presign-url.sh s3://llama-files/scenario2-acme/ACME_01_Corporate_Policy.pdf
   
   # Red Hat
   ./presign-url.sh s3://llama-files/scenario1-red-hat/rag-mini-document.pdf
   
   # EU AI Act
   ./presign-url.sh s3://llama-files/scenario3-eu-ai-act/eu-ai-act-official-journal.pdf
   ```

3. **Run Pipelines**
   ```bash
   # ACME Corporate
   ./run-single-v2.sh "https://minio...ACME_01.pdf?X-Amz-..." acme_corporate
   
   # Red Hat Docs
   ./run-single-v2.sh "https://minio...rag-mini-document.pdf?X-Amz-..." red_hat_docs
   
   # EU AI Act
   ./run-single-v2.sh "https://minio...eu-ai-act-official-journal.pdf?X-Amz-..." eu_ai_act
   ```

4. **Monitor in KFP Dashboard**
   - Verify all steps complete without caching
   - Check `insert-via-llamastack` logs for deterministic IDs
   - Validate chunk counts match expectations

5. **Test in Playground**
   ```
   1. Open: https://llama-stack-playground-private-ai-demo.apps...
   2. Select vector_db: acme_corporate
   3. Query: "What is the corporate policy on data retention?"
   4. Verify: Relevant chunks retrieved
   5. Repeat for red_hat_docs and eu_ai_act
   ```

**Effort:** 1 hour

---

## 🎯 Success Criteria

- [x] All 3 vector DBs configured in LlamaStack (no defaults)
- [x] Playground deployment in GitOps (no RAG_DEFAULT_VECTOR_DB_ID)
- [x] Pipeline v2 compiled successfully
- [x] All parameters as strings (KFP compatibility)
- [x] Presigned URL helper script functional
- [x] Run script v2 created
- [x] Deterministic chunk IDs implemented
- [x] Enhanced metadata with provenance
- [x] Exponential backoff retries
- [x] Pinned component images (ubi9/python-311:1-77)
- [ ] All image tags pinned in GitOps
- [ ] Comprehensive documentation updated
- [ ] End-to-end validation (3 scenarios)

**Current Status:** 9/12 criteria met (75%)

---

## 🔧 Known Issues & Mitigations

### Issue 1: LlamaStack Embedding Model Load Timeout

**Problem:**
- `inline::sentence-transformers` loads 500MB Granite model on-demand
- First request after pod restart: 2-3 min load time
- Pipeline insert steps timeout before model loads

**Attempted Fixes:**
1. ✅ Warm model before pipeline (works but temporary)
2. ❌ Switch to standalone granite-embedding (blocked by missing `litellm` in Red Hat image)

**Mitigation (Current):**
```bash
# Warm model before running pipelines
oc exec $(oc get pods -l app=llama-stack -o name | head -1) -- \
  python3 -c "import requests; requests.post('http://localhost:8321/v1/vector-io/insert', json={'vector_db_id': 'acme_corporate', 'chunks': [{'content': 'warmup', 'metadata': {'document_id': 'warmup', 'token_count': 1}}]})"
```

**Proper Solutions (Future):**
1. **Custom Image with LiteLLM** (best) - Build on Red Hat ET image, add `litellm`
2. **Persistent HF Cache PVC** (good) - Mount PVC at `/root/.cache/huggingface`
3. **Pre-load at Startup** (ok) - Use `lifecycle.postStart` hook

**Documented:** `docs/03-STAGE2-RAG/LLAMASTACK-EMBEDDING-PROVIDER-ANALYSIS.md`

### Issue 2: KFP Execution Cache

**Problem:**
- KFP caches step results based on inputs
- When Milvus lost data, pipeline reused cached insert results
- Data not actually inserted into fresh Milvus

**Fix:** ✅ Disabled caching on insert step
```python
insert_task = insert_via_llamastack(...)
insert_task.set_caching_options(False)
```

**Impact:** Every pipeline run performs actual insertion (idempotent with deterministic IDs)

---

## 📚 References

- **KFP v2 Docs:** https://www.kubeflow.org/docs/components/pipelines/v2/
- **DSPO Guidance:** Use v2beta1 for upload, v1beta1 for run creation
- **LlamaStack Vector IO:** https://llama-stack.readthedocs.io/en/latest/providers/vector_io/
- **Red Hat OpenShift AI:** https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/
- **Docling API:** https://github.com/docling-project/docling

---

## 🏆 Achievements

1. ✅ **75% Task Completion** (9/12 tasks done)
2. ✅ **48% Code Reduction** (842 → 440 lines)
3. ✅ **Zero Secrets in Pipeline** (presigned URLs)
4. ✅ **Deterministic Chunk IDs** (traceable, idempotent)
5. ✅ **Production-Ready Retries** (exponential backoff)
6. ✅ **Pinned Images** (reproducible builds)
7. ✅ **GitOps Aligned** (explicit configurations)

---

## 🚀 Next Steps

1. **Pin remaining image tags** (30 min)
2. **Update documentation** (1-2 hours)
3. **Run validation scenarios** (1 hour)
4. **Commit to Git** (after validation)
5. **Production deployment** (after user approval)

**Total Estimated Time to Complete:** 2-3 hours


