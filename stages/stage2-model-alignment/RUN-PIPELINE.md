# Running the RAG Pipeline (Fully Reproducible)

## Prerequisites

1. Stage 0 (AI Platform) and Stage 1 (Model Serving) deployed
2. Stage 2 components deployed (Docling, LlamaStack, Milvus, etc.)
3. `.env` file at project root with MinIO credentials
4. Test document uploaded to MinIO: `s3://llama-files/sample/test-document.txt`

## Quick Start

```bash
cd stages/stage2-model-alignment

# Upload pipeline and create run (100% reproducible)
./upload-and-run.sh
```

This script:
- ✅ Uploads pipeline to DSPA programmatically
- ✅ Creates experiment
- ✅ Creates and starts pipeline run
- ✅ Monitors execution
- ✅ Fully reproducible - no manual steps

## What It Does

1. **Reads configuration** from `.env` and cluster
2. **Updates pipeline defaults** with current MinIO credentials
3. **Uploads pipeline** via KFP v1beta1 API
4. **Creates run** with all parameters
5. **Monitors execution** for 60 seconds
6. **Provides dashboard link** for detailed monitoring

## Pipeline Flow

```
Download from MinIO
    ↓
Process with Docling
    ↓
Generate Embeddings (Granite)
    ↓
Insert via LlamaStack Vector IO API
    ↓
Verify Ingestion
```

## Validation

After pipeline completes successfully:

1. Open LlamaStack Playground:
   ```
   https://llama-stack-playground-private-ai-demo.apps.<cluster-domain>
   ```

2. Test RAG query:
   ```
   What are ACME quality standards?
   ```

3. Verify context appears and response references the document

## Troubleshooting

### MinIO File Access Error

**Symptom:** Pipeline fails with "403 Forbidden" or "Access Denied"

**Cause:** Test file not accessible in MinIO

**Fix:**
1. Port-forward to MinIO Console:
   ```bash
   oc port-forward -n model-storage svc/minio 19001:9001
   ```

2. Open: http://localhost:19001
   - Login with credentials from `.env`

3. Upload test file to: `llama-files/sample/test-document.txt`

4. Re-run: `./upload-and-run.sh`

### API Timeout

**Symptom:** Script hangs or times out during upload/run creation

**Cause:** KFP API latency in cluster

**Note:** The run may still be created successfully despite timeout.

**Check:**
```bash
# List recent runs
oc get pods -n private-ai-demo --sort-by=.metadata.creationTimestamp | tail -10
```

## Files

- `upload-and-run.sh` - Main execution script ✅
- `kfp/pipeline.py` - Pipeline definition
- `kfp/kfp-api-helpers.sh` - KFP API utilities
- `../../artifacts/docling-rag-pipeline-ascii.yaml` - Compiled pipeline

## Reference

- Pipeline follows Red Hat RHOAI 2.25 best practices
- Uses KFP v2 (DSPA) with v1beta1 run API
- Integrates with LlamaStack Vector IO API
- Fully GitOps-compatible
