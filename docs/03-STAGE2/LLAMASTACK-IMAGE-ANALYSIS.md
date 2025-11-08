# LlamaStack Image Analysis - RHOAI 2.25 & Red Hat ET

**Date:** 2025-11-03  
**Status:** Both available images are incomplete

## Images Tested

### 1. RHOAI 2.25 Operator Default
**Image:** `quay.io/opendatahub/llama-stack:odh`  
**Source:** LlamaStack Operator default (when `distribution: {}`)

**Issues:**
- ❌ No `prompts` API support
- ❌ `ValueError: 'prompts' is not a valid Api`
- Cannot be used for RAG workflows requiring prompts

### 2. Red Hat Emerging Technologies  
**Image:** `quay.io/redhat-et/llama:vllm-0.2.7`  
**Source:** User-specified via `distribution.image`

**Issues:**
- ❌ No `prompts` API support (`ValueError: 'prompts' is not a valid Api`)
- ❌ No `files` API providers:
  - `remote::s3-files`: Not available
  - `inline::files`: Not available
- ❌ Missing Python dependencies:
  - `ModuleNotFoundError: No module named 'litellm'`
  - Breaks `remote::openai` provider (needed for Granite embeddings)

## Configuration Tested

### Working Configuration (Core APIs only)
```yaml
apis:
  - inference
  - agents
  - safety
  - telemetry
  - tool_runtime
  - vector_io
  # - files     # NO provider available
  # - prompts   # Not a valid API in these images
```

## Recommendations

### Immediate
**Pivot to Custom RAG Implementation**

All required infrastructure is deployed and healthy:
- vLLM InferenceServices (quantized + full)
- Milvus vector database
- Docling document processing
- MinIO object storage
- KFP v2 (DSPA)
- Service Mesh

### Long-term
**Contact Red Hat for Complete Image**

Questions for Red Hat:
1. What is the recommended LlamaStack image for RHOAI 2.25?
2. Is there a complete image with Files API + Prompts API + litellm?
3. Roadmap for LlamaStack support in RHOAI?

---
**Conclusion:** Neither available image supports complete RAG workflows. Custom implementation recommended.
