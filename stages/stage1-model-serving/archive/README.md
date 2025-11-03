# Archived Scripts

These scripts are from an older architecture and are no longer maintained.

## Archived Files

### deploy-modelcar-pipeline.sh
**Reason**: Replaced by consolidated `deploy.sh`
- Referenced ImageStreams (now archived - pipelines push to Quay.io)
- Referenced separate workspace PVCs (consolidated into pipeline workspaces)
- Old pipeline structure (pre-Tekton v1 migration)

**Current Approach**: `deploy.sh` handles all deployment (GitOps + secrets)

### query-full-model.sh
**Reason**: Architecture changed to PVC-backed storage
- Queried Model Registry for OCI image URIs
- Full model now uses PVC (`pvc://mistral-24b-pvc/`), not OCI images
- Quantized model uses S3 (`s3://llm-models/`)

**Current Approach**: Model URIs are in InferenceService manifests

### validate.sh
**Reason**: References obsolete components
- Checked for model download jobs (now part of Tekton pipelines)
- Checked for MinIO in `private-ai-demo` namespace (now in `model-storage`)
- Checked for benchmark jobs (testing pipelines replaced this)

**Current Validation**:
```bash
# Check InferenceServices
oc -n private-ai-demo get isvc

# Check pipelines
oc -n private-ai-demo get pipelineruns

# Check Model Registry
oc -n rhoai-model-registries get modelregistry
```

## Current Architecture

**Model Import**:
1. Tekton Pipeline: `pipeline-model-import`
   - `download-model` - Downloads from HuggingFace
   - `upload-to-minio` - Pushes to MinIO S3
   - `build-runtime` - Builds vLLM runtime image
   - `register-model` - Registers in Model Registry
2. Images pushed to **Quay.io** (not internal registry)
3. Model weights in **MinIO** (`model-storage` namespace)

**Model Serving**:
- **Quantized**: S3-backed (`s3://llm-models/`)
- **Full**: PVC-backed (`pvc://mistral-24b-pvc/`)
- Both use shared `vllm-cuda` ServingRuntime

**Testing**:
- Tekton Pipeline: `model-testing-v2`
- Results published to Model Registry
- Check results: `./check-testing-results.sh`

See `../README.md` for current usage.
