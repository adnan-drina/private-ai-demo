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
- **Kubeflow Pipelines (KFP v2)** - Automated document processing
  - `docling-rag-ingestion` - RAG document ingestion pipeline
    - Download documents from MinIO
    - Process with Docling
    - Generate embeddings with LlamaStack/Granite
    - Store in Milvus vector database
    - Verify ingestion (≥10 entities)

### Demo Notebooks
- **02-rag-demo-redhat.ipynb** - Query Red Hat documentation
- **03-rag-demo-eu-ai-act.ipynb** - Query EU AI Act
- **04-rag-demo-acme-litho.ipynb** - Query ACME policies

## Prerequisites

- **Stage 1** deployed and validated
- Models serving and ready
- Documents in `./documents/` folder for ingestion

## Deployment

Stage 2 follows the same deployment pattern as Stage 1, with **fully automated pipeline management**:

### 1. Deploy Infrastructure

```bash
cd stages/stage2-model-alignment
./deploy.sh
```

This script will:
- Create MinIO bucket for KFP artifacts
- Create secrets (MinIO, LlamaStack)
- Configure SCC permissions
- Enable Service Mesh injection
- Deploy all GitOps resources (DSPA, Milvus, LlamaStack, Docling)
- Compile KFP v2 pipeline → `artifacts/docling-rag-pipeline.yaml`
- **Automatically upload pipeline to DSPA** ✨ (requires `jq`)

### 2. Run RAG Ingestion Pipeline

```bash
# Run with default sample document
./run-rag-ingestion.sh

# Run with custom document
./run-rag-ingestion.sh s3://llama-files/docs/my-document.pdf
```

This script will:
- Check prerequisites (DSPA ready, services running)
- Ensure pipeline is uploaded (idempotent, automatic)
- Create pipeline run via DSPA API with OAuth authentication
- Provide monitoring instructions

> **Note:** `jq` is required for automated pipeline management. Install with:
> - macOS: `brew install jq`
> - RHEL/Fedora: `sudo dnf install jq`
> - Ubuntu: `sudo apt install jq`

### 3. Validate Deployment

```bash
./validate.sh
```

## Verification

Monitor deployment:

```bash
# Check Milvus
oc get deployment milvus-standalone -n private-ai-demo

# Check Llama Stack
oc get llamastackdistribution llama-stack -n private-ai-demo
oc get pods -l app=llama-stack -n private-ai-demo

# Check Docling
oc get deployment docling -n private-ai-demo

# Check DSPA (Data Science Pipelines)
oc get dspa dspa -n private-ai-demo

# List uploaded pipelines (programmatically)
./gitops/stage02-model-alignment/kfp/programmatic-access.sh

# Monitor pipeline runs via RHOAI Dashboard
# Or check run status via API:
DSPA_ROUTE=$(oc get route ds-pipeline-dspa -n private-ai-demo -o jsonpath='{.spec.host}')
curl -sk -H "Authorization: Bearer $(oc whoami -t)" \
  "https://$DSPA_ROUTE/apis/v2beta1/runs" | jq '.runs[] | {name: .display_name, status: .state}'

# Check ingested documents in Milvus
oc exec -it deployment/milvus-standalone -n private-ai-demo -- \
  ls /var/lib/milvus
```

## Document Ingestion

The KFP v2 pipeline (`docling-rag-ingestion`) automatically:
1. Download documents from MinIO S3 storage (`s3://llama-files/`)
2. Process and chunk documents using Docling
3. Generate embeddings using LlamaStack/Granite model
4. Store vectors in Milvus with metadata
5. Verify ingestion (≥10 entities threshold)

### Running the Pipeline

```bash
# Run with default sample document
./run-rag-ingestion.sh

# Run with custom document from MinIO
./run-rag-ingestion.sh s3://llama-files/docs/my-document.pdf
```

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

## Project Structure

```
stages/stage2-model-alignment/
├── deploy.sh              # Main deployment script
├── run-rag-ingestion.sh   # Run RAG pipeline
├── validate.sh            # Validation script
├── kfp/
│   └── pipeline.py        # KFP v2 pipeline definition
└── README.md             # This file

gitops/stage02-model-alignment/
├── milvus/               # Vector database deployment
├── llama-stack/          # LlamaStack orchestrator + CR
├── docling/              # Document processing service
├── kfp/                  # KFP v2 (DSPA) configuration
│   ├── dspa.yaml         # DataSciencePipelinesApplication
│   ├── DEPLOY.md         # Pipeline deployment guide
│   ├── programmatic-access.sh  # OAuth API examples
│   └── example-run-config.json # Run template
└── kustomization.yaml    # Kustomize root

artifacts/
└── docling-rag-pipeline.yaml  # Compiled KFP pipeline (not in git)
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
