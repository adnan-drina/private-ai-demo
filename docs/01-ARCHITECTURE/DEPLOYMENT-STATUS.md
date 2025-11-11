# Deployment Status

**Last Updated**: November 3, 2025  
**Branch**: `stage1-complete`  
**Cluster**: `cluster-gmgrr.gmgrr.sandbox5294.opentlc.com`

---

## Stage 1: Model Serving ✅ COMPLETE

### Overview
Full end-to-end MLOps pipeline for Mistral 24B model serving with quantized and full-precision variants.

### ✅ Deployed Components

#### 1. InferenceServices (vLLM-CUDA Runtime)

| Model | Status | Revision | GPUs | Storage | URL |
|-------|--------|----------|------|---------|-----|
| **Quantized** (W4A16) | ✅ READY | 00001 | 1×L4 (g6.4xlarge) | S3 (MinIO) | https://mistral-24b-quantized-private-ai-demo... |
| **Full** (FP16) | ✅ READY | 00001 | 4×L4 (g6.12xlarge) | PVC (120Gi) | https://mistral-24b-private-ai-demo... |

**Configuration**:
- **Quantized**: Pulls from MinIO S3 (`s3://llm-models/Mistral-Small-24B-Instruct/quantized-w4a16/`)
- **Full**: Loads from PVC (`pvc://mistral-24b-pvc/`) - 83GB model mirrored from MinIO
- **ServingRuntime**: Shared `vllm-cuda` runtime for both models
- **GPU Quota**: 5/8 GPUs used (4 full + 1 quantized)

#### 2. Model Import Pipelines (Tekton)

**Status**: ✅ Both pipelines succeeded

| Pipeline | Status | Runtime Image | Model Upload | Registry |
|----------|--------|---------------|--------------|----------|
| mistral-quantized | ✅ SUCCEEDED | Built & pushed | ✅ MinIO S3 | Quay.io |
| mistral-full | ✅ SUCCEEDED | Built & pushed | ✅ MinIO S3 | Quay.io |

**Pipeline Tasks**:
1. `download-model` - Downloads from HuggingFace
2. `upload-to-minio` - Pushes to MinIO S3 storage
3. `build-runtime` - Builds vLLM runtime image with Buildah
4. `register-model` - Registers in Model Registry

**Key Configuration**:
- Images pushed to **Quay.io** (`quay.io/adnan_drina/mistral-*`)
- Model weights stored in **MinIO** (`minio.model-storage.svc:9000`)
- **No internal registry** - pipelines use Quay directly
- Tekton runs with Buildah for rootless container builds

#### 3. MinIO Object Storage

**Status**: ✅ Deployed & Healthy

- **Namespace**: `model-storage`
- **Storage**: 500Gi PVC
- **Access**: Internal service (`minio.model-storage.svc:9000`)
- **Dashboard**: https://minio-console-model-storage.apps...
- **Buckets**: `llm-models/` (model weights), `llm-results/` (test results)

#### 4. Model Registry

**Status**: ✅ Deployed

- **Namespace**: `rhoai-model-registries`
- **Service**: `private-ai-model-registry`
- **Models Registered**:
  - `Mistral-Small-24B-Instruct` → `quantized-w4a16-2501`
  - `Mistral-Small-24B-Instruct` → `fp16-2501`

#### 5. Service Mesh & Networking

**Configuration**:
- **Service Mesh**: Enabled for `private-ai-demo` namespace
- **Revision**: `data-science-smcp`
- **PeerAuthentication**: PERMISSIVE mode
- **NetworkPolicy**: Allows Model Registry access

---

## Recent Cleanup & Fixes (Nov 3, 2025)

### 1. PVC Size Fix ✅
**Problem**: 80Gi PVC too small for full model (90GB: 44GB consolidated + 45GB sharded)  
**Solution**: Increased to 120Gi PVC  
**Result**: Model mirrored successfully in 11 minutes @ 125 MiB/s  
**Files Changed**:
- `gitops/.../vllm/pvc-mistral-24b.yaml`

### 2. MinIO Secret Keys Fix ✅
**Problem**: Job expected `MINIO_ROOT_USER`/`PASSWORD` but secret had `accesskey`/`secretkey`  
**Solution**: Updated Job to use correct keys from deploy.sh  
**Result**: Mirror job completed successfully  
**Files Changed**:
- `docs/03-REFERENCE/initial-model-mirror/job-mirror-full-model.yaml`

### 3. ImageStreams Cleanup ✅
**Problem**: Empty ImageStreams (pipelines push to Quay, not internal registry)  
**Solution**: Removed unused ImageStreams from GitOps  
**Result**: Cleaner GitOps structure  
**Files Changed**:
- Deleted `gitops/stage01-model-serving/serving/archive/imagestreams/`
- Removed references in deployment scripts and documentation

### 4. GPU Quota Issue Fix ✅
**Problem**: Multiple failed revisions causing GPU quota exhaustion (6+4 > 8)  
**Solution**: Deleted all ISVCs and redeployed fresh with revision 00001  
**Result**: Both models READY with clean revisions  
**Current Usage**: 5/8 GPUs (4 full + 1 quantized)

### 5. Internal Registry Artifacts Removal ✅
**Problem**: `internal-registry-private-ai` secret and connection not needed  
**Solution**: Moved to reference docs, removed from active GitOps  
**Files Moved**:
- `connection-internal-registry.yaml` → `docs/03-REFERENCE/secrets/`
- `job-mirror-full-model.yaml` → `docs/03-REFERENCE/initial-model-mirror/`

---

## GitOps Structure

```
gitops/stage01-model-serving/
├── serving/
│   ├── project-namespace/        # Namespace, quotas, service accounts
│   ├── network-policy/            # Model Registry access
│   ├── model-registry/            # ConfigMap for pipelines
│   ├── pipelines/                 # Tekton Tasks & Pipelines
│   │   ├── 00-rbac/               # ServiceAccounts, Roles, RoleBindings
│   │   └── active/
│   │       ├── 01-tasks/          # download-model, upload-to-minio, build-runtime, register-model
│   │       ├── 02-pipeline/       # pipeline-model-import & testing pipeline charts
│   │       └── 03-pipelineruns/   # mistral-full, mistral-quantized PipelineRuns
│   ├── vllm/                      # InferenceServices & ServingRuntime
│   │   ├── servingruntime-vllm-cuda.yaml
│   │   ├── pvc-mistral-24b.yaml
│   │   ├── inferenceservice-mistral-24b.yaml
│   │   ├── inferenceservice-mistral-24b-quantized.yaml
│   │   ├── virtualservice-*.yaml
│   │   └── destinationrule-*.yaml
│   └── model-serving-testing/     # Jupyter notebooks for validation
```

---

## Reproducibility

### From Scratch Deployment

```bash
# 1. Set environment variables
cp stages/stage1-model-serving/.env.template stages/stage1-model-serving/.env
# Edit .env with your credentials

# 2. Run deployment script
cd stages/stage1-model-serving
./deploy.sh

# 3. Sync ArgoCD
oc apply -f ../../gitops-apps/stage01/application.yaml

# 4. Run model import pipelines
oc create -f gitops/stage01-model-serving/serving/pipelines/active/03-pipelineruns/pipelinerun-mistral-quantized.yaml
oc create -f gitops/stage01-model-serving/serving/pipelines/active/03-pipelineruns/pipelinerun-mistral-full.yaml

# 5. Mirror full model to PVC (one-time)
oc apply -f docs/03-REFERENCE/initial-model-mirror/job-mirror-full-model.yaml

# 6. Verify deployment
oc -n private-ai-demo get isvc
```

### Secrets Required (Created by deploy.sh)

- `quay-credentials` - Quay.io robot account
- `hf-token` - HuggingFace token for model downloads
- `minio-credentials` - MinIO access (`accesskey`/`secretkey`)
- `s3-credentials-kserve` - MinIO S3 for InferenceService storage-initializer

**Note**: `internal-registry-private-ai` secret is **NOT required** (pipelines use Quay.io)

---

## Verification

### Test Endpoints

```bash
# Quantized model (1×L4, S3-backed)
curl https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1/models

# Full model (4×L4, PVC-backed)
curl https://mistral-24b-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1/models
```

### Check Status

```bash
# InferenceServices
oc -n private-ai-demo get isvc

# Pods & GPU usage
oc -n private-ai-demo get pods -l serving.kserve.io/inferenceservice
oc -n private-ai-demo get resourcequota ai-workload-quota

# Pipelines
oc -n private-ai-demo get pipelineruns

# Model Registry
oc -n rhoai-model-registries get modelregistry
```

---

## Known Limitations

1. **GPU Quota**: 8 GPUs total (sufficient for 1 full + 1-2 quantized models)
2. **PVC Size**: Full model requires 120Gi minimum (90GB model + overhead)
3. **Model Loading Time**: Full model takes ~6 minutes to load from PVC
4. **ImageStreams**: Not used (pipelines push directly to Quay.io)

---

## Next Steps (Stage 2)

- ⏳ KFP v2 RAG pipeline deployment
- ⏳ Model alignment & fine-tuning
- ⏳ Advanced monitoring & observability
- ⏳ Production hardening & scaling

---

## Commits Summary

**Latest Commits** (stage1-complete branch):

1. `3157e3e` - refactor: remove unused ImageStreams and internal-registry artifacts
2. `8951a04` - fix(gitops): remove internal-registry secret from GitOps and mirror job  
3. `3907159` - fix(vllm): correct MinIO secret keys in mirror job
4. `088057e` - fix(vllm): increase full model PVC to 120Gi and add PostSync mirror job

**All changes are committed and reproducible from GitOps** ✅

