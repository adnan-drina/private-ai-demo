# Stage 2: Model Alignment with RAG + Llama Stack

## Overview

Stage 2 demonstrates how to enhance LLM responses with private enterprise data using Retrieval-Augmented Generation (RAG). This stage integrates Llama Stack as the central orchestrator, Milvus for vector storage, and Tekton for automated document ingestion pipelines.

## Components

### RAG Infrastructure
- **Milvus** - Vector database for embeddings (50Gi PVC)
- **Granite Embedding Model** - `granite-embedding-125m-english`
- **Docling** - Document processing and chunking pipeline

### Orchestration
- **Llama Stack Distribution** - Central orchestrator
  - Inference provider: vLLM (from Stage 1)
  - Memory provider: Milvus
  - Telemetry: OpenTelemetry + Prometheus

### Document Ingestion
- **Tekton Pipelines** - Automated document processing
  - `redhat-document-ingestion` - Red Hat product docs
  - `eu-ai-act-ingestion` - EU AI Act regulations
  - `acme-policies-ingestion` - ACME manufacturing policies

### Demo Notebooks
- **02-rag-demo-redhat.ipynb** - Query Red Hat documentation
- **03-rag-demo-eu-ai-act.ipynb** - Query EU AI Act
- **04-rag-demo-acme-litho.ipynb** - Query ACME policies

## Prerequisites

- **Stage 1** deployed and validated
- Models serving and ready
- Documents in `./documents/` folder for ingestion

## Deployment

```bash
# Deploy all Stage 2 components
./deploy.sh

# Validate deployment
./validate.sh
```

## Verification

Monitor deployment:

```bash
# Check Milvus
oc get deployment milvus-standalone -n private-ai-demo

# Check Llama Stack
oc get llamastackdistribution -n private-ai-demo
oc get deployment llama-stack -n private-ai-demo

# Check Tekton pipelines
tkn pipeline list -n private-ai-demo

# Monitor pipeline runs
tkn pr list -n private-ai-demo
tkn pr logs -f <pipelinerun-name> -n private-ai-demo

# Check ingested documents in Milvus
oc exec -it deployment/milvus-standalone -n private-ai-demo -- \
  ls /var/lib/milvus
```

## Document Ingestion

The Tekton pipelines automatically:
1. Read documents from PVC/ConfigMaps
2. Process and chunk documents using Docling
3. Generate embeddings using Granite model
4. Store vectors in Milvus with metadata

### Use Cases

**Red Hat Documentation**
- Product documentation
- Best practices
- Installation guides

**EU AI Act**
- Regulatory compliance
- AI governance
- Risk assessment

**ACME Manufacturing**
- Calibration procedures
- Equipment specifications
- Quality standards

## RAG Query Flow

```
User Query
    ↓
Llama Stack Orchestrator
    ↓
1. Generate query embedding (Granite)
2. Vector similarity search (Milvus)
3. Retrieve top-k relevant chunks
4. Build augmented prompt
    ↓
5. Generate response (vLLM + Mistral)
    ↓
Enhanced Response with Citations
```

## Testing RAG

Access the notebooks in OpenShift AI dashboard:

```bash
# Get workbench route
oc get route rag-testing -n private-ai-demo

# Or use Llama Stack API directly
LLAMA_STACK_URL=$(oc get route llama-stack -n private-ai-demo -o jsonpath='{.spec.host}')

curl -k https://${LLAMA_STACK_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-24b-quantized",
    "messages": [{"role": "user", "content": "What is OpenShift AI?"}]
  }'
```

## Troubleshooting

### Milvus Not Starting
- Check PVC: `oc get pvc milvus-data -n private-ai-demo`
- Check logs: `oc logs deployment/milvus-standalone -n private-ai-demo`
- Verify storage class supports RWO

### Pipeline Runs Failing
- Check task logs: `tkn pr logs <pipelinerun> -n private-ai-demo`
- Verify Docling deployment: `oc get deployment docling -n private-ai-demo`
- Check embedding model: `oc get inferenceservice granite-embedding -n ai-infrastructure`

### Llama Stack Not Connecting
- Check LlamaStackDistribution: `oc describe llamastackdistribution -n private-ai-demo`
- Verify vLLM services: `oc get svc -n private-ai-demo | grep mistral`
- Check Milvus service: `oc get svc milvus-standalone -n private-ai-demo`

### Poor RAG Results
- Verify documents were ingested: Check Milvus collection count
- Tune similarity threshold in Llama Stack config
- Adjust chunk size/overlap in pipeline parameters
- Use more powerful embedding model

## GitOps Structure

```
gitops-new/stage02-model-alignment/
├── milvus/            # Vector database
├── llama-stack/       # Orchestrator + LlamaStackDistribution CR
├── docling/           # Document processing
├── pipelines/         # Tekton Tasks, Pipelines, PipelineRuns
└── notebooks/         # RAG demo notebooks (3)
```

## Next Steps

Once Stage 2 is validated:
1. Test all three RAG use cases in notebooks
2. Verify document retrieval quality
3. Proceed to **Stage 3: Model Monitoring with TrustyAI**

## Documentation

- [Llama Stack Documentation](https://llama-stack.readthedocs.io/)
- [Milvus Documentation](https://milvus.io/docs)
- [Red Hat Llama Stack Guide](https://developers.redhat.com/articles/2025/03/15/llama-stack-demos)
- [Tekton Pipelines](https://tekton.dev/docs/)
