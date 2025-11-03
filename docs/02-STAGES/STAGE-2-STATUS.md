# Stage 2: Model Alignment (RAG) - Status Report

**Date:** November 3, 2025  
**Stage:** 2 - Model Alignment with RAG  
**Overall Status:** ⚠️ Partially Deployed (4/6 components working)

---

## Executive Summary

Stage 2 enhances LLM responses with private enterprise data using Retrieval-Augmented Generation (RAG). The infrastructure is partially deployed with **2 critical components failing** that block RAG workflows.

### Component Status

| Component | Status | Issue |
|-----------|--------|-------|
| **Milvus** | ✅ 1/1 Ready | Working (26h) |
| **MariaDB** | ✅ 1/1 Ready | Working (KFP metadata) |
| **DSPA (KFP)** | ✅ All pods Running | Working (6 pods healthy) |
| **Stage 1 Models** | ✅ Both Ready | Working (mistral-24b + quantized) |
| **Docling** | ❌ 0/1 CrashLoopBackOff | 386 restarts in 25h |
| **Llama Stack** | ❌ 0/1 MinimumReplicasUnavailable | SCC Forbidden Error |

---

## Issue #1: Docling - CrashLoopBackOff (CRITICAL)

### Root Cause
Container downloads **2GB+ of CUDA/PyTorch dependencies at RUNTIME** on every restart, timing out before readiness probe (30s) succeeds.

### Evidence
```
Downloading nvidia_cusolver_cu12-11.7.3.90 (267.5 MB)
Downloading nvidia_cusparse_cu12-12.5.8.93 (288.2 MB)
Downloading nvidia_nccl_cu12-2.27.5 (322.3 MB)
Total: 2GB+ per restart
```

**Current State:**
- 386 restarts over 25 hours
- Never completes initialization
- Readiness probe: `connection refused` on port 8080

### Impact
- ❌ RAG document ingestion pipelines **cannot run**
- ❌ Cannot process PDFs for Milvus vector storage
- ❌ **Blocks all Stage 2 RAG workflows**

### Solutions (Ordered by Best Practice)

#### A. ✅ Build Custom Docling Image (RECOMMENDED)
**Red Hat Best Practice**

```dockerfile
# Dockerfile
FROM registry.access.redhat.com/ubi9/python-311:latest

# Install CUDA/PyTorch dependencies at build time
RUN pip install --no-cache-dir \
    torch torchvision torchaudio \
    nvidia-cudnn-cu12 nvidia-cublas-cu12 \
    nvidia-cuda-runtime-cu12

# Copy application
COPY docling/ /app/
WORKDIR /app

CMD ["python", "app.py"]
```

**Steps:**
1. Build image: `podman build -t quay.io/yourorg/docling:v1 .`
2. Push: `podman push quay.io/yourorg/docling:v1`
3. Update deployment image reference
4. Apply and verify

**Effort:** 30-60 minutes  
**Risk:** Low  
**Sustainability:** High (production-ready)

#### B. ⚠️ Increase Probe Delays (TEMPORARY WORKAROUND)

```yaml
spec:
  containers:
  - name: docling
    readinessProbe:
      initialDelaySeconds: 600  # 10 minutes
      periodSeconds: 10
    livenessProbe:
      initialDelaySeconds: 900  # 15 minutes
      periodSeconds: 30
```

**Pros:** Quick fix (2 minutes)  
**Cons:** Inefficient, slow startup every time  
**Use Case:** Testing only, not production

#### C. ⚠️ Add PVC for pip Cache (PARTIAL FIX)

Helps with subsequent restarts but doesn't solve the first-time download problem.

---

## Issue #2: Llama Stack - SCC Forbidden (HIGH PRIORITY)

### Root Cause
Deployment specifies `fsGroup: 0` (root group), which is **rejected by OpenShift restricted-v2 SCC**.

### Error Message
```
Error creating: pods "llama-stack-..." is forbidden: 
unable to validate against any security context constraint: 
  restricted-v2: .spec.securityContext.fsGroup: 
  Invalid value: []int64{0}: 0 is not an allowed group
```

### Impact
- ❌ Llama Stack orchestrator **not running**
- ❌ Cannot use RAG with Llama Stack API
- ❌ Notebooks cannot connect to orchestrator

### Solutions (Ordered by Best Practice)

#### A. ✅ Fix fsGroup in Deployment (RECOMMENDED)

**Option 1: Remove fsGroup (let OpenShift auto-assign)**
```yaml
spec:
  template:
    spec:
      securityContext:
        # Remove fsGroup: 0
```

**Option 2: Use namespace-specific fsGroup**
```bash
# Get namespace's supplemental groups range
oc get namespace private-ai-demo -o yaml | grep supplemental

# Use first value from range (e.g., 1001130000)
```

```yaml
spec:
  template:
    spec:
      securityContext:
        fsGroup: 1001130000
```

**Steps:**
1. Read current deployment: `oc get deploy llama-stack -n private-ai-demo -o yaml > llama-stack.yaml`
2. Edit and remove/fix `fsGroup`
3. Apply: `oc apply -f llama-stack.yaml`
4. Verify pod starts: `oc get pod -l app=llama-stack -n private-ai-demo`

**Effort:** 5 minutes  
**Risk:** Very low  
**Sustainability:** High (OpenShift security best practice)

#### B. ⚠️ Grant anyuid SCC (LESS PREFERRED)

```bash
oc adm policy add-scc-to-user anyuid -z llama-stack-sa -n private-ai-demo
```

**Pros:** Quick fix  
**Cons:** Security trade-off, not recommended for production  
**Use Case:** Testing only

---

## GitOps Status: NOT ALIGNED ⚠️

### Current State
- Stage 2 resources deployed **manually** (not via ArgoCD)
- GitOps manifests exist in `gitops/stage02-model-alignment/`
- No ArgoCD Application CR for stage02

### Impact
- ❌ Configuration drift possible
- ❌ Changes not tracked in git
- ❌ Cannot leverage auto-sync/self-healing

### Solution
```bash
# Create ArgoCD Application for Stage 2
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: stage02-model-alignment
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/private-ai-demo.git
    targetRevision: main
    path: gitops/stage02-model-alignment
  destination:
    server: https://kubernetes.default.svc
    namespace: private-ai-demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

---

## Recommended Action Plan

### Priority 1: Fix Llama Stack (5 minutes) ✅

**Quick win - unblocks orchestrator**

```bash
# Remove fsGroup restriction
oc patch deployment llama-stack -n private-ai-demo --type='json' \
  -p='[{"op": "remove", "path": "/spec/template/spec/securityContext/fsGroup"}]'

# Verify pod starts
oc get pod -l app=llama-stack -n private-ai-demo -w
```

**Expected Result:** Pod starts within 1-2 minutes

---

### Priority 2: Fix Docling (Choose approach)

#### Option A: Custom Image (30-60 minutes) - RECOMMENDED

1. Create `Containerfile` with pre-installed deps
2. Build: `podman build -t quay.io/yourorg/docling:v1 .`
3. Push: `podman push quay.io/yourorg/docling:v1`
4. Update deployment image
5. Test with single document pipeline

#### Option B: Probe Delay (2 minutes) - TEMPORARY

```bash
oc patch deployment docling -n private-ai-demo --type='json' \
  -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 600},
    {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value": 900}
  ]'
```

Wait 10-15 minutes for container to stabilize.

---

### Priority 3: Align with GitOps (15-30 minutes)

1. Verify `gitops/stage02-model-alignment/` manifests build correctly
2. Create ArgoCD Application CR (see above)
3. Sync and validate
4. Commit any manual changes to git

---

### Priority 4: End-to-End RAG Validation (30 minutes)

Once Docling + Llama Stack are healthy:

```bash
# Run Red Hat document ingestion pipeline
oc create -f gitops/stage02-model-alignment/pipelines/pipelinerun-redhat-docs.yaml

# Monitor pipeline
tkn pr logs -f <pipelinerun-name> -n private-ai-demo

# Verify vectors in Milvus
oc exec -it deployment/milvus-standalone -n private-ai-demo -- \
  ls -lh /var/lib/milvus

# Test RAG query via Llama Stack API
LLAMA_URL=$(oc get route llama-stack -n private-ai-demo -o jsonpath='{.spec.host}')
curl -k https://${LLAMA_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-24b-quantized",
    "messages": [{"role": "user", "content": "What is OpenShift AI?"}]
  }'

# Validate notebooks
oc get notebook -n private-ai-demo
# Access notebook route and run 02-rag-demo-redhat.ipynb
```

---

## Success Criteria

- [ ] Docling: 1/1 Ready, no CrashLoopBackOff
- [ ] Llama Stack: 1/1 Ready, pod running
- [ ] Document ingestion pipeline completes successfully
- [ ] Vectors visible in Milvus
- [ ] RAG query returns enhanced response with context
- [ ] Notebooks can connect to Llama Stack API
- [ ] Stage 2 managed by ArgoCD (Synced/Healthy)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              STAGE 2: RAG ARCHITECTURE                  │
└─────────────────────────────────────────────────────────┘

User Query
    ↓
Llama Stack Orchestrator
    ↓
1. Generate query embedding ────→ Granite Embedding Model
2. Vector similarity search ────→ Milvus (Vector DB)
3. Retrieve top-k chunks
4. Build augmented prompt
    ↓
5. Generate response ───────────→ vLLM (mistral-24b)
    ↓
Enhanced Response + Citations

Document Ingestion (Tekton Pipelines):
  PDFs/Docs → Docling → Chunks → Granite Embeddings → Milvus
```

---

## References

- **Docling Image Issue:** Downloading 2GB+ CUDA deps at runtime
- **Llama Stack SCC Error:** `fsGroup: 0` not allowed in restricted-v2
- **GitOps Path:** `gitops/stage02-model-alignment/`
- **Stage 2 README:** `stages/stage2-model-alignment/README.md`


