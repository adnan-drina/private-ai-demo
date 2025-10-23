# TrustyAI Llama Stack Provider - Evaluation Integration

**Purpose**: Integrate TrustyAI LM-Eval as an evaluation provider in Llama Stack  
**Provider**: `remote::trustyai-lmeval`  
**Source**: [trustyai-explainability/llama-stack-provider-lmeval](https://github.com/trustyai-explainability/llama-stack-provider-lmeval)  
**Status**: 🚧 In Development  

---

## 🎯 Overview

This component deploys the TrustyAI LM-Eval provider as a remote provider for Llama Stack, enabling evaluation capabilities through a unified API.

### Current Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   OpenShift Cluster                     │
│                                                         │
│  ┌──────────────┐        ┌──────────────┐             │
│  │   vLLM       │        │  Llama Stack │             │
│  │   Models     │◄───────│              │             │
│  └──────────────┘        │ • Inference  │             │
│                          │ • Agents     │             │
│  ┌──────────────┐        │ • RAG        │             │
│  │  TrustyAI    │        │ • Safety     │             │
│  │  Operator    │  ← Separate            │             │
│  │  (LMEval)    │        │              │             │
│  └──────────────┘        └──────────────┘             │
└─────────────────────────────────────────────────────────┘
```

### Target Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   OpenShift Cluster                     │
│                                                         │
│  ┌──────────────┐        ┌──────────────────────┐     │
│  │   vLLM       │        │    Llama Stack       │     │
│  │   Models     │◄───────│                      │     │
│  └──────────────┘        │ • Inference          │     │
│                          │ • Agents             │     │
│  ┌──────────────┐        │ • RAG                │     │
│  │  TrustyAI    │◄───────│ • Safety             │     │
│  │  Provider    │        │ • **EVAL** ← NEW!    │     │
│  │  (Remote)    │        │                      │     │
│  └──────────────┘        └──────────────────────┘     │
│         ↓                                              │
│  ┌──────────────┐                                      │
│  │  TrustyAI    │                                      │
│  │  Operator    │  ← Backend for evaluations          │
│  └──────────────┘                                      │
└─────────────────────────────────────────────────────────┘
```

---

## 🏗️ Components

### 1. TrustyAI LM-Eval Provider Deployment

**Container**: `quay.io/trustyai/llama-stack-provider-lmeval:latest`

The provider acts as a bridge between Llama Stack's evaluation API and TrustyAI's LMEvalJob operator.

**Key Features**:
- Implements Llama Stack's `eval` API
- Translates Llama Stack eval requests to TrustyAI LMEvalJob CRs
- Monitors eval job progress
- Returns results via Llama Stack API

### 2. Updated Llama Stack Configuration

Add `eval` API and `trustyai-lmeval` provider to Llama Stack's `run.yaml`.

### 3. RBAC Configuration

Provider needs permissions to:
- Create/read/delete LMEvalJob CRs in `private-ai-demo` namespace
- Read ConfigMaps and Secrets (for model endpoints)
- Watch LMEvalJob status

---

## 📋 Implementation

### Step 1: Deploy TrustyAI Provider

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trustyai-lmeval-provider
  namespace: private-ai-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: trustyai-lmeval-provider
  template:
    metadata:
      labels:
        app: trustyai-lmeval-provider
        app.kubernetes.io/name: trustyai-provider
        app.kubernetes.io/component: evaluation
        app.kubernetes.io/part-of: llama-stack
    spec:
      serviceAccountName: trustyai-provider
      containers:
      - name: provider
        image: quay.io/trustyai/llama-stack-provider-lmeval:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        # TrustyAI Configuration
        - name: TRUSTYAI_LM_EVAL_NAMESPACE
          value: "private-ai-demo"
        - name: TRUSTYAI_LMEVAL_TLS
          value: "false"  # Internal cluster communication
        
        # Model endpoints (from Stage 1)
        - name: VLLM_URL_QUANTIZED
          value: "https://mistral-24b-quantized-private-ai-demo.apps.cluster-qtvt5.qtvt5.sandbox2082.opentlc.com/v1/completions"
        - name: VLLM_URL_FULL
          value: "https://mistral-24b-private-ai-demo.apps.cluster-qtvt5.qtvt5.sandbox2082.opentlc.com/v1/completions"
        
        # HuggingFace token for datasets/tokenizers
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: huggingface-token
              key: HF_TOKEN
        
        # Logging
        - name: LOG_LEVEL
          value: "INFO"
        
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
```

### Step 2: Create Service & Route

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: trustyai-lmeval-provider
  namespace: private-ai-demo
  labels:
    app: trustyai-lmeval-provider
spec:
  selector:
    app: trustyai-lmeval-provider
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  type: ClusterIP
```

### Step 3: Update Llama Stack Configuration

```yaml
# Update gitops/components/llama-stack/configmap.yaml
apis:
  - inference
  - agents
  - safety
  - telemetry
  - tool_runtime
  - vector_io
  - eval  # ← NEW: Enable evaluation API

providers:
  # ... existing providers ...
  
  eval:  # ← NEW: TrustyAI evaluation provider
    - provider_id: trustyai-lmeval
      provider_type: remote::trustyai-lmeval
      config:
        url: "http://trustyai-lmeval-provider.private-ai-demo.svc:8080"
        namespace: "private-ai-demo"
        models:
          - model_id: mistral-24b-quantized
            endpoint: "https://mistral-24b-quantized-private-ai-demo..."
            tokenizer: "RedHatAI/Mistral-Small-24B-Instruct-2501-quantized.w4a16"
          - model_id: mistral-24b-full
            endpoint: "https://mistral-24b-private-ai-demo..."
            tokenizer: "mistralai/Mistral-Small-24B-Instruct-2501"
```

### Step 4: RBAC Configuration

```yaml
# serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: trustyai-provider
  namespace: private-ai-demo

---
# role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: trustyai-provider
  namespace: private-ai-demo
rules:
# LMEvalJob management
- apiGroups: ["trustyai.opendatahub.io"]
  resources: ["lmevaljobs"]
  verbs: ["get", "list", "watch", "create", "delete", "patch"]
- apiGroups: ["trustyai.opendatahub.io"]
  resources: ["lmevaljobs/status"]
  verbs: ["get", "list", "watch"]

# ConfigMap and Secret access
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]

# Pod logs (for debugging)
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list"]

---
# rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: trustyai-provider
  namespace: private-ai-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: trustyai-provider
subjects:
- kind: ServiceAccount
  name: trustyai-provider
  namespace: private-ai-demo
```

---

## 🚀 Usage

### Via Llama Stack Python Client

```python
from llama_stack_client import LlamaStackClient

# Connect to Llama Stack
client = LlamaStackClient(
    base_url="http://llama-stack.private-ai-demo.svc:8321"
)

# Run evaluation through unified API
result = client.eval.evaluate(
    task_config={
        "type": "benchmark",
        "benchmarks": ["arc_easy", "hellaswag", "gsm8k", "truthfulqa_mc2"],
        "num_samples": 100,
        "dataset_path": "huggingface"  # or "custom" for custom datasets
    },
    model="mistral-24b-quantized",
    eval_candidate={
        "type": "model",
        "model": "mistral-24b-quantized"
    }
)

# Access results
print(f"ARC-Easy: {result.metrics['arc_easy']['acc_norm']}")
print(f"HellaSwag: {result.metrics['hellaswag']['acc_norm']}")
print(f"GSM8K: {result.metrics['gsm8k']['exact_match']}")
print(f"TruthfulQA: {result.metrics['truthfulqa_mc2']['acc']}")
```

### Via Llama Stack REST API

```bash
# Trigger evaluation
curl -X POST http://llama-stack.private-ai-demo.svc:8321/eval/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "task_config": {
      "type": "benchmark",
      "benchmarks": ["arc_easy", "hellaswag"],
      "num_samples": 100
    },
    "model": "mistral-24b-quantized"
  }'

# Check status
curl http://llama-stack.private-ai-demo.svc:8321/eval/jobs/{job_id}

# Get results
curl http://llama-stack.private-ai-demo.svc:8321/eval/jobs/{job_id}/results
```

### From Jupyter Notebooks

```python
# stage2-private-data-rag/notebooks/05-unified-evaluation.ipynb

from llama_stack_client import LlamaStackClient
import pandas as pd
import matplotlib.pyplot as plt

# Initialize client
client = LlamaStackClient(base_url="http://llama-stack.private-ai-demo.svc:8321")

# Run evaluations for both models
models = ["mistral-24b-quantized", "mistral-24b-full"]
results = {}

for model in models:
    print(f"Evaluating {model}...")
    result = client.eval.evaluate(
        task_config={
            "type": "benchmark",
            "benchmarks": ["arc_easy", "hellaswag", "gsm8k", "truthfulqa_mc2"],
            "num_samples": 100
        },
        model=model
    )
    results[model] = result

# Compare results
comparison_df = pd.DataFrame({
    'Quantized': [
        results['mistral-24b-quantized'].metrics['arc_easy']['acc_norm'],
        results['mistral-24b-quantized'].metrics['hellaswag']['acc_norm'],
        results['mistral-24b-quantized'].metrics['gsm8k']['exact_match'],
        results['mistral-24b-quantized'].metrics['truthfulqa_mc2']['acc']
    ],
    'Full': [
        results['mistral-24b-full'].metrics['arc_easy']['acc_norm'],
        results['mistral-24b-full'].metrics['hellaswag']['acc_norm'],
        results['mistral-24b-full'].metrics['gsm8k']['exact_match'],
        results['mistral-24b-full'].metrics['truthfulqa_mc2']['acc']
    ]
}, index=['ARC-Easy', 'HellaSwag', 'GSM8K', 'TruthfulQA'])

# Visualize
comparison_df.plot(kind='bar', title='Model Quality Comparison')
plt.ylabel('Accuracy')
plt.show()
```

---

## 🔍 How It Works

### 1. Request Flow

```
User → Llama Stack API → TrustyAI Provider → TrustyAI Operator
                                                      ↓
                                              LMEvalJob CR
                                                      ↓
                                               Eval Pod
                                                      ↓
                                              vLLM Model
```

### 2. Provider Responsibilities

The TrustyAI provider:
1. **Receives** eval request from Llama Stack
2. **Translates** request to LMEvalJob CR
3. **Creates** LMEvalJob in Kubernetes
4. **Monitors** job progress
5. **Extracts** results from LMEvalJob status
6. **Returns** results to Llama Stack

### 3. Job Lifecycle

```yaml
# Provider creates this:
apiVersion: trustyai.opendatahub.io/v1alpha1
kind: LMEvalJob
metadata:
  name: eval-{uuid}
  namespace: private-ai-demo
  labels:
    llama-stack-job-id: {job_id}
spec:
  model: local-completions
  modelArgs:
    - name: base_url
      value: "https://mistral-24b-quantized-.../v1/completions"
  taskList:
    taskNames: ["arc_easy", "hellaswag"]
  limit: "100"

# Provider monitors status:
status:
  state: Running | Complete | Failed
  results: { ... }
```

---

## ✅ Benefits

### 1. Unified API
- ✅ Single endpoint for inference, RAG, agents, **and evaluation**
- ✅ Consistent configuration across all AI operations
- ✅ Easier client integration

### 2. Automation
- ✅ Trigger evals programmatically
- ✅ Integrate with CI/CD pipelines
- ✅ Schedule regular quality checks

### 3. Red Hat Alignment
- ✅ Official Llama Stack provider
- ✅ Uses TrustyAI operator (Red Hat pattern)
- ✅ Follows OpenShift AI best practices

### 4. Extensibility
- ✅ Easy to add custom benchmarks
- ✅ Support for RAG evaluation (Phase 3)
- ✅ Guardrails integration (Phase 4)

---

## 📊 Comparison: Before vs After

| Aspect | Before (Operator Only) | After (Llama Stack Integration) |
|--------|------------------------|----------------------------------|
| **Triggering Evals** | `oc apply -f lmevaljob.yaml` | `client.eval.evaluate(...)` |
| **Checking Status** | `oc get lmevaljob` | `client.eval.get_job_status(id)` |
| **Getting Results** | `oc get lmevaljob -o json` → parse | `result.metrics` (typed) |
| **From Notebooks** | Kubernetes API calls | Native Llama Stack client |
| **From Applications** | Direct Kubernetes client | Llama Stack REST API |
| **Configuration** | Separate YAML files | Unified `run.yaml` |
| **API Consistency** | Different from inference/RAG | Same API as inference/RAG |

---

## 🧪 Testing

### 1. Provider Health Check

```bash
# Check if provider is running
oc get pods -n private-ai-demo -l app=trustyai-lmeval-provider

# Check provider health
curl http://trustyai-lmeval-provider.private-ai-demo.svc:8080/health
```

### 2. Llama Stack Integration Test

```bash
# Check if eval API is available
curl http://llama-stack.private-ai-demo.svc:8321/eval/info

# Expected response:
{
  "provider_id": "trustyai-lmeval",
  "provider_type": "remote::trustyai-lmeval",
  "supported_tasks": ["benchmark", "custom"],
  "supported_models": ["mistral-24b-quantized", "mistral-24b-full"]
}
```

### 3. End-to-End Evaluation Test

```python
# test_eval_integration.py
from llama_stack_client import LlamaStackClient

client = LlamaStackClient(base_url="http://llama-stack.private-ai-demo.svc:8321")

# Run quick test (2 benchmarks, 10 samples each)
result = client.eval.evaluate(
    task_config={
        "type": "benchmark",
        "benchmarks": ["arc_easy", "hellaswag"],
        "num_samples": 10
    },
    model="mistral-24b-quantized"
)

assert result.status == "complete"
assert "arc_easy" in result.metrics
assert "hellaswag" in result.metrics
print("✅ Integration test passed!")
```

---

## 📚 References

### Official Documentation
1. [TrustyAI Llama Stack Provider](https://github.com/trustyai-explainability/llama-stack-provider-lmeval)
2. [Llama Stack Providers Guide](https://llama-stack.readthedocs.io/en/latest/providers/)
3. [Llama Stack Eval API](https://llama-stack.readthedocs.io/en/latest/references/llama_stack_apis/eval/)
4. [Red Hat OpenShift AI - TrustyAI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.22/html-single/monitoring_data_science_models/)

### Internal Documentation
5. `/docs/TRUSTYAI-NEXT-PHASE-PLAN.md` - Overall integration plan
6. `/docs/TRUSTYAI-FULL-EVALUATION-RESULTS.md` - Baseline evaluation results
7. `/gitops/components/trustyai-eval-operator/README.md` - Operator usage

---

## 🚀 Deployment

```bash
# Deploy the provider
oc apply -k gitops/components/trustyai-llama-stack-provider/

# Restart Llama Stack to pick up new configuration
oc rollout restart deployment/llama-stack -n private-ai-demo

# Verify integration
oc logs -n private-ai-demo -l app=llama-stack | grep "eval"
# Should see: "Loaded provider: trustyai-lmeval"
```

---

**Status**: 🚧 **In Development**  
**Next Steps**: 
1. Deploy TrustyAI provider
2. Update Llama Stack configuration
3. Test integration
4. Update notebooks to use Llama Stack eval API
5. Document in demo materials

