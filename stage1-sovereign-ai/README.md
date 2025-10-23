# Stage 1: Sovereign AI - Efficient Inference on Hybrid Cloud

**Duration**: 20 minutes  
**Focus**: Pillar 1 (Efficient Inferencing) + Pillar 3 (Hybrid Cloud Flexibility)

---

## 🚀 Quick Deploy

**Automated deployment**:
```bash
./deploy.sh
```
This script will guide you through the entire deployment interactively.

**OR follow the manual steps below** for step-by-step deployment.

---

## 🎯 What You'll Demonstrate

- **75% GPU cost reduction** through quantization (1 GPU vs 4 GPUs)
- **vLLM as inference engine** (Red Hat AI Inference Server)
- **Complete data sovereignty** (on-premise, cloud, edge, air-gapped)
- **GitOps deployment** (Infrastructure as Code)
- **Production-proven** (Turkish Airlines, AGESIC examples)

---

## ✅ Prerequisites

### Infrastructure
- OpenShift cluster with admin access
- Ability to create MachineSets (or existing GPU nodes)
- Minimum 2 GPU nodes:
  - 1x with 1 GPU (g6.4xlarge or equivalent) for quantized model
  - 1x with 4 GPUs (g6.12xlarge or equivalent) for full model

### Tools
- `oc` CLI configured
- HuggingFace token
- Git (for GitOps)

### Knowledge
- Basic Kubernetes/OpenShift concepts
- Understanding of LLMs and inference

---

## 🚀 Quick Deployment

### Step 1: Create HuggingFace Token Secret

```bash
# Create secret with your HuggingFace token
oc create secret generic huggingface-token \
  --from-literal=token=YOUR_TOKEN_HERE \
  -n private-ai-demo
```

### Step 2: Provision GPU Nodes

```bash
# Set cluster-specific values
export CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
export REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')
export AMI_ID=ami-xxxxx  # Get from your region

# Deploy GPU nodes using component
cd gitops/components/gpu-provisioning
envsubst < g6-4xlarge.yaml | oc apply -f -
envsubst < g6-12xlarge.yaml | oc apply -f -
cd ../../..
```

Wait for nodes to be ready (5-10 minutes):
```bash
watch oc get machines -n openshift-machine-api
watch oc get nodes -l nvidia.com/gpu.present=true
```

### Step 3: Deploy Everything

```bash
# Option A: Deploy production overlay (recommended)
oc apply -k gitops/overlays/production

# Option B: Deploy step-by-step
oc apply -k gitops/base                    # Namespace + vLLM
oc apply -k gitops/components/model-loader # Download models
oc apply -k gitops/components/benchmarking # Benchmarks & registry

# Monitor progress
oc get jobs -n private-ai-demo -w
oc logs job/download-mistral-24b -n private-ai-demo -f
```

### Step 7: Verify Deployment

```bash
# Check InferenceServices
oc get inferenceservice -n private-ai-demo

# Expected output:
# NAME                    READY   URL
# mistral-24b             True    https://...
# mistral-24b-quantized   True    https://...

# Check in OpenShift AI Dashboard
oc get route -n redhat-ods-applications
# Navigate to: Projects → private-ai-demo → Models
```

---

## 🎬 Demo Flow

### 1. Introduction (2 minutes)

**Key Points**:
- AI Platform as Technology Decision Point
- Big 3 challenges: Cost, Complexity, Flexibility
- Today: Pillar 1 (Efficient Inferencing) + Pillar 3 (Hybrid Cloud)

### 2. Architecture Overview (3 minutes)

**Show**:
- GitOps structure
- vLLM as inference engine (Red Hat AI Inference Server)
- OpenShift as deployment platform

**Talking Point**:
> "Everything is code. GPU provisioning to model deployment. Same patterns you use for applications work for AI."

### 3. Live Deployment (5 minutes)

**Navigate to**: OpenShift AI Dashboard

**Show**:
- Both models deployed
- Resource differences (1 GPU vs 4 GPUs)
- Serverless auto-scaling

**Talking Point**:
> "Same model, two versions. Quantized uses 1 GPU. Full uses 4 GPUs. Watch the cost savings..."

### 4. Cost Optimization Proof (5 minutes)

**Show benchmark results**:

| Model | GPUs | Throughput | Cost Factor |
|-------|------|------------|-------------|
| Quantized | 1 | ~19 tok/s | **1x** |
| Full | 4 | ~20 tok/s | **4x** |

**Talking Point**:
> "Less than 5% performance difference. 75% cost reduction. This is production-ready technology."

### 5. Model Registry & GitOps (3 minutes)

**Show**:
- Model Registry with versions
- GitOps repository structure
- Deployment flow (commit → deploy)

**Talking Point**:
> "Version control for models. Audit trail for compliance. Everything automated."

### 6. Conclusion (2 minutes)

**Recap Four Pillars**:
- ✅ Pillar 1: Efficient inference (75% savings)
- ✅ Pillar 3: Hybrid cloud (AGESIC air-gapped, Turkish Airlines hybrid)
- 🔜 Pillar 2: Data connection (Stage 2)
- 🔜 Pillar 4: Agentic AI (Stage 3)

---

## 📊 Benchmark Results

Run benchmarks to generate proof:

```bash
# Benchmarks are included in production overlay
# Or run manually:
oc apply -k gitops/components/benchmarking

# View results
oc logs job/vllm-model-benchmark -n private-ai-demo
```

Expected results:
```
═══════════════════════════════════════════════
BENCHMARK RESULTS - Mistral Models Comparison
═══════════════════════════════════════════════

Quantized Model (1 GPU):
  Short prompts:  20.4 tok/s
  Medium prompts: 19.2 tok/s  
  Long prompts:   19.1 tok/s

Full Model (4 GPUs):
  Short prompts:  21.5 tok/s
  Medium prompts: 20.4 tok/s
  Long prompts:   20.4 tok/s

Cost Savings: 75% (1 GPU vs 4 GPUs)
Performance Impact: <5%
```

---

## 🔍 Verification Checklist

Before presenting:
- [ ] GPU nodes are ready and labeled
- [ ] Both InferenceServices show READY=True
- [ ] Models are registered in Model Registry
- [ ] OpenShift AI Dashboard shows both models
- [ ] Benchmarks have run successfully
- [ ] Test inference endpoints work

Quick test:
```bash
ENDPOINT=$(oc get inferenceservice mistral-24b-quantized -n private-ai-demo -o jsonpath='{.status.url}')
curl -k -X POST "$ENDPOINT/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"mistral-24b-quantized","prompt":"Hello","max_tokens":10}'
```

---

## 🎯 Key Talking Points

### The Cost Message
- "1 GPU vs 4 GPUs = 75% cost reduction"
- "19 vs 20 tokens/sec = <5% performance difference"
- "This scales: 10 models = 10 GPUs vs 40 GPUs saved"

### The Flexibility Message  
- "Same code, different locations"
- "AGESIC runs completely air-gapped for government data"
- "Turkish Airlines runs hybrid: cloud + on-premise"
- "OpenShift anywhere = AI anywhere"

### The Production Message
- "60+ models in production (Turkish Airlines)"
- "180+ government agencies (AGESIC)"
- "Not a prototype—production infrastructure"

---

## 🆘 Troubleshooting

### InferenceService not ready?
```bash
# Check pod status
oc get pods -n private-ai-demo

# Check events
oc get events -n private-ai-demo --sort-by='.lastTimestamp'

# Check InferenceService details
oc describe inferenceservice mistral-24b-quantized -n private-ai-demo
```

### Model download failing?
```bash
# Check HuggingFace token
oc get secret huggingface-token -n private-ai-demo

# Check download job logs
oc logs job/download-mistral-24b-quantized -n private-ai-demo
```

### GPU not available?
```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU operator
oc get pods -n nvidia-gpu-operator
```

---

## 📚 Reference Documentation

- **Full demo script**: [docs/presentations/demo-script.md](../docs/presentations/demo-script.md)
- **Talking points**: [docs/presentations/key-talking-points.md](../docs/presentations/key-talking-points.md)
- **Architecture details**: [docs/reference/COMPLETE-STRUCTURE.md](../docs/reference/COMPLETE-STRUCTURE.md)

---

## ➡️ Next Stage

**Stage 2**: [Private Data Enhancement](../stage2-private-data-rag/README.md)

Add RAG and InstructLab to make models contextually aware of your business data.
