# LlamaStack Deployment Blocker - RHOAI 2.25

## Status: BLOCKED by Distribution Build

**Date:** 2025-11-03  
**RHOAI Version:** 2.25  
**Operator Image:** `registry.redhat.io/rhoai/odh-llama-stack-core-rhel9@sha256:86f8d82f589b4044ce9ac30cb62b4611951d2c383e669c8e2dc5bc74e69e6c86`

## Summary

LlamaStack deployment is **impossible** with the current RHOAI 2.25 distribution due to an incomplete build. The operator's default image (`rh-dev` distribution) does not include the `prompts` API module, which is hardcoded as a requirement in the stack initialization logic.

## Root Cause

The `rh-dev` distribution shipped with RHOAI 2.25 has a fundamental incompatibility:

1. **Stack initialization** (hardcoded in `llama_stack/core/stack.py:342`):
   ```python
   await impls[Api.prompts].initialize()
   ```
   Always tries to initialize prompts, regardless of configuration.

2. **Module missing** in the distribution:
   ```
   WARNING: Failed to import module prompts: No module named 'llama_stack.providers.registry.prompts'
   KeyError: <Api.prompts: 'prompts'>
   ```

3. **Cannot be bypassed:**
   - Removing `prompts` from APIs list → Still tries to initialize
   - Using `distribution: {}` → Operator injects the same incomplete image
   - No alternate image available in RHOAI 2.25

## Validation Attempts

### Attempt 1: Remove prompts from configuration
- **Configuration:** Removed `prompts` from `apis` list
- **Result:** ❌ System still tries to initialize prompts (hardcoded)

### Attempt 2: Use operator default image
- **Configuration:** Set `distribution: {}` to let operator inject default
- **Result:** ❌ Operator uses the same `rh-dev` image without prompts module

### Attempt 3: Add prompts API with inline provider
- **Configuration:** Added `prompts` to APIs and `inline::prompts` provider
- **Result:** ❌ Provider registry doesn't include prompts API key

## Recommendation

**✅ Implement Custom RAG Solution (No LlamaStack Dependency)**

All infrastructure is 100% ready:
- ✅ vLLM InferenceServices (quantized + full) - serving successfully
- ✅ Milvus vector database - deployed and healthy
- ✅ Docling document processing - deployed and healthy
- ✅ MinIO object storage - deployed with `llama-files` bucket
- ✅ KFP v2 (DSPA) - deployed and ready
- ✅ Service Mesh - configured with proper mTLS

### Implementation Plan (Custom RAG)

**Phase 1: Document Ingestion (KFP v2 Pipeline)**
- Use Docling to parse PDFs → structured JSON
- Generate embeddings via Granite embedding model
- Store vectors in Milvus
- Store raw files in MinIO

**Phase 2: RAG Query (Python/FastAPI Service)**
- Accept user query
- Generate query embedding
- Retrieve top-k from Milvus
- Build context + prompt
- Call vLLM InferenceService
- Return augmented response

**Phase 3: Agent Orchestration (Optional)**
- LangChain/LangGraph for multi-step reasoning
- Tool integration via Model Context Protocol
- State management in PostgreSQL

## Next Steps

1. ✅ Document blocker (this file)
2. ⏳ Implement KFP ingestion pipeline
3. ⏳ Create RAG query service
4. ⏳ Deploy via GitOps
5. ⏳ Contact Red Hat for LlamaStack distribution roadmap

## References

- RHOAI 2.25 LlamaStack docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_llama_stack/
- Upstream LlamaStack: https://github.com/meta-llama/llama-stack
- ODH Data Processing: https://github.com/opendatahub-io/odh-data-processing
