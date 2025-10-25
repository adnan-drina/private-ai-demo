# ModelCar Pipeline - End-to-End MLOps for vLLM

This directory contains a complete Tekton-based CI/CD pipeline for building, packaging, and deploying AI models as "ModelCar" containers with vLLM serving.

## 📋 Overview

The **ModelCar Pipeline** automates the entire model lifecycle:

1. **Download**: Fetches models from HuggingFace
2. **Package**: Builds OCI container images (ModelCar pattern)
3. **Push**: Stores in OpenShift internal registry (ImageStream) + Quay.io
4. **Register**: Creates entries in OpenShift AI Model Registry
5. **Deploy**: Launches vLLM InferenceServices with proper GPU configuration

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ModelCar Pipeline Flow                          │
└─────────────────────────────────────────────────────────────────────┘

HuggingFace                   OpenShift                        Quay.io
     │                            │                               │
     │  ┌─────────────────────────┼────────────────────────┐     │
     │  │  1. prepare-context     │                        │     │
     ├──┤  Download model         │                        │     │
     │  └─────────────────────────┼────────────────────────┘     │
     │                            │                               │
     │  ┌─────────────────────────┼────────────────────────┐     │
     │  │  2. build-and-push      │                        │     │
     │  │  Kaniko (no Docker)     ├─► ImageStream         │     │
     │  └─────────────────────────┼────────────────────────┘     │
     │                            │                               │
     │  ┌─────────────────────────┼────────────────────────┐     │
     │  │  3. mirror-to-quay      │                        │     │
     │  │  Skopeo copy            ├────────────────────────┼──┐  │
     │  └─────────────────────────┼────────────────────────┘  │  │
     │                            │                            │  │
     │  ┌─────────────────────────┼────────────────────────┐  │  │
     │  │  4. register-model      │                        │  ├──┤
     │  │  Model Registry API     │  v1alpha3 REST API     │  │  │
     │  └─────────────────────────┼────────────────────────┘  │  │
     │                            │                            │  │
     │  ┌─────────────────────────┼────────────────────────┐  │  │
     │  │  5. deploy-vllm         │                        │  │  │
     │  │  InferenceService       ◄────────────────────────┘  │  │
     │  │  with GPU affinity      │  (uses Quay image)        │  │
     │  └─────────────────────────┼────────────────────────┘  │  │
     │                            │                            │  │
     └────────────────────────────┼────────────────────────────┘  │
                                  │                               │
                            ┌─────▼────────┐            ┌────────▼────┐
                            │ vLLM Service │            │ Quay.io     │
                            │ Ready!       │            │ ModelCar    │
                            └──────────────┘            └─────────────┘
```

## 📁 Directory Structure

```
pipelines/
├── 00-namespace-resources/     # ServiceAccount, RBAC
│   ├── serviceaccount.yaml     # model-pipeline-sa
│   ├── role.yaml               # Permissions for registry, InferenceService
│   └── rolebinding.yaml        # Bind roles to SA
├── 01-tasks/                   # Reusable Tekton tasks
│   ├── clustertask-kaniko-build.yaml        # OCI image builder
│   ├── task-prepare-modelcar.yaml           # HuggingFace download + Containerfile
│   ├── task-mirror-to-quay.yaml             # Skopeo mirroring
│   ├── task-register-model.yaml             # Model Registry v1alpha3 API
│   └── task-deploy-vllm.yaml                # KServe InferenceService
├── 02-pipeline/                # Main pipeline
│   └── pipeline-model-deployment.yaml       # Orchestrates all tasks
└── 03-runs/                    # PipelineRun templates
    ├── pipelinerun-mistral-quantized.yaml   # 1 GPU, g6.4xlarge
    └── pipelinerun-mistral-full.yaml        # 4 GPUs, g6.12xlarge
```

## 🔐 Prerequisites

### 1. Secrets

Ensure your `.env` file contains:

```bash
# Required
HF_TOKEN=hf_xxxxxxxxxxxxx          # HuggingFace token for model downloads
QUAY_USERNAME=your-quay-user       # Quay.io username or robot account
QUAY_PASSWORD=your-quay-password   # Quay.io password or token
QUAY_ORGANIZATION=your-org         # Quay.io organization name

# Optional (auto-detected)
MODEL_REGISTRY_URL=https://model-registry-service-rhoai-model-registries.apps.<cluster>/api/model_registry/v1alpha3
```

### 2. OpenShift Components

- OpenShift Pipelines (Tekton) operator installed
- OpenShift AI with Model Registry
- GPU nodes (g6.4xlarge and g6.12xlarge) provisioned
- vLLM ServingRuntime available

### 3. Cluster Permissions

- Registry editor (for ImageStream push)
- Image pusher/puller (for internal registry)
- InferenceService management (for KServe)

## 🚀 Quick Start

### Option A: Deploy with deploy.sh

The easiest way is to use the Stage 1 deployment script:

```bash
cd stages/stage1-model-serving
./deploy.sh
```

This will:
1. Create all necessary secrets
2. Deploy pipeline infrastructure
3. Offer to run pipelines interactively

### Option B: Manual Deployment

```bash
# 1. Deploy infrastructure
oc apply -k gitops/stage01-model-serving/imagestreams
oc apply -k gitops/stage01-model-serving/workspaces
oc apply -k gitops/stage01-model-serving/pipelines

# 2. Create secrets
oc create secret generic huggingface-token \
  --from-literal=token=$HF_TOKEN \
  -n private-ai-demo

oc create secret generic quay-push \
  --from-literal=QUAY_USERNAME=$QUAY_USERNAME \
  --from-literal=QUAY_PASSWORD=$QUAY_PASSWORD \
  -n private-ai-demo

# 3. Run pipeline (update QUAY_ORG_PLACEHOLDER first)
sed "s/QUAY_ORG_PLACEHOLDER/your-org/g" \
  gitops/stage01-model-serving/pipelines/03-runs/pipelinerun-mistral-quantized.yaml | \
  oc create -f -
```

## 📊 Monitoring Pipeline Runs

### View all PipelineRuns

```bash
oc get pipelineruns -n private-ai-demo
```

### Watch PipelineRun progress

```bash
# Using tkn CLI (recommended)
tkn pipelinerun logs -f -L -n private-ai-demo

# Or using oc
oc get pipelineruns -n private-ai-demo -w
```

### View specific PipelineRun logs

```bash
tkn pipelinerun logs <pipelinerun-name> -n private-ai-demo -f
```

### Check task status

```bash
tkn taskrun list -n private-ai-demo
```

## 🎯 Pipeline Parameters

### Mistral 24B Quantized (w4a16)

| Parameter | Value | Description |
|-----------|-------|-------------|
| `hf_repo` | `RedHatAI/Mistral-Small-24B-Instruct-2501-quantized.w4a16` | HuggingFace model |
| `gpu_count` | `1` | Single GPU |
| `memory_request` | `32Gi` | RAM requirement |
| `node_selector_label` | `node.kubernetes.io/instance-type=g6.4xlarge` | AWS instance type |
| `tensor_parallel_size` | `1` | No parallelism |
| **Estimated time** | **~30 minutes** | Download + Build + Deploy |

### Mistral 24B Full Precision

| Parameter | Value | Description |
|-----------|-------|-------------|
| `hf_repo` | `mistralai/Mistral-Small-24B-Instruct-2501` | HuggingFace model |
| `gpu_count` | `4` | Four GPUs |
| `memory_request` | `96Gi` | RAM requirement |
| `node_selector_label` | `node.kubernetes.io/instance-type=g6.12xlarge` | AWS instance type |
| `tensor_parallel_size` | `4` | 4-way parallelism |
| **Estimated time** | **~60 minutes** | Download + Build + Deploy |

## 🔍 Pipeline Tasks Explained

### Task 1: prepare-modelcar-context

**Purpose**: Creates the build context for the ModelCar image

**What it does**:
- Generates a Python script to download from HuggingFace
- Creates a multi-stage Containerfile:
  - Stage 1: Downloads model using `huggingface-hub`
  - Stage 2: Packages model in minimal UBI image
- Uses Red Hat UBI base images

**Output**: Build context in shared workspace

---

### Task 2: build-and-push (Kaniko)

**Purpose**: Builds OCI image without Docker daemon

**What it does**:
- Uses Kaniko for rootless container builds
- Passes `HF_REPO` as build arg
- Pushes to OpenShift internal registry
- Creates ImageStreamTag automatically

**Why Kaniko**:
- No Docker daemon required
- Secure (rootless)
- OCI-compliant
- Works with ImageStreams

**Output**: Image in `image-registry.openshift-image-registry.svc:5000/private-ai-demo/mistral-24b-quantized:w4a16-2501`

---

### Task 3: mirror-to-quay

**Purpose**: Mirror image to external Quay.io registry

**What it does**:
- Uses Skopeo for efficient image copying
- Authenticates with Quay credentials
- Copies all layers and manifests
- Verifies successful push

**Why Quay**:
- External backup
- Easier sharing
- CI/CD integration
- Image scanning

**Output**: Image in `quay.io/<org>/mistral-24b-quantized:w4a16-2501`

---

### Task 4: register-model

**Purpose**: Register model in OpenShift AI Model Registry

**What it does**:
- Uses Model Registry v1alpha3 REST API
- Creates/finds RegisteredModel
- Creates new ModelVersion
- Points to OCI image URI (`oci://quay.io/...`)
- Adds metadata (format, source, deployment type)

**Benefits**:
- Model governance
- Version tracking
- Lineage and provenance
- Integration with OpenShift AI dashboard

**Output**: Model visible in Model Registry dashboard

---

### Task 5: deploy-vllm

**Purpose**: Deploy model as KServe InferenceService

**What it does**:
- Creates InferenceService manifest
- Sets GPU count and memory
- Configures node selector for proper GPU instance
- Sets vLLM args (tensor parallelism, memory utilization)
- Waits for `Ready` condition (up to 10 minutes)

**Configuration**:
```yaml
spec:
  predictor:
    model:
      runtime: vllm-nvidia-gpu
      storageUri: oci://quay.io/<org>/model:tag
      args:
        - --model=/models
        - --tensor-parallel-size=1  # or 4 for full model
        - --disable-custom-all-reduce
        - --max-model-len=4096
        - --gpu-memory-utilization=0.9
      resources:
        limits:
          nvidia.com/gpu: "1"  # or "4"
```

**Output**: Running vLLM service with endpoint URL

## 🛠️ Troubleshooting

### Pipeline fails at prepare-context

**Symptom**: Task fails with HuggingFace authentication error

**Solution**:
```bash
# Check HuggingFace token secret
oc get secret huggingface-token -n private-ai-demo -o yaml

# Verify token has correct permissions at https://huggingface.co/settings/tokens
```

---

### Pipeline fails at build-and-push

**Symptom**: Kaniko fails with "unauthorized" or "forbidden"

**Solution**:
```bash
# Check ServiceAccount has registry permissions
oc policy add-role-to-user registry-editor -z model-pipeline-sa -n private-ai-demo
oc policy add-role-to-user system:image-pusher -z model-pipeline-sa -n private-ai-demo

# Verify ImageStream exists
oc get imagestream -n private-ai-demo
```

---

### Pipeline fails at mirror-to-quay

**Symptom**: Skopeo authentication failure

**Solution**:
```bash
# Check Quay credentials
oc get secret quay-push -n private-ai-demo -o yaml

# Test Quay authentication manually
skopeo login quay.io -u $QUAY_USERNAME -p $QUAY_PASSWORD

# Verify Quay repository exists and is accessible
```

---

### Pipeline fails at register-model

**Symptom**: Model Registry API connection error

**Solution**:
```bash
# Check Model Registry route
oc get route model-registry-service -n rhoai-model-registries

# Verify Model Registry config secret
oc get secret model-registry-config -n private-ai-demo -o yaml

# Test API endpoint
curl -k https://model-registry-service-rhoai-model-registries.apps.<cluster>/api/model_registry/v1alpha3/registered_models
```

---

### Pipeline fails at deploy-vllm

**Symptom**: InferenceService stuck in "Not Ready"

**Solution**:
```bash
# Check InferenceService status
oc get inferenceservice -n private-ai-demo
oc describe inferenceservice mistral-24b-quantized -n private-ai-demo

# Check predictor pod
oc get pods -n private-ai-demo | grep predictor
oc logs <predictor-pod> -n private-ai-demo

# Common issues:
# - GPU node not available → check MachineSets
# - Image pull error → verify Quay image is accessible
# - OOM error → increase memory limits
```

## 📈 Performance Characteristics

### Workspace Storage

- **PVC Size**: 100Gi
- **Access Mode**: ReadWriteOnce
- **Purpose**: Cache HuggingFace downloads between pipeline runs
- **Benefit**: Subsequent runs are much faster (~5-10 minutes vs 30-60 minutes)

### Build Times

| Phase | Quantized | Full | Notes |
|-------|-----------|------|-------|
| Download | ~15 min | ~40 min | Depends on network speed |
| Build | ~5 min | ~10 min | Kaniko build time |
| Push (Internal) | ~2 min | ~5 min | To ImageStream |
| Mirror (Quay) | ~3 min | ~8 min | To Quay.io |
| Register | <1 min | <1 min | API calls |
| Deploy | ~5-10 min | ~10-15 min | vLLM startup |
| **Total** | **~30 min** | **~75 min** | First run |
| **Total (cached)** | **~15 min** | **~35 min** | Subsequent runs |

## 🎯 Best Practices

### 1. Use PVC Workspace for Caching

The pipeline uses a 100Gi PVC to cache HuggingFace downloads. This dramatically speeds up subsequent pipeline runs.

### 2. Run Pipelines Sequentially

Both models are large. Running them in parallel can:
- Exhaust cluster resources
- Cause OOM errors
- Slow down both pipelines

### 3. Monitor GPU Node Availability

Before running pipelines, ensure GPU nodes are available:

```bash
oc get nodes -l node.kubernetes.io/instance-type=g6.4xlarge
oc get nodes -l node.kubernetes.io/instance-type=g6.12xlarge
```

### 4. Use Private Quay Repositories

For production, use private Quay repositories and configure pull secrets:

```bash
oc create secret docker-registry quay-pull-secret \
  --docker-server=quay.io \
  --docker-username=$QUAY_USERNAME \
  --docker-password=$QUAY_PASSWORD \
  -n private-ai-demo
```

Then update InferenceService to use the pull secret.

### 5. Set Resource Limits

Always set appropriate resource limits to prevent:
- OOM kills
- Resource starvation
- Node instability

## 🔗 References

- [Tekton Documentation](https://tekton.dev/docs/)
- [Kaniko Project](https://github.com/GoogleContainerTools/kaniko)
- [Skopeo](https://github.com/containers/skopeo)
- [KServe Documentation](https://kserve.github.io/website/)
- [vLLM Documentation](https://docs.vllm.ai/)
- [OpenShift AI Model Registry](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [Red Hat OpenShift Pipelines](https://docs.openshift.com/pipelines/)

## 📝 License

This pipeline implementation follows Red Hat best practices and is designed for use with:
- Red Hat OpenShift Container Platform
- Red Hat OpenShift AI
- Red Hat OpenShift Pipelines

---

**Created**: October 24, 2025  
**Version**: 1.0  
**Part of**: Private AI Demo - Stage 1 (Model Serving)

