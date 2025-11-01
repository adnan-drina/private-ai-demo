# Stage 01: Model Serving with vLLM

**Purpose**: Deploy and serve AI models using vLLM inference server on OpenShift AI

---

## 📋 Overview

Stage 01 provides the foundation for serving large language models with high performance:

- **Mistral 24B Quantized** - 1 GPU (g6.4xlarge node)
- **Mistral 24B Full Precision** - 4 GPUs (g6.12xlarge node)
- **GuideLLM Benchmarking** - Performance testing and metrics
- **JupyterLab Workbench** - Interactive notebooks for testing

---

## 🏗️ Components

### 1. Base Infrastructure
- **Namespace**: `private-ai-demo`
- **Secrets**: HuggingFace token for model downloads
- **Resource Quotas**: GPU limits and resource management
- **RBAC**: Service accounts and role bindings

### 2. MinIO Object Storage
- **MinIO Server**: S3-compatible storage for models and artifacts
- **PVC**: Persistent storage for MinIO data (10Gi)
- **Route**: External access to MinIO console
- **Use Cases**:
  - Store downloaded model weights as backup
  - Archive benchmark test results from GuideLLM
  - Store evaluation results from TrustyAI
  - Persist training artifacts and checkpoints
  - S3-compatible API for integration with ML tools

### 3. vLLM Serving
- **ServingRuntime**: vLLM CUDA runtime configuration
- **InferenceServices**: KServe resources for model endpoints
- **PVCs**: Persistent storage for downloaded models

###  Model Loader Jobs
- **download-mistral-24b**: Full precision model download
- **download-mistral-24b-quantized**: Quantized model download

### 4. Benchmarking
- **GuideLLM Jobs**: Performance benchmarking
- **Results PVCs**: Benchmark results storage
- **Registry Integration**: Publish results to Model Registry

### 5. Workbench
- **JupyterLab**: Interactive notebook environment
- **Notebooks**: Benchmark analysis and testing

---

## 🚀 Deployment

### Prerequisites
- OpenShift AI 2.25 installed
- GPU nodes provisioned (g6.4xlarge and g6.12xlarge)
- Model Registry deployed (Stage 00)
- `.env` in repository root with:
  - `HF_TOKEN`
  - `MINIO_ACCESS_KEY`
  - `MINIO_SECRET_KEY`
  - `QUAY_USERNAME`
  - `QUAY_PASSWORD`

### GitOps-First Workflow
1. Ensure Stage 00 ArgoCD applications are healthy (`stage00-*`).
2. Review `gitops/stage01-model-serving/` manifests for desired changes.
3. Run the helper script to create secrets and trigger syncs:
   ```bash
   ./stages/stage1-model-serving/deploy.sh
   ```
4. Monitor ArgoCD:
   ```bash
   oc get applications.argoproj.io -n openshift-gitops stage01-model-serving
   ```

> Secrets are never committed to Git. The helper script reads `.env`, creates
> the required Kubernetes Secrets, and then asks ArgoCD to reconcile the
> Git-managed resources.

---

## 📊 Resources Deployed

| Resource Type | Count | Description |
|---------------|-------|-------------|
| Namespace | 1 | private-ai-demo |
| InferenceService | 2 | Quantized + Full models |
| ServingRuntime | 1 | vLLM CUDA runtime |
| PVC | 5 | Model storage + benchmark results |
| Job | 5 | Model downloads + benchmarks |
| Notebook | 1 | JupyterLab workbench |
| ConfigMap | 3 | Configs and scripts |
| Secret | 1 | HuggingFace token |

---

## 🔍 Verification

### Check InferenceServices
```bash
oc get inferenceservice -n private-ai-demo
```

Expected output:
```
NAME                    URL                                     READY
mistral-24b-quantized   https://mistral-24b-quantized-...      True
mistral-24b             https://mistral-24b-...                True
```

### Check Model Download Progress
```bash
oc get jobs -n private-ai-demo | grep download
oc logs job/download-mistral-24b-quantized -n private-ai-demo
```

### Access Workbench
```bash
oc get notebook -n private-ai-demo
```

---

## 📝 Configuration

### HuggingFace Token
Update the secret before deployment:
```yaml
# base-secrets/secret-huggingface-token.yaml
data:
  token: <base64-encoded-hf-token>
```

### GPU Node Affinity
Models are configured with node affinity:
- **Quantized**: `node.kubernetes.io/instance-type: g6.4xlarge`
- **Full**: `node.kubernetes.io/instance-type: g6.12xlarge`

---

## 🔗 Dependencies

- **Stage 00 (Platform)**: OpenShift AI, GPU Operators, GPU Nodes
- **External**: Model Registry (for benchmark results)

---

## 📚 Related Documentation

- [vLLM Documentation](https://docs.vllm.ai/)
- [KServe Documentation](https://kserve.github.io/website/)
- [OpenShift AI Model Serving](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- [GuideLLM Benchmarking](https://github.com/neuralmagic/guidellm)

---

**Status**: Production Ready ✅  
**Maintained By**: Platform Team  
**Last Updated**: October 23, 2025

