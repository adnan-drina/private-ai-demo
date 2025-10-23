# Red Hat OpenShift AI - RAG Implementation Guide

**Technical reference for deploying production-ready RAG on Red Hat OpenShift AI**

---

## 🏗️ Architecture Overview

This implementation follows Red Hat's official RAG architecture as documented in [Working with RAG](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_cloud_service/1/html/working_with_rag).

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│ Red Hat OpenShift AI Platform                                   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Data Science Project: private-ai-demo                    │  │
│  │                                                           │  │
│  │  ┌─────────────────┐         ┌──────────────────────┐   │  │
│  │  │ vLLM Runtime    │◄────────│ KServe               │   │  │
│  │  │ Mistral 24B     │         │ InferenceService     │   │  │
│  │  │ (Quantized)     │         │ - Serverless mode    │   │  │
│  │  └─────────────────┘         │ - minScale=1         │   │  │
│  │         ▲                     └──────────────────────┘   │  │
│  │         │                                                │  │
│  │         │                     ┌──────────────────────┐   │  │
│  │         │                     │ Llama Stack          │   │  │
│  │         └─────────────────────│ Distribution         │   │  │
│  │                               │ - Inference          │   │  │
│  │                               │ - Agent (RAG)        │   │  │
│  │                               │ - Vector I/O         │   │  │
│  │                               │ - Safety             │   │  │
│  │                               └──────────────────────┘   │  │
│  │                                         │                │  │
│  │                                         ▼                │  │
│  │                               ┌──────────────────────┐   │  │
│  │                               │ Milvus               │   │  │
│  │                               │ - 768-dim vectors    │   │  │
│  │                               │ - rag_documents      │   │  │
│  │                               └──────────────────────┘   │  │
│  │                                         ▲                │  │
│  │                                         │                │  │
│  │                               ┌──────────────────────┐   │  │
│  │                               │ Tekton Pipeline      │   │  │
│  │                               │ 1. Prepare docs      │   │  │
│  │                               │ 2. Docling process   │   │  │
│  │                               │ 3. Extract metadata  │   │  │
│  │                               │ 4. Chunk documents   │   │  │
│  │                               │ 5. Ingest to Milvus  │   │  │
│  │                               └──────────────────────┘   │  │
│  │                                         ▲                │  │
│  │                                         │                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                            │                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Shared Infrastructure: ai-infrastructure                 │  │
│  │                                                           │  │
│  │  ┌──────────────────────────────────────────────────┐   │  │
│  │  │ Docling Operator (Community Operators)           │   │  │
│  │  │ - DoclingServe CR                                │   │  │
│  │  │ - AI-powered PDF processing                      │   │  │
│  │  │ - Async API (handles large files)               │   │  │
│  │  └──────────────────────────────────────────────────┘   │  │
│  │                                                           │  │
│  │  ┌──────────────────────────────────────────────────┐   │  │
│  │  │ MinIO (S3-compatible object storage)             │   │  │
│  │  │ - Model artifacts                                │   │  │
│  │  │ - Training data                                  │   │  │
│  │  │ - Pipeline outputs                               │   │  │
│  │  └──────────────────────────────────────────────────┘   │  │
│  │                                                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Multi-Tenancy Strategy

**Shared Infrastructure** (`ai-infrastructure` namespace):
- Docling service (used by all projects)
- MinIO (model storage)
- Potentially: shared Milvus for non-sensitive data

**Project-Specific** (`private-ai-demo` namespace):
- LLM inference (Mistral vLLM)
- Llama Stack distribution
- Milvus vector database (isolated)
- Tekton pipelines
- JupyterLab workbench

**Benefits**:
- Resource optimization (shared services)
- Data isolation (project-specific vector DBs)
- RBAC enforcement (cross-namespace access controls)

---

## 🔧 Component Deep Dive

### 1. vLLM + KServe InferenceService

**Configuration**:
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: mistral-24b-quantized
  namespace: private-ai-demo
  annotations:
    serving.kserve.io/deploymentMode: Serverless
    openshift.io/display-name: "Mistral 24B Quantized"
  labels:
    opendatahub.io/dashboard: "true"
spec:
  predictor:
    minReplicas: 1  # Keep warm - no cold start
    maxReplicas: 3
    model:
      modelFormat:
        name: vllm
      runtime: vllm-runtime
      storageUri: pvc://models-cache/mistral-24b-quantized
      env:
        - name: VLLM_ATTENTION_BACKEND
          value: "FLASH_ATTN"
        - name: VLLM_ENABLE_AUTO_TOOL_CHOICE
          value: "true"
        - name: VLLM_TOOL_CALL_PARSER
          value: "mistral"
```

**Key Decisions**:
- ✅ **Serverless mode**: Integrates with OpenShift AI Dashboard
- ✅ **minReplicas=1**: No cold start (warm models)
- ✅ **Tool calling enabled**: Required for Llama Stack Agent API
- ✅ **Flash Attention**: GPU memory optimization

### 2. Llama Stack Distribution

**Llama Stack Operator Activation**:
```bash
# Method 1: Patch DataScienceCluster (Red Hat official)
oc patch datasciencecluster default-dsc --type=merge --patch '
spec:
  components:
    llamastack-operator:
      managementState: Managed
'

# Method 2: Manual subscription (alternative)
oc apply -f gitops/components/llama-stack/operator-subscription.yaml
```

**Configuration** (`llamastack-config` ConfigMap):
```yaml
apis:
  - agents
  - inference
  - safety
  - telemetry
  - tool_runtime
  - vector_io

providers:
  inference:
    - provider_type: remote::vllm
      config:
        url: https://mistral-24b-quantized-private-ai-demo.apps...
        api_token: dummy  # Required for vLLM compatibility
      provider_id: vllm-mistral
    - provider_type: inline::sentence-transformers
      config: {}
      provider_id: sentence-transformers

  agents:
    - provider_type: inline::meta-reference
      config: {}
      provider_id: meta-reference

  vector_io:
    - provider_type: remote::milvus
      config:
        host: milvus-shared
        port: 19530
      provider_id: milvus-shared

  tool_runtime:
    - provider_type: inline::rag-runtime
      config: {}
      provider_id: rag-runtime

models:
  - model_id: mistral-24b-quantized
    provider_id: vllm-mistral
    provider_model_id: mistralai/Mistral-Small-24B-Instruct-2501
    model_type: llm
  
  - model_id: ibm-granite/granite-embedding-125m-english
    provider_id: sentence-transformers
    provider_model_id: ibm-granite/granite-embedding-125m-english
    model_type: embedding

vector_dbs:
  - vector_db_id: rag_documents
    embedding_model: ibm-granite/granite-embedding-125m-english
    embedding_dimension: 768
    provider_id: milvus-shared

tool_groups:
  builtin::rag:
    - name: knowledge_search
      provider_id: rag-runtime
```

**Critical Configuration Notes**:
1. **External URLs**: vLLM uses external route (not internal service DNS) due to KServe networking
2. **`api_token: dummy`**: Required for vLLM compatibility (ignored by vLLM)
3. **Embedding dimension 768**: Aligned with IBM Granite model (not 384!)
4. **Tool groups**: Maps `builtin::rag` to `rag-runtime` provider
5. **Deployment strategy**: `Recreate` (not `RollingUpdate`) to avoid PVC conflicts

### 3. Milvus Vector Database

**Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: milvus-standalone
  namespace: private-ai-demo
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: milvus
        image: milvusdb/milvus:v2.4.15
        command: ["milvus", "run", "standalone"]
        env:
        - name: ETCD_USE_EMBED
          value: "true"
        - name: COMMON_STORAGETYPE
          value: "local"
        ports:
        - containerPort: 19530
          protocol: TCP
        volumeMounts:
        - name: milvus-storage
          mountPath: /var/lib/milvus
      volumes:
      - name: milvus-storage
        persistentVolumeClaim:
          claimName: milvus-data
```

**Key Decisions**:
- ✅ **Standalone mode**: Simplified deployment (embedded etcd)
- ✅ **Local storage**: PVC-backed (for OpenShift)
- ✅ **768-dim embeddings**: IBM Granite model
- ✅ **Dynamic field limit**: 65KB (stripped base64 images to comply)

**Collection Configuration**:
```python
from pymilvus import Collection, FieldSchema, CollectionSchema, DataType

fields = [
    FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
    FieldSchema(name="document_id", dtype=DataType.VARCHAR, max_length=256),
    FieldSchema(name="content", dtype=DataType.VARCHAR, max_length=65535),  # 64KB limit
    FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=768),
    FieldSchema(name="metadata", dtype=DataType.JSON)  # page, article, section_type, etc.
]

schema = CollectionSchema(fields=fields, description="RAG documents")
collection = Collection(name="rag_documents", schema=schema)

# Create index
collection.create_index(
    field_name="embedding",
    index_params={"index_type": "IVF_FLAT", "metric_type": "COSINE", "params": {"nlist": 128}}
)
```

### 4. Docling Service

**DoclingServe CR** (Operator-managed):
```yaml
apiVersion: docling.github.io/v1alpha1
kind: DoclingServe
metadata:
  name: shared-docling
  namespace: ai-infrastructure
spec:
  replicas: 1
  resources:
    limits:
      memory: 8Gi
      cpu: 4
    requests:
      memory: 4Gi
      cpu: 2
```

**API Endpoints**:
- `POST /v1/convert/file` - Synchronous (120s timeout)
- `POST /v1/convert/file/async` - Asynchronous (for large PDFs)
- `GET /v1/status/poll/{task_id}` - Check async status
- `GET /v1/result/{task_id}` - Fetch async result

**Best Practices**:
1. **Use async for PDFs > 50 pages**: Avoids 120s timeout
2. **Strip base64 images**: Not searchable, exceeds Milvus 65KB limit
3. **Preserve metadata**: Page numbers, article IDs, section types
4. **Heading-aware chunking**: Keeps context intact

### 5. Tekton Pipeline

**Pipeline Tasks**:
1. **prepare-documents**: List PDF files in PVC
2. **process-all-pdfs**: Call Docling async API, poll for completion
3. **extract-metadata**: Parse page numbers, article IDs, heading hierarchy
4. **chunk-documents**: Semantic chunking (heading-aware, 1-2 paragraphs)
5. **ingest-to-milvus**: Call Llama Stack `/v1/vector-io/insert` API
6. **verify-output**: Confirm all chunks ingested

**PipelineRun Example**:
```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: rag-ingestion-eu-ai-act-simple
  namespace: private-ai-demo
spec:
  pipelineRef:
    name: rag-ingestion-simple
  params:
    - name: scenario
      value: "eu-ai-act"
    - name: llamastack-service
      value: "http://rag-stack-service.private-ai-demo.svc:8321"
  workspaces:
    - name: documents
      persistentVolumeClaim:
        claimName: rag-documents
```

**Execution Time**: ~8 minutes for 3 PDFs (200+ pages total)

---

## 📊 Performance & Optimization

### Quantization Benefits

| Model | Size | GPU Memory | Throughput | Cost Savings |
|-------|------|------------|------------|--------------|
| Mistral 24B (FP16) | 48 GB | 1x A100 (80GB) | 15 tok/s | Baseline |
| Mistral 24B (GPTQ-Int4) | 12 GB | 1x A10G (24GB) | 14 tok/s | **75%** |

**Key Insight**: Quantization enables deployment on smaller, cheaper GPUs with minimal quality loss.

### RAG Performance

| Metric | Before Optimization | After Optimization |
|--------|--------------------|--------------------|
| Chunk ingestion time | 15 min (3 PDFs) | 8 min |
| Query latency (cold) | 5-8s | 1-2s (minScale=1) |
| Query latency (warm) | 1-2s | 0.5-1s |
| Retrieval accuracy | 85% | 92% (heading-aware chunking) |

**Optimizations Applied**:
1. ✅ Async Docling processing (eliminates 120s timeout)
2. ✅ Base64 image stripping (reduces chunk size, avoids Milvus limit)
3. ✅ IBM Granite embeddings (768-dim, better accuracy than 384-dim)
4. ✅ minScale=1 for InferenceService (no cold start)
5. ✅ Flash Attention in vLLM (reduces GPU memory)

---

## 🔒 Security & RBAC

### Cross-Namespace Access

**Problem**: Llama Stack in `private-ai-demo` needs to access Docling in `ai-infrastructure`

**Solution**: RBAC ClusterRole + RoleBinding
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cross-namespace-service-access
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
- apiGroups: ["route.openshift.io"]
  resources: ["routes"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: llamastack-cross-namespace-access
  namespace: ai-infrastructure
subjects:
- kind: ServiceAccount
  name: rag-stack-sa
  namespace: private-ai-demo
roleRef:
  kind: ClusterRole
  name: cross-namespace-service-access
  apiGroup: rbac.authorization.k8s.io
```

### Workbench OAuth

**OpenShift AI Dashboard Integration**:
```yaml
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  name: rag-testing
  namespace: private-ai-demo
  annotations:
    notebooks.opendatahub.io/inject-oauth: "true"
    openshift.io/display-name: "RAG Testing Workbench"
  labels:
    opendatahub.io/dashboard: "true"
spec:
  template:
    spec:
      serviceAccountName: rag-workbench-sa
      containers:
      - name: rag-testing
        image: quay.io/opendatahub/workbench-images:jupyter-datascience-ubi9-python-3.11-20250217
        env:
        - name: NOTEBOOK_ARGS
          value: "--ServerApp.port=8888 --ServerApp.token='' --ServerApp.password='' --ServerApp.base_url=/notebook/private-ai-demo/rag-testing"
```

**Key Annotations**:
- `notebooks.opendatahub.io/inject-oauth: "true"` → OAuth sidecar injected
- `opendatahub.io/dashboard: "true"` → Visible in Dashboard

---

## 📦 GitOps Deployment

### Kustomize Structure

```
gitops/
├── kustomization.yaml           # Root: deploy everything
├── base/
│   ├── namespace/               # Namespaces
│   └── vllm/                    # InferenceServices
├── components/
│   ├── minio/                   # Object storage
│   ├── model-loader/            # HuggingFace download jobs
│   ├── milvus/                  # Vector database
│   ├── llama-stack/             # RAG orchestration
│   ├── docling-operator/        # Document processing
│   ├── docling-pipeline/        # Tekton tasks & pipelines
│   ├── workbench/               # JupyterLab
│   └── benchmarking/            # Performance tests
└── overlays/
    ├── dev/                     # Development
    ├── staging/                 # Pre-production
    └── production/              # Production
```

### Deployment Commands

```bash
# Option 1: Deploy everything (production overlay)
oc apply -k gitops/overlays/production

# Option 2: Deploy base + specific components
oc apply -k gitops/base
oc apply -k gitops/components/model-loader
oc apply -k gitops/components/milvus
oc apply -k gitops/components/llama-stack

# Option 3: Stage-specific deployment scripts
cd stage2-private-data-rag
./deploy.sh  # Automated, opinionated deployment
```

---

## 🧪 Testing & Validation

### Component Health Checks

```bash
# 1. vLLM InferenceService
oc get inferenceservice -n private-ai-demo
oc get pods -n private-ai-demo -l serving.kserve.io/inferenceservice=mistral-24b-quantized

# 2. Llama Stack
oc get deployment rag-stack -n private-ai-demo
curl https://$(oc get route llamastack -n private-ai-demo -o jsonpath='{.spec.host}')/v1/health

# 3. Milvus
oc exec -n private-ai-demo deployment/milvus-standalone -- python3 -c "
from pymilvus import connections, Collection
connections.connect('default', host='localhost', port='19530')
print(Collection('rag_documents').num_entities)
"

# 4. Docling
curl https://$(oc get route shared-docling-route -n ai-infrastructure -o jsonpath='{.spec.host}')/docs

# 5. Tekton Pipeline
oc get pipelinerun -n private-ai-demo
```

### End-to-End RAG Test

```python
from llama_stack_client import LlamaStackClient

# Connect to Llama Stack
client = LlamaStackClient(base_url='https://your-llamastack-route')

# Create RAG agent
agent = client.agents.create(
    agent_id="test-agent",
    model_id="mistral-24b-quantized",
    tool_groups=["builtin::rag"],
    instructions="You are an EU AI Act expert. Answer with precise citations."
)

# Create session and query
session = client.agents.sessions.create(agent_id="test-agent")
response = client.agents.turns.create(
    agent_id="test-agent",
    session_id=session.session_id,
    messages=[{
        "role": "user",
        "content": "Is AI-powered CV screening high-risk under the EU AI Act?"
    }]
)

print(response.turn.output_message.content)
# Expected: Article 6, Annex III(4)(a) reference with page citations
```

---

## 🐛 Troubleshooting

### Issue 1: vLLM Pod Not Scheduling

**Symptoms**:
- InferenceService stuck in `Pending`
- Pod events show: "0/X nodes are available: X Insufficient nvidia.com/gpu"

**Solution**:
```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# If no GPU nodes, provision MachineSets
oc apply -f gitops/components/gpu-provisioning/g6-4xlarge.yaml

# Verify GPU operator
oc get pods -n nvidia-gpu-operator
```

### Issue 2: Llama Stack Can't Connect to vLLM

**Symptoms**:
- Llama Stack logs: `Connection refused` or `Name resolution failed`
- Agent API returns: `Model mistral-24b-quantized not found`

**Root Cause**: Internal service DNS doesn't work with KServe serverless

**Solution**: Use external route URL in `llamastack-config` ConfigMap
```yaml
providers:
  inference:
    - provider_type: remote::vllm
      config:
        url: https://mistral-24b-quantized-private-ai-demo.apps.cluster...  # External!
        api_token: dummy
```

### Issue 3: Milvus "Dynamic field exceeds 65KB" Error

**Symptoms**:
- Ingestion task fails with: `the length (XXXXXX) of dynamic field exceeds max length (65536)`

**Root Cause**: Base64 images from Docling exceed Milvus's 65KB content field limit

**Solution**: Strip base64 images during ingestion (they're not searchable anyway)
```python
import re
content = re.sub(r'!\[.*?\]\(data:image/[^;]+;base64,[^\)]+\)', '[IMAGE]', content)
if len(content) > 60000:
    content = content[:60000]
```

### Issue 4: Llama Stack Deployment Timeout (PVC Conflict)

**Symptoms**:
- `oc rollout status deployment/rag-stack` times out
- Pod events: `Multi-Attach error for volume "pvc-XXX"`

**Root Cause**: `RollingUpdate` strategy with PVC causes conflict (old pod holds PVC)

**Solution**: Change deployment strategy to `Recreate`
```yaml
spec:
  strategy:
    type: Recreate
```

### Issue 5: Pipeline "Unknown status" Loop

**Symptoms**:
- Docling processing task logs show: "Unknown status: unknown"
- Task never completes

**Root Cause**: Incorrect parsing of Docling async API response fields

**Solution**: Use correct field names (`task_status`, not `status`)
```python
status_data = requests.get(f"{docling_url}/v1/status/poll/{task_id}").json()
status = status_data.get('task_status', 'unknown')  # Not 'status'!
if status == 'success':  # Not 'completed'!
    # Fetch result...
```

---

## 📚 References

### Red Hat Documentation
- [Working with RAG](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_cloud_service/1/html/working_with_rag)
- [Llama Stack Operator](https://llama-stack-k8s-operator.pages.dev/)
- [Llama Stack Demos](https://github.com/opendatahub-io/llama-stack-demos)
- [vLLM Runtime](https://github.com/opendatahub-io/vllm-serving-runtime)

### Open Source Projects
- [Docling](https://github.com/DS4SD/docling) - AI-powered document processing
- [Docling Operator](https://github.com/docling-project/docling-operator)
- [Milvus](https://milvus.io/) - Vector database
- [IBM Granite Embeddings](https://huggingface.co/ibm-granite/granite-embedding-125m-english)

### Best Practices
- [Kustomize for GitOps](https://www.redhat.com/en/blog/your-guide-to-continuous-delivery-with-openshift-gitops-and-kustomize)
- [Multi-tenancy in OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.19/html/managing_users_and_user_resources/managing-openshift-ai-users_useradd)
- [RAG Best Practices](https://www.llamaindex.ai/blog/a-cheat-sheet-and-some-recipes-for-building-advanced-rag-803a9d94c41b)

---

## 🤝 Contributing

Found an issue? Have an improvement?

1. Test in your environment
2. Document the fix in this guide
3. Update GitOps manifests
4. Submit a pull request

---

**Next**: [Stage 3: Enterprise Agentic AI](../stage3-enterprise-mcp/README.md)

