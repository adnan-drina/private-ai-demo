# Red Hat Docling Reference Implementation

**Analysis Date:** 2025-11-02  
**Source:** [github.com/opendatahub-io/odh-data-processing](https://github.com/opendatahub-io/odh-data-processing)

## 🔍 Summary

Red Hat's official reference for Docling integration uses **KFP v2 components** (not standalone deployment).

### Key Differences

| Aspect | Red Hat Reference | Our Implementation |
|--------|-------------------|-------------------|
| Deployment | KFP components only | Standalone REST API |
| Base Image | `quay.io/fabianofranz/docling-ubi9:2.54.0` | Runtime pip install |
| Use Case | Batch processing | Ad-hoc conversions |
| Parallelism | `dsl.ParallelFor` | Not applicable |
| Integration | Artifact passing | HTTP API |

### Red Hat Base Image

```dockerfile
FROM quay.io/sclorg/python-311-c9s:c9s
# Pre-installs: Docling, Tesseract OCR, all models
# Security: Runs as USER 1001 (non-root)
# Size: ~2.5GB
```

### KFP Component Pattern

```python
@dsl.component(
    base_image="quay.io/fabianofranz/docling-ubi9:2.54.0"
)
def docling_convert_standard(
    input_path: dsl.Input[dsl.Artifact],
    output_path: dsl.Output[dsl.Artifact],
    pdf_filenames: List[str],
):
    from docling.document_converter import DocumentConverter
    # ... implementation
```

## 🎯 Recommendation: Hybrid Approach

**Keep Both:**
- ✅ Our REST API: For LlamaStack integration, ad-hoc conversions
- ✅ Add Red Hat KFP Components: For batch RAG ingestion pipelines

**Next Steps:**
1. ✅ Analysis complete
2. Create KFP components using Red Hat base image
3. Build RAG ingestion pipeline with Docling → Chunk → Embed → Milvus

## 📚 Resources

- Reference Repo: https://github.com/opendatahub-io/odh-data-processing
- Base Image: `quay.io/fabianofranz/docling-ubi9:2.54.0`
- Docling Project: https://github.com/docling-project/docling
