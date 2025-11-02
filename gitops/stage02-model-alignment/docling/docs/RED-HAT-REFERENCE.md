# Docling Integration: Red Hat Reference Implementation Analysis

**Source:** [github.com/opendatahub-io/odh-data-processing](https://github.com/opendatahub-io/odh-data-processing)  
**Purpose:** Official Red Hat/OpenDataHub reference for Docling integration with KFP  
**Date Analyzed:** 2025-11-02

---

## 🔍 Key Findings

### Repository Structure

```
odh-data-processing/
├── kubeflow-pipelines/
│   ├── common/                    # Shared components
│   │   ├── constants.py           # Base images, common configs
│   │   ├── import_pdfs.py         # PDF import component
│   │   ├── create_pdf_splits.py   # Parallel processing splits
│   │   └── download_docling_models.py  # Model downloader
│   ├── docling-standard/          # Standard Docling pipeline
│   │   ├── Containerfile          # Base image definition
│   │   ├── standard_components.py # KFP components
│   │   ├── standard_convert_pipeline.py  # Pipeline definition
│   │   └── standard_convert_pipeline_compiled.yaml  # Compiled YAML
│   └── docling-vlm/               # Vision-Language Model variant
├── notebooks/                     # Tutorial and use-case notebooks
├── custom-workbench-image/        # Workbench image builder
└── scripts/                       # Utility scripts
```

---

## ✅ Red Hat Best Practices (from reference repo)

### 1. **KFP Component Structure**

Red Hat uses **KFP v2 components** with the `@dsl.component` decorator:

```python
from kfp import dsl

@dsl.component(
    base_image="quay.io/fabianofranz/docling-ubi9:2.54.0",
)
def docling_convert_standard(
    input_path: dsl.Input[dsl.Artifact],
    artifacts_path: dsl.Input[dsl.Artifact],
    output_path: dsl.Output[dsl.Artifact],
    pdf_filenames: List[str],
    pdf_backend: str = "dlparse_v4",
    image_export_mode: str = "embedded",
    # ... more parameters
):
    """Convert PDF files to JSON/Markdown using Docling"""
    from docling.document_converter import DocumentConverter
    # ... implementation
```

**Key Points:**
- Uses official Docling base image with all dependencies
- Proper artifact passing between components
- Type hints for inputs/outputs
- Comprehensive parameter configuration

### 2. **Base Image (Containerfile)**

```dockerfile
FROM quay.io/sclorg/python-311-c9s:c9s

USER 0
RUN dnf -y install tesseract tesseract-langpack-eng leptonica-devel libglvnd-glx
# ... more system deps

USER 1001
WORKDIR /opt/app-root/src

# Install Docling with CPU-only torch (smaller, faster)
RUN pip install docling --extra-index-url https://download.pytorch.org/whl/cpu

# Pre-download Docling models into image
RUN docling-tools models download layout tableformer -o "${DOCLING_ARTIFACTS_PATH}"
```

**Key Features:**
- ✅ Runs as non-root (USER 1001)
- ✅ Pre-installs all Docling models (faster pipeline execution)
- ✅ CPU-only PyTorch (smaller image, no GPU needed)
- ✅ UBI9-based (Red Hat supported)
- ✅ Tesseract OCR pre-configured

### 3. **Pipeline Architecture**

```python
@dsl.pipeline(
    name="data-processing-docling-standard-pipeline",
    description="Docling standard convert pipeline"
)
def convert_pipeline(
    num_splits: int = 3,
    pdf_from_s3: bool = False,
    pdf_filenames: str = "...",
    # ... docling parameters
):
    # 1. Import PDFs (from HTTP or S3)
    importer = import_pdfs(filenames=pdf_filenames, ...)
    
    # 2. Split for parallel processing
    pdf_splits = create_pdf_splits(
        input_path=importer.outputs["output_path"],
        num_splits=num_splits
    )
    
    # 3. Download Docling models (cached)
    artifacts = download_docling_models(pipeline_type="standard")
    
    # 4. Parallel conversion
    with dsl.ParallelFor(pdf_splits.output) as pdf_split:
        converter = docling_convert_standard(
            input_path=importer.outputs["output_path"],
            artifacts_path=artifacts.outputs["output_path"],
            pdf_filenames=pdf_split,
            # ... parameters
        )
```

**Key Features:**
- ✅ Parallel processing with `dsl.ParallelFor`
- ✅ Model caching (download once, reuse)
- ✅ Artifact-based data passing
- ✅ S3 and HTTP source support
- ✅ Configurable parallelism (`num_splits`)

### 4. **Common Components (Reusable)**

| Component | Purpose | Key Features |
|-----------|---------|--------------|
| `import_pdfs` | Fetch PDFs from HTTP or S3 | Secret mounting, S3 credentials |
| `create_pdf_splits` | Split file list for parallel processing | Dynamic parallelism |
| `download_docling_models` | Download/cache Docling models | HuggingFace Hub, caching |
| `docling_convert_standard` | PDF → Markdown/JSON conversion | Full Docling configuration |

---

## 📊 Comparison: Red Hat vs Our Current Implementation

| Aspect | Red Hat Reference | Our Current Implementation |
|--------|-------------------|---------------------------|
| **Deployment Model** | KFP components only | Standalone REST API Deployment |
| **Base Image** | Pre-built with Docling + models | Runtime pip install |
| **Execution Context** | KFP pipeline tasks | FastAPI service |
| **Model Storage** | Baked into image | Downloaded at runtime |
| **Parallelism** | Native KFP ParallelFor | Not applicable (API service) |
| **Integration** | Direct artifact passing | HTTP API calls |
| **Resource Efficiency** | High (models pre-cached) | Medium (install on start) |
| **Use Case** | Batch document processing | On-demand conversion |

---

## 🎯 Recommendations

### Short Term: Keep Both Approaches

**Our REST API Deployment:**
- ✅ Good for: Ad-hoc document conversion
- ✅ Good for: External integrations
- ✅ Good for: LlamaStack integration
- ✅ Keep as-is for now

**Red Hat KFP Components:**
- ✅ Good for: Batch document processing
- ✅ Good for: RAG ingestion pipelines
- ✅ Good for: Parallel processing at scale
- ✅ **Adopt for Stage 2 KFP pipelines**

### Medium Term: Adopt Red Hat Pattern for KFP

**1. Use Red Hat's Docling Base Image**
```yaml
# In our KFP components
base_image: "quay.io/fabianofranz/docling-ubi9:2.54.0"
```

**2. Create Our Own KFP Components**

Based on Red Hat reference, but customized for our RAG workflow:

```python
# stages/stage2-model-alignment/kfp/components/docling_convert.py
from kfp import dsl

@dsl.component(
    base_image="quay.io/fabianofranz/docling-ubi9:2.54.0"
)
def docling_convert_for_rag(
    input_path: dsl.Input[dsl.Artifact],
    output_path: dsl.Output[dsl.Artifact],
    pdf_filenames: List[str],
    output_format: str = "markdown",  # For RAG chunking
):
    """Convert PDFs to Markdown for RAG ingestion"""
    from docling.document_converter import DocumentConverter
    # ... implementation
```

**3. Integrate with Our RAG Pipeline**

```python
# stages/stage2-model-alignment/kfp/pipeline.py
@dsl.pipeline(name="rag-ingestion-pipeline")
def rag_pipeline(documents: str):
    # Use Red Hat pattern for document processing
    converted = docling_convert_for_rag(pdf_filenames=documents)
    
    # Our existing components
    chunked = chunk_documents(input_path=converted.outputs["output_path"])
    embedded = embed_chunks(chunks=chunked.output)
    indexed = ingest_to_milvus(embeddings=embedded.output)
```

---

## 🔧 Implementation Plan

### Phase 1: Analyze & Document ✅ COMPLETE
- [x] Clone Red Hat reference repo
- [x] Analyze component structure
- [x] Document findings
- [x] Compare with our implementation

### Phase 2: Create Hybrid Approach (Recommended)
- [ ] Keep REST API for ad-hoc use
- [ ] Create KFP components using Red Hat base image
- [ ] Reuse Red Hat common components (import_pdfs, etc.)
- [ ] Integrate into our RAG pipeline

### Phase 3: Production Optimization
- [ ] Build our own Docling base image (with custom models)
- [ ] Add monitoring and observability
- [ ] Create end-to-end RAG demo
- [ ] Performance tuning and scaling

---

## 📦 Red Hat Base Image Details

**Image:** `quay.io/fabianofranz/docling-ubi9:2.54.0`

**Includes:**
- UBI9 Python 3.11
- Docling 2.54.0
- Tesseract OCR with English models
- Pre-downloaded Docling models (layout, tableformer)
- PyTorch (CPU-only for smaller size)
- All system dependencies

**Size:** ~2.5GB (much smaller than building at runtime)

**Security:**
- Runs as non-root (USER 1001)
- UBI9-based (Red Hat supported, CVE scanning)
- Fixed permissions for group write

---

## 🔗 Useful Links

- **Red Hat Reference:** https://github.com/opendatahub-io/odh-data-processing
- **Docling Project:** https://github.com/docling-project/docling
- **RHOAI Docs:** https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_llama_stack/index
- **KFP SDK:** https://www.kubeflow.org/docs/components/pipelines/v2/

---

## 💡 Key Takeaways

1. **Red Hat doesn't deploy Docling as a standalone service** – it's embedded in KFP components
2. **Pre-built base image** with models is much more efficient than runtime installation
3. **Parallel processing** with `dsl.ParallelFor` enables horizontal scaling
4. **Our REST API is complementary** – good for different use cases
5. **Adopt Red Hat pattern for batch processing** – use their proven approach
6. **Keep both approaches** – REST API for real-time, KFP for batch

---

**Status:** ✅ Analysis Complete  
**Next Steps:** Create KFP components using Red Hat base image  
**Owner:** Stage 2 team  
**Last Updated:** 2025-11-02

