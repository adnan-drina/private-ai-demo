# Stage 2: Private Data Enhancement with RAG

Transform generic LLM responses into precise, source-cited answers using Retrieval Augmented Generation (RAG) with Red Hat OpenShift AI and Llama Stack.

## Overview

This stage demonstrates how Red Hat OpenShift AI enables enterprises to enhance LLMs with private data using production-ready RAG architecture. We showcase **3 real-world scenarios** across different industries, all using the same infrastructure but different document corpora.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Stage 1: Mistral 24B                     │
│              (Quantized, deployed via vLLM/KServe)           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                  Stage 2: RAG Components                     │
│                                                              │
│  ┌──────────────┐   ┌──────────────┐   ┌─────────────────┐ │
│  │   Docling    │→  │ Llama Stack  │→  │     Milvus      │ │
│  │  (PDF→Text)  │   │(Orchestrator)│   │ (Vector Store)  │ │
│  └──────────────┘   └──────────────┘   └─────────────────┘ │
│                                                              │
│  Embedding: IBM Granite (768 dimensions)                    │
│  Pipeline: Tekton (automated ingestion)                     │
└─────────────────────────────────────────────────────────────┘
```

**Key Components:**
- **Milvus**: Vector database with IBM Granite 768-dimensional embeddings
- **Llama Stack**: RAG orchestration layer (reuses Stage 1 Mistral model)
- **Docling**: AI-powered PDF processing (headings, tables, citations)
- **Tekton**: Automated document ingestion pipelines
- **JupyterLab**: Interactive demo notebooks

## Demo Scenarios

### 📘 Scenario 1: Red Hat OpenShift AI Documentation

**Industry:** Technology / Enterprise IT  
**Use Case:** Technical documentation Q&A for cloud architects and engineers

**Business Value:**
- Accelerate developer onboarding with accurate, source-cited answers
- Reduce support ticket volume with self-service technical documentation
- Ensure compliance with official Red Hat documentation

**Corpus:**
- Red Hat OpenShift AI RAG Deployment Guide (203 KB PDF)

**Demo Notebook:** `02-rag-demo-redhat.ipynb`

**Key Questions:**
- Hardware/software prerequisites for Llama Stack deployment
- Exact configuration steps for RAG workloads
- Operator dependencies and setup procedures

**README:** [README-redhat.md](./README-redhat.md)

---

### ⚖️ Scenario 2: EU AI Act Regulation

**Industry:** Legal / Compliance / Regulatory  
**Use Case:** Regulatory compliance assistant for AI governance teams

**Business Value:**
- Navigate complex 500+ page regulation with precise citations
- Answer compliance questions with article-level accuracy
- Track implementation timelines across 2025-2027 phasing

**Corpus:**
- EU AI Act Official Journal (Regulation 2024/1689) - 2.6 MB PDF
- European Parliament Research Service Timeline - 1.4 MB PDF
- European Commission Q&A Document - 94 KB PDF
- **Total:** 214 chunks indexed

**Demo Notebook:** `03-rag-demo-eu-ai-act.ipynb`

**Key Questions:**
- High-risk AI system classifications and obligations
- Prohibited AI practices (e.g., social scoring, emotion recognition)
- GPAI (General Purpose AI) obligations and thresholds
- Implementation timelines and deadlines

**Docling Features Showcased:**
- Heading hierarchy preservation
- Table extraction and parsing
- Annex/Article cross-references
- Page-level citations

**README:** [README-eu-ai-act.md](./README-eu-ai-act.md)

---

### 🏭 Scenario 3: ACME LithoOps Copilot

**Industry:** Semiconductor Manufacturing  
**Use Case:** Technical support copilot for lithography operations

**Business Value:**
- Instant access to tool calibration procedures (L-900 EUV)
- Real-time SPC limit checks for PX-7 product line
- Troubleshooting guidance with FMEA-backed recommendations
- Reduce mean time to resolution (MTTR) for production issues

**Corpus (6 Documents):**
1. DFO Calibration SOP (Tool: L-900 EUV) - 13 KB PDF
2. Lithography Control Plan & SPC Limits (PX-7) - 12 KB PDF
3. Tool Health & Predictive Rules (FMEA Extract) - 12 KB PDF
4. Scanner & Metrology Test Recipe Handbook - 12 KB PDF
5. Trouble Response Playbook (Tier-1/Tier-2) - 12 KB PDF
6. Reliability Summary Report Q3 FY25 - 12 KB PDF
- **Total:** 13 chunks indexed

**Demo Notebook:** `04-rag-demo-acme-litho.ipynb`

**Key Questions:**
- Dose/overlay UCL limits for specific product/layer combinations
- DFO calibration procedures for EUV tools
- Troubleshooting steps for overlay drift scenarios
- Tool health monitoring and predictive maintenance rules

**Metadata Schema:**
- Product line, layer, tool model
- SPC limits, calibration steps, FMEA actions
- Troubleshooting procedures with severity levels

**README:** [README-acme.md](./README-acme.md)

---

## Deployment

### Prerequisites

1. **Stage 1 Deployed**: Mistral 24B quantized model running on vLLM
2. **OpenShift AI Installed**: DataScienceCluster with Llama Stack operator
3. **GPU Nodes Available**: For Stage 1 model serving
4. **CLI Tools**: `oc`, `kubectl`

### Quick Start

```bash
cd stage2-private-data-rag
./deploy.sh
```

The script will:
1. Verify Stage 1 deployment
2. Activate Llama Stack operator via DSC patch
3. Deploy shared infrastructure (Milvus, Docling, Llama Stack)
4. Deploy Tekton pipeline components
5. Create JupyterLab workbench with all 3 notebooks
6. Prompt you to select scenarios to deploy (1, 2, 3, or All)

### Scenario Selection

When prompted, you can deploy:
- **Individual scenarios**: Enter `1`, `2`, or `3`
- **Multiple scenarios**: Enter `1,2` or `2,3`
- **All scenarios**: Enter `A` or `all`

Each scenario will:
- Upload documents to PVC (if needed)
- Deploy scenario-specific Tekton tasks
- Run document ingestion pipeline
- Make demo notebook available in workbench

### Access the Demos

1. **Get Workbench URL:**
   ```bash
   oc get route rag-testing -n private-ai-demo
   ```

2. **Open in Browser** (OAuth login required)

3. **Run Notebooks:**
   - `02-rag-demo-redhat.ipynb` - Red Hat documentation
   - `03-rag-demo-eu-ai-act.ipynb` - EU AI Act regulation
   - `04-rag-demo-acme-litho.ipynb` - ACME manufacturing

### Monitor Pipelines

```bash
# List all pipeline runs
oc get pipelinerun -n private-ai-demo

# Monitor specific scenario
oc get pipelinerun -n private-ai-demo | grep redhat
oc get pipelinerun -n private-ai-demo | grep eu-ai-act
oc get pipelinerun -n private-ai-demo | grep acme

# Check pipeline logs
oc logs -n private-ai-demo -l tekton.dev/pipelineRun=<pipeline-run-name>
```

## Red Hat AI Four Pillars Demonstrated

### 1. **Efficient Inferencing** ✅
- Quantized Mistral 24B (4-bit compressed-tensors)
- GPU-optimized vLLM serving
- Cost-effective LLM deployment at scale

### 2. **Simplified Data Connection** ✅
- **Milvus** vector database integration
- **Docling** for intelligent PDF processing
- **Tekton** pipelines for automated ingestion
- Multiple data formats supported (PDFs, text, structured data)

### 3. **Hybrid Cloud Flexibility** ✅
- Deployed on OpenShift (runs anywhere)
- Cloud-agnostic architecture
- GPU and CPU inference options
- Multi-tenancy: `ai-infrastructure` (shared) + `private-ai-demo` (tenant)

### 4. **Agentic AI Delivery** ✅
- **Llama Stack** for RAG orchestration
- Agent-based reasoning with tool calling
- Context-aware responses with citations
- Foundation for Stage 3: MCP Servers & Quarkus AI Agents

## Technical Details

### Embedding Model

**IBM Granite Embedding (768 dimensions)**
- Optimized for enterprise documents
- Better performance on technical/legal text vs. MiniLM
- Aligned with Red Hat's reference architecture

### Vector Database

**Milvus Standalone**
- Collection: `rag_documents`
- Shared across all scenarios
- Metadata filtering for multi-scenario queries

### Document Processing

**Docling Service**
- Async API for large PDFs (>1000 pages)
- Heading hierarchy preservation
- Table extraction
- Cross-reference detection
- Page-level citation tracking

### RAG Orchestration

**Llama Stack Distribution**
- Remote vLLM provider (reuses Stage 1 Mistral model)
- IBM Granite embedding provider
- Milvus vector I/O integration
- Agent API with `builtin::rag/knowledge_search` tool

## GitOps Structure

```
gitops/
├── components/
│   ├── milvus/              # Vector database
│   ├── llama-stack/         # RAG orchestration
│   │   ├── configmap.yaml   # Mistral + IBM Granite config
│   │   └── deployment.yaml
│   ├── docling-pipeline/    # Tekton tasks & pipelines
│   │   ├── task-docling-process-pure-async.yaml
│   │   ├── task-chunk-documents.yaml
│   │   ├── task-ingest-to-milvus.yaml
│   │   ├── pipeline-redhat-ingestion.yaml
│   │   ├── pipeline-rag-ingestion-simple.yaml  # EU AI Act
│   │   └── pipeline-acme-ingestion.yaml
│   └── workbench/           # JupyterLab notebooks
│       └── notebooks/
│           ├── 02-rag-demo-redhat.ipynb
│           ├── 03-rag-demo-eu-ai-act.ipynb
│           └── 04-rag-demo-acme-litho.ipynb
└── overlays/
    ├── milvus/
    ├── llama-stack/
    ├── docling/
    └── workbench/
```

## Troubleshooting

### Llama Stack Not Starting

```bash
# Check operator status
oc get datasciencecluster default-dsc -o yaml | grep llamastack

# Patch DSC to activate
oc patch datasciencecluster default-dsc --type merge \
  --patch '{"spec":{"components":{"llamastack":{"managementState":"Managed"}}}}'

# Check pod logs
oc logs -n private-ai-demo -l app=llama-stack
```

### Pipeline Failures

```bash
# Check task run logs
oc get taskrun -n private-ai-demo
oc logs -n private-ai-demo <taskrun-name>

# Verify Docling service
oc get pods -n ai-infrastructure | grep docling
curl http://shared-docling-service.ai-infrastructure.svc:5001/health
```

### Milvus Connection Issues

```bash
# Check Milvus status
oc get pods -n ai-infrastructure | grep milvus

# Test connectivity from Llama Stack
oc exec -n private-ai-demo -l app=llama-stack -- \
  curl -s http://milvus-standalone.ai-infrastructure.svc:19530
```

## References

- **Red Hat RAG Guide**: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_cloud_service/1/html/working_with_rag
- **Llama Stack Demos**: https://github.com/opendatahub-io/llama-stack-demos
- **Docling**: https://github.com/DS4SD/docling
- **IBM Granite**: https://huggingface.co/ibm-granite/granite-embedding-125m-english
- **Milvus**: https://milvus.io/docs

## Next Steps

- **Stage 3**: MCP Servers & Quarkus AI Agents
  - Build proactive AI agents with Model Context Protocol
  - Integrate RAG into enterprise workflows
  - Deploy serverless AI agents with Quarkus native compilation
