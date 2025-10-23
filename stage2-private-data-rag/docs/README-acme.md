# ACME LithoOps Copilot - RAG Implementation

## Overview

Production-ready RAG system for ACME lithography operations, providing AI-assisted troubleshooting, limit checking, and procedural guidance for semiconductor manufacturing.

**Use Case**: Technical support for lithography engineers working with L-900 EUV tools and PX-7 product.

---

## Architecture

### Stack (Aligned with EU AI Act Project)

**Infrastructure Layer:**
- **LLM**: Mistral-24B-Quantized (from Stage 1)
- **Embedding Model**: IBM Granite Embeddings 125M (768 dimensions)
- **Vector DB**: Milvus (collection: `acme_documents`, dim=768)
- **Orchestration**: Llama Stack (Agents, Vector I/O, Safety)
- **Document Processing**: Docling (AI-powered PDF extraction)
- **Pipeline**: Tekton (automated ingestion workflow)

**Application Layer:**
- **Agent Instructions**: Context-aware for technical queries
- **Retrieval**: Hybrid (BM25 + semantic embeddings)
- **Reranking**: Document-type preference (PLAYBOOK > SPC > SOP > FMEA > RECIPE > REPORT)
- **Citation Format**: `[Doc, §section, p.X]`

---

## Corpus

### Documents (6 PDFs, ~32 pages total)

| Document | Type | Purpose | Key Sections |
|----------|------|---------|--------------|
| ACME_01 | SOP | DFO Calibration for L-900 EUV | §3, §4 calibration steps |
| ACME_02 | SPC | Lithography Control Plan & Limits (PX-7) | §SPC dose/overlay UCLs |
| ACME_03 | FMEA | Tool Health & Predictive Rules (L-900) | §FMEA maintenance rules |
| ACME_04 | RECIPE | Scanner & Metrology Test Recipes | §RECIPE qualification |
| ACME_05 | PLAYBOOK | Trouble Response (Tier 1-2) | §TR troubleshooting steps |
| ACME_06 | REPORT | Reliability Summary Q3 FY25 | §REL uptime metrics |

---

## Metadata Schema

### Extended from EU AI Act Pattern

```json
{
  "doc_name": "ACME_02",
  "doc_type": "SPC",
  "version": "v1.9",
  "section_id": "§SPC-3",
  "page_start": 5,
  "page_end": 5,
  "tool_model": "L-900",
  "product": "PX-7",
  "layer": "M1",
  "parameter": "overlay",
  "ucl_value": 3.5,
  "ucl_unit": "nm",
  "table_id": "Table-2",
  "anchor": "pdf://ACME_02#page=5"
}
```

**Rationale**: Manufacturing context requires tool/product/layer tracking for limit queries.

---

## Milvus Configuration

### Collection Setup

```python
collection_params = {
    "name": "acme_documents",
    "dimension": 768,  # IBM Granite 125M embeddings
    "metric_type": "COSINE",  # Best for normalized embeddings
    "index_type": "IVF_FLAT",  # Trade-off: accuracy vs speed
    "nlist": 128  # 2x sqrt(num_chunks) heuristic
}
```

**Index Choice Rationale:**
- **IVF_FLAT**: Chosen for corpus size (~150-200 chunks expected)
  - Provides good accuracy/speed balance for small-medium corpora
  - Lower memory overhead than HNSW
  - Acceptable latency for interactive queries (<500ms retrieval)
  
**Alternative Considered:**
- **HNSW**: Better for larger corpora (>10K chunks)
  - Higher memory usage
  - Faster queries but unnecessary for our scale
  - Would use if corpus grows >1000 chunks

**Metric Choice:**
- **COSINE**: Standard for normalized embeddings
  - Granite embeddings are L2-normalized
  - Handles magnitude variations better than L2
  - Consistent with EU AI Act implementation

---

## Document Processing Pipeline

### 1. Docling Conversion

**Command (same as EU AI Act):**
```bash
docling convert \
  --from ${PDF_PATH} \
  --to ${OUTPUT_DIR} \
  --format md,json \
  --ocr-engine=easyocr \
  --table-mode=accurate
```

**Post-Processing:**
- Preserve headings (§ notation)
- Extract page numbers
- Normalize section IDs (§SOP-3, §TR-5, etc.)
- Strip base64 images (prevent 65KB Milvus limit)

### 2. Chunking Strategy

**Heading-Aware Chunking:**
- Target: 400-500 tokens per chunk
- Keep tables intact (atomic chunks)
- Preserve decision-tree branches (troubleshooting)
- Overlap: 50 tokens for context continuity

**Deduplication:**
- Cross-reference SOP ↔ SPC overlaps (calibration procedures)
- Merge redundant limit definitions
- Keep highest-authority source (SPC > SOP for limits)

### 3. Metadata Extraction

**From Filename:**
```
ACME_02_PX-7_Lithography_Control_Plan_&_SPC_Limits.pdf
  ↓
  doc_name: ACME_02
  product: PX-7
  doc_type: SPC
```

**From Content:**
- Section IDs: Regex `§[A-Z]+-\d+`
- Tool models: Pattern match `L-\d+`
- Layers: Pattern match `M\d+|V\d+`
- Limits: Extract numeric values + units

### 4. Indexing

**Milvus Operations:**
```python
# Insert chunks with metadata
collection.insert([
    {
        "vector": granite_embedding(chunk_text),
        "text": chunk_text,
        "metadata": json.dumps(metadata_dict)
    }
])

# Build index
collection.create_index(
    field_name="vector",
    index_params={"index_type": "IVF_FLAT", "metric_type": "COSINE", "params": {"nlist": 128}}
)
```

**BM25 Auxiliary Index:**
- Store in `documents/scenario2/index/bm25_index.pkl`
- Use for hybrid retrieval (complement semantic search)
- Helps with exact parameter matches (e.g., "3.5 nm UCL")

---

## Retrieval & Reranking

### Hybrid Retrieval

**Stage 1: Semantic + BM25**
```python
semantic_results = milvus_search(query_embedding, top_k=10)
bm25_results = bm25_search(query_tokens, top_k=10)
combined = merge_with_rrf(semantic_results, bm25_results)
```

**Stage 2: Rerank by Document Type**

**Preference Order:**
1. **PLAYBOOK** (§TR sections) - Troubleshooting queries
2. **SPC** (§SPC sections) - Limit queries
3. **SOP** (§SOP sections) - Procedure queries
4. **FMEA** (§FMEA sections) - Predictive maintenance
5. **RECIPE** (§RECIPE sections) - Test setup
6. **REPORT** (§REL sections) - Historical data

**Rationale**: Mirrors engineer's mental model - check troubleshooting guide first, then limits, then procedures.

---

## Answer Synthesis

### System Prompt (Adapted from EU AI Act)

```
You are an ACME LithoOps technical assistant.
Answer questions using ONLY information from the provided ACME documents.

For limit queries:
- Start with ≤2 sentences answering the question
- Provide 3-6 bullets with numeric comparisons (e.g., "3.8 nm > 3.5 nm UCL")
- Include a "Citations" section mapping each claim to [Doc, §section, p.X]

For troubleshooting queries:
- Start with immediate action
- List diagnostic steps as bullets
- Provide fallback escalation path
- Cite relevant sections

For procedural queries:
- Summarize the procedure
- List key steps
- Note prerequisites and tools
- Cite SOP sections

If information is not in ACME sources, reply: "Not found in ACME sources."
```

### Example Output Format

**Query**: "Is 3.8 nm overlay within spec for PX-7 M1?"

**Answer**:
```
The measured overlay of 3.8 nm EXCEEDS the specification for PX-7 M1 layer.

Key limits:
- Overlay UCL: 3.5 nm [ACME_02, §SPC-3, p.5]
- Measured: 3.8 nm
- Deviation: +0.3 nm (+8.6% over UCL)
- Status: OUT OF SPEC - escalate to Tier 2

Actions:
- Verify metrology calibration
- Check scanner alignment drift
- Review last 10 wafers for trend
- Consult [ACME_05, §TR-7, p.3] for overlay troubleshooting

Citations:
- [ACME_02, §SPC-3, p.5] - PX-7 M1 overlay UCL = 3.5 nm
- [ACME_05, §TR-7, p.3] - Overlay drift troubleshooting playbook
```

---

## Evaluation

### Eval Set (`documents/scenario2/eval/acme_eval_set.json`)

**10 Questions covering:**
- Calibration procedures (ACME_01)
- Limit queries (ACME_02)
- Troubleshooting (ACME_05)
- Predictive maintenance (ACME_03)
- Recipe setup (ACME_04)
- Reliability metrics (ACME_06)
- Multi-document synthesis
- Table extraction
- Negative tests (non-existent tools)

**Target**: ≥75% pass rate (same as EU AI Act)

### Eval Harness

**Run Command:**
```bash
python eval_acme_rag.py \
  --eval-set documents/scenario2/eval/acme_eval_set.json \
  --output documents/scenario2/eval/rag_eval_report.json
```

**Pass Criteria (per question):**
- Retrieved expected documents
- Included required citations
- No hallucination (verified against corpus)
- Numeric values correct (for limit queries)

---

## API Endpoints (Stage 3 Integration)

### 1. General RAG Answer

**Endpoint**: `POST /rag/answer`

**Request**:
```json
{
  "query": "What are the dose limits for PX-7?",
  "filters": {
    "doc_type": "SPC",
    "product": "PX-7"
  }
}
```

**Response**:
```json
{
  "answer_md": "The dose UCL for PX-7 is...",
  "citations": [
    {"doc": "ACME_02", "section": "§SPC-2", "page": 4}
  ],
  "used_chunks": [
    {"text": "...", "score": 0.92, "metadata": {...}}
  ]
}
```

### 2. Limit Query (Specialized)

**Endpoint**: `POST /rag/limits`

**Request**:
```json
{
  "product": "PX-7",
  "layer": "M1"
}
```

**Response**:
```json
{
  "dose_ucl_pct": 3.0,
  "overlay_ucl_nm": 3.5,
  "bf_target_nm": 50.0,
  "bf_tol_nm": 5.0,
  "citations": [
    {"doc": "ACME_02", "section": "§SPC-3", "page": 5}
  ]
}
```

---

## Deployment

### Prerequisites

1. Llama Stack running with Milvus connection
2. Mistral-24B-Quantized model deployed
3. IBM Granite embeddings configured
4. Docling service available

### Ingestion Pipeline

**Tekton Pipeline** (reuse EU AI Act structure):
```bash
oc apply -f gitops/components/docling-pipeline-acme/
```

**Upload Documents**:
```bash
# Upload to PVC
kubectl cp documents/scenario2/pdfs/ \
  private-ai-demo/rag-documents-pvc:/acme/

# Run pipeline
oc create -f gitops/components/docling-pipeline-acme/pipeline-run-acme.yaml
```

---

## Differences from EU AI Act Implementation

| Aspect | EU AI Act | ACME Lithography |
|--------|-----------|------------------|
| **Domain** | Regulatory compliance | Manufacturing operations |
| **Citation Format** | `[OJ p.X, Art.Y]` | `[Doc, §section, p.X]` |
| **Metadata** | Articles, Annexes, Recitals | Tools, Products, Layers, Limits |
| **Answer Style** | Analytical explanation | Action-oriented with numeric checks |
| **Document Types** | Official Journals, Guidelines | SOPs, SPCs, FMEAs, Playbooks |
| **Reranking** | By document authority | By engineer workflow (Playbook-first) |
| **Table Extraction** | Minimal | Critical (limit tables) |

---

## Files Generated

```
documents/scenario2/
├── pdfs/                    # 6 source PDFs (provided)
├── parsed/                  # Docling output (md + json)
├── index/                   # BM25 index (pkl)
├── eval/
│   ├── acme_eval_set.json        # 10 test questions
│   └── rag_eval_report.json      # Evaluation results
├── telemetry/
│   └── acme_run_summary.json     # Metrics for Stage 3
└── reports/                 # Generated reports (Stage 3)
```

---

## Success Criteria

✅ **Milvus Collection**:
- 768-dim vectors (IBM Granite)
- IVF_FLAT index with COSINE metric
- ~150-200 chunks indexed

✅ **Answer Quality**:
- Includes [Doc, §section, p.X] citations
- Numeric limit comparisons for SPC queries
- Action-oriented for troubleshooting

✅ **Evaluation**:
- ≥75% pass rate on eval set
- No hallucination on negative tests
- Correct multi-document synthesis

✅ **Code Structure**:
- Mirrors EU AI Act project organization
- Reuses Tekton pipeline structure
- Documented rationale for all choices

---

## References

- [EU AI Act RAG Implementation](../docs/stage2/RAG-IMPLEMENTATION-SUCCESS.md)
- [Red Hat Llama Stack Demos](https://github.com/opendatahub-io/llama-stack-demos)
- [IBM Granite Embeddings](https://huggingface.co/ibm-granite/granite-embedding-125m-english)
- [Milvus Documentation](https://milvus.io/docs)

---

**Last Updated**: October 8, 2025  
**Status**: Implementation in progress  
**Target**: Production-ready ACME RAG with ≥75% eval pass rate

