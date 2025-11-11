# Red Hat AI Demo - Five-Stage Journey

**Complete demonstration of Red Hat AI's Four Pillars on OpenShift**

---

## 🚀 Overview

This demo showcases Red Hat AI capabilities through five progressive stages, demonstrating sovereignty, flexibility, trust, and integration.

### Demo Stages

0. **Platform Setup** - OpenShift AI 2.25, GPU nodes, Model Registry
1. **Model Serving** - Efficient vLLM inference with benchmarking
2. **Model Alignment** - RAG + Llama Stack orchestration
3. **Model Monitoring** - TrustyAI evaluation + observability
4. **Model Integration** - Agentic workflows with MCP

---

## 📁 Project Structure

```
private-ai-demo/
├── README.md                                           # This file
│
├── gitops-new/                                         # GitOps manifests (Kustomize)
│   ├── argocd/                                         # ArgoCD Applications
│   ├── stage00-ai-platform-rhoai/                     # Stage 0: Platform
│   ├── stage01-model-serving/                          # Stage 1: vLLM
│   ├── stage02-model-alignment/                        # Stage 2: RAG
│   ├── stage03-model-monitoring/                       # Stage 3: TrustyAI
│   └── stage04-model-integration/                      # Stage 4: MCP
│
├── stage0-ai-platform-rhoai/                          # Stage 0 deployment
│   ├── README.md                                       # Platform setup guide
│   ├── deploy.sh                                       # Deploy RHOAI + GPU
│   ├── validate.sh                                     # Validate platform
│   └── env.template                                    # Config template
│
├── stage1-model-serving-with-vllm/                    # Stage 1 deployment
│   ├── README.md                                       # Model serving guide
│   ├── deploy.sh                                       # Deploy models + benchmarks
│   ├── validate.sh                                     # Validate serving
│   └── env.template                                    # HuggingFace token
│
├── stage2-model-alignment-with-rag-and-llama-stack/  # Stage 2 deployment
│   ├── README.md                                       # RAG setup guide
│   ├── deploy.sh                                       # Deploy RAG stack
│   ├── validate.sh                                     # Validate RAG
│   ├── env.template                                    # Config template
│   └── documents/                                      # Documents for ingestion
│
├── stage3-model-monitoring-with-trustyai-.../         # Stage 3 deployment
│   ├── README.md                                       # Monitoring guide
│   ├── deploy.sh                                       # Deploy observability
│   ├── validate.sh                                     # Validate monitoring
│   └── env.template                                    # Config template
│
├── stage4-model-integration-with-mcp-and-llama-stack/ # Stage 4 deployment
│   ├── README.md                                       # Agent guide
│   ├── deploy.sh                                       # Deploy MCP + agent
│   ├── validate.sh                                     # Validate integration
│   ├── env.template                                    # Config template
│   └── documents/                                      # Agent data
│
├── docs/                                               # Documentation
│   └── *.md                                            # Architecture & guides
│
└── scripts/                                            # Utility scripts
    └── cleanup-environment.sh                          # Clean deployment
```

---

## 🎯 Prerequisites

### Required
- **OpenShift Cluster** - 4.16+ with admin access
- **oc CLI** - Configured and logged in
- **HuggingFace Token** - For model downloads
- **GPU Capacity** - AWS g6.4xlarge (1 GPU) + g6.12xlarge (4 GPUs)

### Installed via Stage 0
- OpenShift AI operator 2.25
- GPU Operator
- Model Registry

---

## 🚀 Quick Start

### End-to-End Deployment

```bash
# 1. Login to OpenShift
oc login <cluster-url>

# 2. Stage 0: Platform Setup
cd stage0-ai-platform-rhoai
./deploy.sh
./validate.sh

# 3. Stage 1: Model Serving
cd ../stage1-model-serving-with-vllm
cp env.template .env
# Edit .env and add HF_TOKEN
./deploy.sh
./validate.sh

# 4. Stage 2: Model Alignment (RAG)
cd ../stage2-model-alignment-with-rag-and-llama-stack
./deploy.sh
./validate.sh

# 5. Stage 3: Model Monitoring
cd ../stage3-model-monitoring-with-trustyai-opentelemetry-and-llama-stack
./deploy.sh
./validate.sh

# 6. Stage 4: Model Integration (MCP)
cd ../stage4-model-integration-with-mcp-and-llama-stack
./deploy.sh
./validate.sh
```

### Using ArgoCD (GitOps)

```bash
# Deploy ArgoCD Applications
oc apply -k gitops-new/argocd/

# Monitor sync status
oc get applications -n openshift-gitops
```

---

## 📚 Stage Details

### Stage 0: AI Platform - RHOAI
**Setup foundational infrastructure**

- OpenShift AI 2.25 operator
- DataScienceCluster with Model Registry
- GPU Operator + GPU nodes (g6.4xlarge, g6.12xlarge)
- Model Registry + MySQL backend

📖 [Stage 0 README](stage0-ai-platform-rhoai/README.md)

---

### Stage 1: Model Serving with vLLM
**Efficient inference with benchmarking**

- vLLM ServingRuntime (shared)
- Mistral 24B Quantized (1 GPU, W4A16)
- Mistral 24B Full (4 GPUs, FP16)
- GuideLLM benchmarks + Model Registry integration
- MinIO storage for artifacts
- Benchmark results notebook

**Key Concepts:** GPU optimization, quantization trade-offs, cost efficiency

📖 [Stage 1 README](stage1-model-serving-with-vllm/README.md)

---

### Stage 2: Model Alignment with RAG + Llama Stack
**Enterprise data enhancement**

- Llama Stack orchestrator (central hub)
- Milvus vector database
- Docling + Granite embedding model
- Tekton document ingestion pipelines (3 use cases)
- RAG demonstration notebooks

**Use Cases:**
- Red Hat documentation queries
- EU AI Act compliance questions
- ACME manufacturing procedures

**Key Concepts:** RAG, vector search, document chunking, Llama Stack

📖 [Stage 2 README](stage2-model-alignment-with-rag-and-llama-stack/README.md)

---

### Stage 3: Model Monitoring with TrustyAI + OpenTelemetry + Llama Stack
**Quality assessment and observability**

- TrustyAI LMEvalJobs (4 benchmarks: arc_easy, hellaswag, gsm8k, truthfulqa_mc2)
- Grafana dashboards (performance + quality)
- Prometheus metrics collection
- OpenTelemetry distributed tracing
- Evaluation results notebook

**Key Metrics:**
- Model accuracy and quality scores
- GPU utilization and memory
- TTFT (Time To First Token)
- Throughput and latency

**Key Concepts:** Model evaluation, observability, quality vs performance

📖 [Stage 3 README](stage3-model-monitoring-with-trustyai-opentelemetry-and-llama-stack/README.md)

---

### Stage 4: Model Integration with MCP + Llama Stack
**Enterprise agentic workflows**

- ACME Calibration Agent (Quarkus app)
- PostgreSQL equipment database
- MCP Servers (Database + Slack)
- Llama Stack + RAG integration
- Agent demonstration notebook

**Workflow:**
```
User Query
  ↓
ACME Agent
  ├→ Database MCP (equipment lookup)
  ├→ Llama Stack + RAG (calibration docs)
  ├→ vLLM (expert analysis)
  └→ Slack MCP (team notification)
  ↓
Comprehensive Response
```

**Key Concepts:** MCP protocol, agentic AI, multi-step orchestration

📖 [Stage 4 README](stage4-model-integration-with-mcp-and-llama-stack/README.md)

---

## 🏗️ Red Hat AI Four Pillars

This demo demonstrates all four pillars of Red Hat AI:

### 1️⃣ Flexible Foundation (Stage 1)
- ✅ Multiple model formats (quantized, full precision)
- ✅ Efficient serving (vLLM)
- ✅ GPU optimization and cost efficiency

### 2️⃣ Data & AI Integration (Stage 2)
- ✅ RAG with enterprise data
- ✅ Vector storage and retrieval
- ✅ Automated document ingestion

### 3️⃣ Trust & Governance (Stage 3)
- ✅ Model quality evaluation
- ✅ Continuous monitoring
- ✅ Comprehensive observability

### 4️⃣ Integration & Automation (Stage 4)
- ✅ Agentic workflows
- ✅ Standardized protocols (MCP)
- ✅ Enterprise system integration

---

## 🎓 Demo Audience

### For Technical Teams
- Architecture patterns for AI deployments
- Best practices for GPU optimization
- RAG implementation with Llama Stack
- Observability and monitoring strategies

### For Business Stakeholders
- AI sovereignty and data privacy
- Cost optimization (quantization)
- Quality vs performance trade-offs
- Enterprise AI integration patterns

---

## 🔧 Troubleshooting

### Common Issues

**Models not loading:**
```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check InferenceServices
oc get inferenceservice -n private-ai-demo

# Check pod placement
oc get pods -n private-ai-demo -o wide
```

**RAG not working:**
```bash
# Check Milvus
oc get deployment milvus-standalone -n private-ai-demo

# Check Llama Stack
oc get llamastackdistribution -n private-ai-demo

# Check pipelines
tkn pr list -n private-ai-demo
```

**Monitoring issues:**
```bash
# Check TrustyAI
oc get lmevaljob -n private-ai-demo

# Check Grafana
oc get route grafana -n private-ai-demo
```

---

## 📖 Documentation

### Red Hat Official Docs
- [OpenShift AI 2.25](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25)
- [Serving Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/serving_models/)
- [Monitoring Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/monitoring_data_science_models/)
- [Model Registry](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/managing_model_registries/)

### Open Source Projects
- [vLLM](https://docs.vllm.ai/)
- [Llama Stack](https://llama-stack.readthedocs.io/)
- [Milvus](https://milvus.io/docs)
- [TrustyAI](https://trustyai-explainability.github.io/)
- [Model Context Protocol](https://modelcontextprotocol.io/)

### Community Resources
- [Red Hat AI Services GitHub](https://github.com/rh-aiservices-bu/)
- [Llama Stack Demos](https://github.com/opendatahub-io/llama-stack-demos)
- [rhoai-mlops Examples](https://github.com/rhoai-mlops/)

---

## 🧹 Cleanup

To remove all components:

```bash
# Delete namespace (removes all deployed resources)
oc delete project private-ai-demo

# Or use cleanup script
./scripts/cleanup-environment.sh
```

---

## 📝 License

This demo project is provided as-is for demonstration and educational purposes.

---

## 🤝 Contributing

This is a demonstration project. For production deployments, please refer to official Red Hat documentation and work with Red Hat support.

---

## 📧 Support

For issues or questions:
- Review stage-specific README files
- Check docs/ folder for detailed guides
- Consult Red Hat OpenShift AI documentation
- Contact Red Hat support for production use

---

**Built with ❤️ demonstrating Red Hat AI capabilities**
