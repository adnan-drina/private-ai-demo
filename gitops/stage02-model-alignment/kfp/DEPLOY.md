# KFP v2 Pipeline Deployment Guide

This document provides reproducible steps for deploying and running KFP v2 pipelines in RHOAI.

## Prerequisites (Automated via GitOps)

All infrastructure is deployed via GitOps:

- ✅ DSPA (DataSciencePipelinesApplication) with dashboard label
- ✅ MinIO object storage for artifacts
- ✅ Milvus vector database
- ✅ LlamaStack for embeddings
- ✅ Docling for document processing

## Pipeline Upload (One-Time Manual Step)

**Why manual?** KFP v2 stores pipelines in DSPA's internal database (not as Kubernetes resources).
This is a one-time operation per pipeline; runs are then fully automatable.

### Steps:

1. **Access RHOAI Dashboard**
   ```
   https://rhods-dashboard-redhat-ods-applications.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com
   ```

2. **Navigate to Project**
   - Go to: Data Science Projects → `private-ai-demo`
   - Click: **Pipelines** tab

3. **Upload Pipeline**
   - Click: **"Upload pipeline"** or **"Import pipeline"**
   - Select file: `artifacts/docling-rag-pipeline.yaml`
   - Pipeline name: `docling-rag-ingestion`
   - Description: `RAG ingestion: Docling → Embeddings → Milvus`
   - Click: **"Upload"**

4. **Verify Upload**
   - Pipeline should appear in the list
   - Status: Ready

**Note**: This step only needs to be done once per pipeline or when the pipeline definition changes.

## Running Pipelines (Fully Reproducible)

Once uploaded, pipeline runs can be automated:

### Option 1: Via RHOAI Dashboard (Manual)

1. In Pipelines tab, find `docling-rag-ingestion`
2. Click **"Create run"**
3. Configure parameters (see "Pipeline Parameters" below)
4. Click **"Start"**

### Option 2: Via Script (Reproducible)

```bash
# Set parameters
PIPELINE_ID=$(oc get ... # query DSPA API for pipeline ID)

# Create run via DSPA API
curl -X POST "https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/apis/v2beta1/runs" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d @run-config.json
```

### Option 3: Via Notebook/Python (Best for Automation)

See: `stages/stage2-model-alignment/kfp/create-run.py`

## Pipeline Parameters

Default values for `docling-rag-ingestion`:

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `input_uri` | `s3://llama-files/sample/rag-mini.pdf` | S3 URI of document to process |
| `docling_url` | `http://docling.private-ai-demo.svc:8080` | Docling service endpoint |
| `embedding_url` | `http://llamastack.private-ai-demo.svc:8321/v1` | LlamaStack embeddings API |
| `embedding_model` | `ibm-granite/granite-embedding-125m-english` | Embedding model name |
| `milvus_uri` | `tcp://milvus-standalone.private-ai-demo.svc.cluster.local:19530` | Milvus connection |
| `milvus_collection` | `rag_documents` | Collection name |
| `embedding_dimension` | `768` | Embedding vector size |
| `chunk_size` | `512` | Text chunk size |
| `min_entities` | `10` | Minimum entities for validation |
| `minio_endpoint` | `minio.model-storage.svc:9000` | MinIO endpoint |
| `aws_access_key_id` | (from secret) | MinIO access key |
| `aws_secret_access_key` | (from secret) | MinIO secret key |

## Troubleshooting

### Pipeline not visible in dashboard
- Verify DSPA has label: `opendatahub.io/dashboard=true`
- Check: `oc get dspa dspa -n private-ai-demo -o yaml`

### Upload fails
- Check DSPA status: `oc get dspa dspa -n private-ai-demo`
- Verify DSPA components: `oc get pods -n private-ai-demo -l app=ds-pipeline-dspa`

### Run fails
- Check task logs: `oc logs -n private-ai-demo <pod-name>`
- Verify service endpoints (Docling, LlamaStack, Milvus, MinIO)

## Files

- **Pipeline Source**: `stages/stage2-model-alignment/kfp/pipeline.py`
- **Compiled YAML**: `artifacts/docling-rag-pipeline.yaml` (upload this)
- **DSPA Config**: `gitops/stage02-model-alignment/kfp/dspa.yaml`
- **This Guide**: `gitops/stage02-model-alignment/kfp/DEPLOY.md`

## Updating Pipelines

When you modify the pipeline code:

1. Recompile:
   ```bash
   source .venv-kfp/bin/activate
   python3 stages/stage2-model-alignment/kfp/pipeline.py
   ```

2. Re-upload `artifacts/docling-rag-pipeline.yaml` via dashboard
   - KFP will create a new pipeline version
   - Previous versions remain available

## Integration with deploy.sh

Add to main `deploy.sh`:

```bash
# Stage 2: KFP Pipeline Setup
echo "📋 KFP Pipeline Setup"
echo "  ✅ DSPA configured via GitOps"
echo "  ✅ Pipeline compiled: artifacts/docling-rag-pipeline.yaml"
echo "  ⚠️  Manual step required:"
echo "      Upload pipeline via RHOAI dashboard (one-time)"
echo "      See: gitops/stage02-model-alignment/kfp/DEPLOY.md"
```

