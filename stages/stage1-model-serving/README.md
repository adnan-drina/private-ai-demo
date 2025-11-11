# Stage 1: Model Serving with vLLM

## Overview

Stage 1 demonstrates production-ready model serving using vLLM on GPU-accelerated infrastructure. This stage deploys two Mistral 24B models (quantized and full precision) with automated MLOps pipelines for model import and registration.

## Architecture

### Model Serving
- **vLLM ServingRuntime** - Shared CUDA runtime for efficient inference
- **Mistral 24B Quantized** - 1 GPU (g6.4xlarge), W4A16 quantization, S3-backed storage
- **Mistral 24B Full** - 4 GPUs (g6.12xlarge), FP16 precision, PVC-backed storage (120Gi)

### Storage
- **MinIO** - S3-compatible object storage (`model-storage` namespace) for model weights
- **PVC** - Persistent volume for full model (avoids ephemeral storage pressure)

### MLOps Pipeline (Tekton)
- **Model Import Pipeline** - Download from HuggingFace, upload to MinIO, build runtime image, register in Model Registry

### Model Registry
- Centralized model metadata and versioning
- Integration with import pipeline

## Prerequisites

- **Stage 0** deployed (RHOAI, GPU Operator, Service Mesh)
- **GPU nodes** available (1× g6.4xlarge + 1× g6.12xlarge)
- **HuggingFace Token** - For model downloads
- **Quay.io Credentials** - For runtime image storage

## Quick Start

### 1. Initial Deployment

```bash
# Copy environment template
cp .env.template .env

# Edit .env with your credentials:
#   - HF_TOKEN
#   - QUAY_USERNAME, QUAY_PASSWORD, QUAY_ORGANIZATION
#   - MINIO_ACCESS_KEY, MINIO_SECRET_KEY

# Deploy all Stage 1 components
./deploy.sh
```

### 2. Import Models

```bash
# Import quantized model (~20GB, 30 minutes)
./run-model-import.sh quantized

# Import full model (~48GB, 60 minutes)
./run-model-import.sh full
```

### 3. Test Models (Optional)

```bash
# Test quantized model (lm-eval + benchmarks)
./run-model-testing.sh quantized

# Test full model
./run-model-testing.sh full

# Check results in Model Registry dashboard
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Main deployment script (GitOps resources + secrets) |
| `run-model-import.sh` | Start model import pipeline |
| `run-model-testing.sh` | Start model testing pipeline (lm-eval + benchmarks) |

Legacy helper scripts from earlier architecture iterations were removed during repository cleanup. Use `git log` if historical references are needed.

## Model Import Pipeline

The `model-import` Tekton pipeline automates the full model lifecycle:

**Tasks**:
1. **download-model** - Downloads from HuggingFace using HF_TOKEN
2. **upload-to-minio** - Uploads model weights to MinIO S3 storage
3. **build-runtime** - Builds vLLM runtime image with Buildah and pushes to Quay.io
4. **register-model** - Registers model metadata in Model Registry

**Configuration**:
- Images pushed to **Quay.io** (`quay.io/${QUAY_ORG}/mistral-*`)
- Model weights stored in **MinIO** (`minio.model-storage.svc:9000`)
- No ImageStreams (pipelines use Quay directly)
- Rootless Buildah builds with PVC-backed storage

**PipelineRun manifests**:
- `gitops/.../03-pipelineruns/pipelinerun-mistral-quantized.yaml`
- `gitops/.../03-pipelineruns/pipelinerun-mistral-full.yaml`

## Model Testing Pipeline

The `model-testing-v2` Tekton pipeline validates deployed InferenceServices:

**Tasks**:
1. **run-lm-eval-v2** - Language model evaluation (hellaswag, arc_easy)
2. **run-guidellm-v2** - Performance benchmarks (TTFT, throughput, latency)
3. **publish-test-results-v2** - Uploads results to Model Registry

**Features**:
- Tests deployed models (no download/build needed)
- Security-hardened (internal HTTP services, service mesh mTLS)
- Model Registry SDK integration
- Provenance tracking (pipeline UID, timestamp, artifacts)
- MinIO artifact storage for audit trail

**PipelineRun manifests**:
- `gitops/.../03-pipelineruns/pipelinerun-test-mistral-quantized-v2.yaml`
- `gitops/.../03-pipelineruns/pipelinerun-test-mistral-full-v2.yaml`

## InferenceService Configuration

Both models use the shared `vllm-cuda` ServingRuntime:

### Quantized Model (S3-backed)
```yaml
storageUri: s3://llm-models/Mistral-Small-24B-Instruct/quantized-w4a16/
resources:
  requests:
    cpu: 6
    memory: 16Gi
    nvidia.com/gpu: "1"
nodeSelector:
  nvidia.com/gpu.product: NVIDIA-L4
  node.kubernetes.io/instance-type: g6.4xlarge
```

### Full Model (PVC-backed)
```yaml
storageUri: pvc://mistral-24b-pvc/
resources:
  requests:
    cpu: 16
    memory: 80Gi
    nvidia.com/gpu: "4"
    ephemeral-storage: 25Gi
nodeSelector:
  nvidia.com/gpu.product: NVIDIA-L4
  node.kubernetes.io/instance-type: g6.12xlarge
```

**Note**: Full model uses PVC to avoid ephemeral storage pressure (90GB model on node disk).

## Verification

### Check Deployment Status

```bash
# InferenceServices
oc get isvc -n private-ai-demo

# Expected output:
# NAME                    READY   URL
# mistral-24b             True    https://mistral-24b-...
# mistral-24b-quantized   True    https://mistral-24b-quantized-...
```

### Test Endpoints

```bash
# Get model information
curl -k https://mistral-24b-quantized-private-ai-demo.apps.<cluster>/v1/models

# Test inference
curl -k https://mistral-24b-quantized-private-ai-demo.apps.<cluster>/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-24b-quantized",
    "prompt": "Hello, my name is",
    "max_tokens": 50
  }'
```

### Check Pipeline Status

```bash
# List all pipeline runs
oc get pipelineruns -n private-ai-demo

# Check specific pipeline
oc get pipelinerun <name> -n private-ai-demo

# View logs
tkn pipelinerun logs <name> -n private-ai-demo -f
```

### Check Model Registry

```bash
# Get Model Registry route
MR_URL=$(oc get route private-ai-model-registry-http -n rhoai-model-registries -o jsonpath='{.spec.host}')

# List registered models
curl -sk "https://$MR_URL/api/model_registry/v1alpha3/registered_models" | jq '.items[] | {name, id}'

# Check model versions
curl -sk "https://$MR_URL/api/model_registry/v1alpha3/model_versions?registeredModelId=<id>" | jq '.items[] | {name, customProperties}'
```

## Key Metrics

| Metric | Quantized (1 GPU) | Full (4 GPUs) |
|--------|-------------------|---------------|
| Model Size | ~20 GB | ~90 GB (consolidated + sharded) |
| GPU Memory | ~24 GB | ~80 GB |
| Precision | W4A16 | FP16 |
| Storage | MinIO S3 | PVC (120Gi) |
| Load Time | ~2 minutes | ~6 minutes |
| Cost/Hour | ~$1.00 | ~$5.00 |

## Troubleshooting

### InferenceServices Not Ready

```bash
# Check pod status
oc get pods -n private-ai-demo -l serving.kserve.io/inferenceservice

# Check logs
oc logs -n private-ai-demo <predictor-pod> -c kserve-container --tail=100

# Check events
oc get events -n private-ai-demo --sort-by=.lastTimestamp | tail -30

# Check GPU allocation
oc get resourcequota ai-workload-quota -n private-ai-demo
```

### Pipeline Failures

```bash
# Check PipelineRun status
oc get pipelinerun <name> -n private-ai-demo

# View detailed logs
./monitor-pipeline.sh -n private-ai-demo -r <pipelinerun-name>

# Check task-specific logs
oc logs -n private-ai-demo <taskrun-pod> -c step-<step-name>

# Common issues:
# - HF_TOKEN invalid: Check secret 'hf-token'
# - Quay push failed: Check secret 'quay-credentials'
# - MinIO connection: Check secret 'minio-credentials'
# - Storage full: Check PVC capacity for pipeline workspaces
```

### Model Registry Issues

```bash
# Check Model Registry status
oc get modelregistry private-ai-model-registry -n rhoai-model-registries

# Check route
oc get route -n rhoai-model-registries

# Test connectivity
MR_URL=$(oc get route private-ai-model-registry-http -n rhoai-model-registries -o jsonpath='{.spec.host}')
curl -sk "https://$MR_URL/api/model_registry/v1alpha3/registered_models"
```

## GitOps Structure

```
gitops/stage01-model-serving/
├── serving/
│   ├── project-namespace/          # Namespace, quotas, RBAC
│   ├── network-policy/              # Model Registry access
│   ├── model-registry/              # ConfigMap for pipelines
│   ├── pipelines/                   # Tekton infrastructure
│   │   ├── 00-rbac/                 # ServiceAccounts, Roles
│   │   └── active/
│   │       ├── 01-tasks/            # Task definitions
│   │       ├── 02-pipeline/         # Pipeline definitions
│   │       └── 03-pipelineruns/     # PipelineRun templates
│   ├── vllm/                        # Model serving
│   │   ├── servingruntime-vllm-cuda.yaml
│   │   ├── pvc-mistral-24b.yaml
│   │   ├── inferenceservice-mistral-24b.yaml
│   │   ├── inferenceservice-mistral-24b-quantized.yaml
│   │   ├── virtualservice-*.yaml
│   │   └── destinationrule-*.yaml
│   └── archive/                     # Archived/obsolete resources
└── kustomization.yaml
```

## Next Steps

Once Stage 1 is validated:

1. **Review test results** in Model Registry
2. **Benchmark comparison** between quantized and full models
3. **Proceed to Stage 2** - Model Alignment with RAG + KFP pipelines

## Resources

- [vLLM Documentation](https://docs.vllm.ai/)
- [KServe InferenceService](https://kserve.github.io/website/latest/modelserving/v1beta1/llm/vllm/)
- [Red Hat Model Serving Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.24/html/serving_models/)
- [Tekton Pipelines](https://tekton.dev/docs/pipelines/)
- [Model Registry SDK](https://github.com/kubeflow/model-registry)

---

**Status**: ✅ Production Ready  
**Last Updated**: November 3, 2025  
**Branch**: `stage1-complete`
