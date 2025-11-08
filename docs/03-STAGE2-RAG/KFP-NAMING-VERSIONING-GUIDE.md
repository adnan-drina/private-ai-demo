# KFP Pipeline Naming & Versioning Guide

**Date:** 2025-11-07  
**Status:** Recommendations for Production Alignment

## Overview

This document provides guidelines for Kubeflow Pipelines (KFP) naming and versioning conventions, based on KFP v2 best practices and our current implementation analysis.

---

## 1. Pipeline Naming Conventions

### Best Practices

✅ **Use kebab-case** (lowercase with hyphens)  
✅ **Be descriptive but concise**  
✅ **Include purpose/domain**  
✅ **Avoid special characters** (except hyphens)  
✅ **Use consistent naming** across environments

### Examples

**Good:**
- `data-processing-and-insertion`
- `batch-data-processing`
- `rag-ingestion-pipeline`

**Avoid:**
- `DataProcessing` (camelCase)
- `data_processing` (underscores)
- `pipeline1` (not descriptive)

### Our Implementation

✅ **Excellent!** Our pipeline names already follow best practices:
- `data-processing-and-insertion`
- `batch-data-processing`

---

## 2. Pipeline Versioning Strategies

### Option A: Timestamp-based (Current)

**Format:** `v20251107-121838`

**Pros:**
- Auto-sortable
- Clear chronology
- No manual version management

**Cons:**
- Doesn't convey semantic changes

**Use when:**
- Rapid iteration/development
- Internal pipelines
- Testing/experimentation

### Option B: Semantic Versioning (Recommended for Production)

**Format:** `v1.2.3` (MAJOR.MINOR.PATCH)

**Increment rules:**
- **MAJOR**: Breaking changes (parameter changes, output schema changes)
- **MINOR**: New features (new optional parameters, new steps)
- **PATCH**: Bug fixes (no interface changes)

**Examples:**
- `v1.0.0` - Initial release
- `v1.1.0` - Added new optional parameter
- `v1.1.1` - Fixed chunking bug
- `v2.0.0` - Changed required parameters (breaking)

**Pros:**
- Clear change significance
- Industry standard
- Better for production/releases

**Cons:**
- Manual version management

**Use when:**
- Production pipelines
- Published/shared pipelines
- Stable APIs

### Option C: Hybrid (Recommended for Our Use Case)

**Format:** `v1.2.3-20251107`

Combines semantic version with timestamp.

**Example workflow:**
- Dev: `v1.0.0-dev-20251107`
- Staging: `v1.0.0-rc1`
- Production: `v1.0.0`

---

## 3. Pipeline vs Pipeline Version

### Key Concepts

**Pipeline (Immutable Name):**
- One pipeline = one logical workflow
- Name stays the same across versions
- Example: `"batch-data-processing"`

**Pipeline Version (Multiple per Pipeline):**
- Each version = specific implementation
- Can have many versions per pipeline
- Example: `"v1.0.0"`, `"v1.1.0"`, `"v2.0.0"`

### Correct Workflow

1. **First upload:** Create pipeline + initial version
   ```python
   client.upload_pipeline(
       pipeline_package_path=yaml_file,
       pipeline_name="batch-data-processing"
   )
   ```

2. **Updates:** Add new versions to existing pipeline
   ```python
   client.upload_pipeline_version(
       pipeline_id=pipeline_id,
       pipeline_package_path=yaml_file,
       pipeline_version_name="v1.1.0"
   )
   ```

---

## 4. Upload API Best Practices

### Recommended Pattern: Check and Upload

```python
try:
    # Check if pipeline exists
    pipelines = client.list_pipelines(
        filter='{"predicates":[{"key":"name","operation":"EQUALS","stringValue":"batch-data-processing"}]}'
    )
    
    if pipelines and pipelines.pipelines:
        pipeline_id = pipelines.pipelines[0].pipeline_id
        
        # Upload new version
        version = client.upload_pipeline_version(
            pipeline_id=pipeline_id,
            pipeline_package_path=yaml_file,
            pipeline_version_name="v1.2.0"
        )
    else:
        # Create new pipeline
        pipeline = client.upload_pipeline(
            pipeline_package_path=yaml_file,
            pipeline_name="batch-data-processing"
        )
except Exception as e:
    # Handle errors
    pass
```

---

## 5. Component Naming

### Best Practices

✅ **Use snake_case** for component functions  
✅ **Use descriptive, verb-based names**  
✅ **Match filename to function name**

### Our Implementation

✅ **Excellent!** All components follow best practices:

| Component Function | File | Assessment |
|-------------------|------|------------|
| `list_pdfs_in_s3()` | `list_pdfs_in_s3.py` | ✅ Perfect |
| `download_from_s3()` | `download_from_s3.py` | ✅ Perfect |
| `process_with_docling()` | `process_with_docling.py` | ✅ Perfect |
| `chunk_markdown()` | `chunk_markdown.py` | ✅ Perfect |
| `insert_via_llamastack()` | `insert_via_llamastack.py` | ✅ Perfect |
| `verify_ingestion()` | `verify_ingestion.py` | ✅ Perfect |

---

## 6. Control Flow Naming

### ParallelFor Loops

✅ **Always provide custom name parameter**  
✅ **Use descriptive, action-based names**  
✅ **Use kebab-case for UI readability**

### Example

**Good:**
```python
with dsl.ParallelFor(
    items=list_task.output,
    name="process-each-pdf"  # ✅ Descriptive
) as item:
    # ...
```

**Bad:**
```python
with dsl.ParallelFor(
    items=list_task.output
    # ❌ No name → auto-generates "for-loop-1"
) as item:
    # ...
```

### Our Implementation

✅ **Fixed in commit e2404e0!**
- Before: `for-loop-1` (auto-generated)
- After: `process-each-pdf` (descriptive)

---

## 7. Current Implementation Analysis

### ✅ What's Good

1. **Pipeline Naming**: Perfect kebab-case, descriptive
2. **Component Naming**: Perfect snake_case, verb-based
3. **Control Flow**: Custom names provided
4. **File Organization**: Modular, follows KFP best practices

### ⚠️ What Needs Improvement

1. **Versioning Strategy**: Add semantic versioning for production
2. **Pipeline Consolidation**: Multiple pipeline entities per scenario
3. **Upload Logic**: Should check and update versions, not create duplicates
4. **Version Metadata**: Add version info to pipeline descriptions

---

## 8. Recommendations

### 1. Add Semantic Versioning

**Current:** `v20251107-121838` (timestamp only)  
**Recommended:** `v1.0.0` or `v1.0.0-20251107` (hybrid)

**Implementation:**
```python
# pipeline.py
PIPELINE_VERSION = "1.0.0"  # Update when making changes

@dsl.pipeline(
    name="batch-data-processing",
    description=f"RAG Batch Ingestion Pipeline v{PIPELINE_VERSION} - "
                "Refactored with modular components."
)
def batch_docling_rag_pipeline(...):
    # ...
```

### 2. Consolidate Pipeline Entities

**Problem:**
- 3 separate pipelines: `batch-data-processing-{acme,redhat,euaiact}`
- Clutters dashboard
- Same logic, just different parameters

**Solution:**
Keep ONE pipeline: `"batch-data-processing"`

Differentiate via run parameters:
- `vector_db_id`: `"acme_corporate"`, `"red_hat_docs"`, `"eu_ai_act"`
- `s3_prefix`: different S3 paths per scenario

**Benefits:**
- ✅ Cleaner dashboard
- ✅ Easier version management
- ✅ Single source of truth

### 3. Improve Upload Logic

**Current:** Creates new pipeline if name conflicts

**Recommended:**
1. Check if pipeline exists
2. If exists: upload new **version**
3. If not: create new pipeline

### 4. Add Version Metadata

Include version info in pipeline descriptions:

```python
@dsl.pipeline(
    name="batch-data-processing",
    description="RAG Batch Ingestion Pipeline v1.0.0 - "
                "Refactored with modular components. "
                "Features: Parallel PDF processing, server-side embeddings. "
                "Breaking: Requires chunk_size as int, not string."
)
def batch_docling_rag_pipeline(...):
    # ...
```

---

## 9. About `__init__.py` Files

### Current State

We have:
- `kfp/__init__.py` (empty)
- `kfp/components/__init__.py` (empty)

Both are in git.

### Should We Keep Them?

**YES ✅**

**Reasons:**

1. **Explicit Package Definition**
   - Makes intent clear: "this is a package"
   - Better for IDE support and tooling

2. **Import Clarity**
   - Our imports work: `from components.xxx import yyy`
   - More predictable across environments

3. **Future Extensibility**
   - Can add `__all__` to control public API
   - Can add package-level imports if needed

4. **Best Practice Alignment**
   - Python packaging best practices recommend `__init__.py`
   - Red Hat/OpenShift projects follow this pattern

5. **Build/Distribution Compatibility**
   - Better compatibility with packaging tools
   - Works consistently across environments

### Should They Be in Git?

**YES ✅**

Even though they're empty:
- They define the package structure
- They're part of the code (not generated)
- They're needed for imports to work correctly

**Exceptions (should NOT be in git):**
- `__pycache__/` folders → `.gitignore` ✅
- `*.pyc` files → `.gitignore` ✅

### Recommendation

✅ **KEEP `__init__.py` files** (both in project and git)  
✅ **Keep them EMPTY** (no code needed currently)  
✅ **Add content ONLY if you need to:**
- Control public API (`__all__`)
- Add package-level imports
- Add initialization code

**Current state: Perfect! No changes needed.**

---

## 10. Summary

### Current State Assessment

| Aspect | Status | Notes |
|--------|--------|-------|
| Pipeline Naming | ✅ Excellent | Kebab-case, descriptive |
| Component Naming | ✅ Excellent | Snake_case, verb-based |
| Control Flow Naming | ✅ Fixed | Custom names (commit e2404e0) |
| File Organization | ✅ Excellent | Modular, KFP best practices |
| Versioning | ⚠️ Improve | Add semantic versioning |
| Pipeline Consolidation | ⚠️ Improve | Too many pipeline entities |
| `__init__.py` Files | ✅ Perfect | Keep as-is |

### Priority Actions

1. **Optional (for production):** Add semantic versioning (`v1.0.0`)
2. **Optional (for clean dashboard):** Consolidate pipeline entities
3. **Current state:** Already excellent for development use!

### References

- [KFP User Guides](https://www.kubeflow.org/docs/components/pipelines/user-guides/)
- [KFP Create Components](https://www.kubeflow.org/docs/components/pipelines/user-guides/create-components/)
- [Semantic Versioning](https://semver.org/)
- [PEP 420 - Implicit Namespace Packages](https://peps.python.org/pep-0420/)

---

**Last Updated:** 2025-11-07  
**Status:** Documented and Reviewed  
**Commit:** e2404e0 (KFP component refactoring)

