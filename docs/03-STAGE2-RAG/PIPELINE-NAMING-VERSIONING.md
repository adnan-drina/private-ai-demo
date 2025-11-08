# Pipeline Naming & Versioning Convention

> **Last Updated:** 2025-11-08  
> **Current Version:** v1.0.2  
> **Status:** Active

## 📋 Overview

This document defines the naming and versioning conventions for KFP v2 pipelines in Stage 2 (RAG ingestion). Following these conventions ensures consistency, traceability, and maintainability across all pipeline runs.

## 🎯 Design Principles

1. **Shared Pipeline Identity** - All scenarios use the same pipeline name
2. **Automatic Version Tracking** - Each run creates a unique version with timestamp
3. **Semantic Versioning** - Code version follows semver in descriptions
4. **Scenario-Based Organization** - Runs and experiments are grouped by scenario
5. **Chronological Ordering** - Timestamps ensure natural ordering in UI

## 📐 Naming Structure

### 1. Pipeline Name (Fixed)

**Convention:** `data-processing-and-insertion`

- **Scope:** Shared across all scenarios (Red Hat, ACME, EU AI Act)
- **Location:** 
  - `run-batch-ingestion.sh` line 117
  - `kfp/pipeline.py` lines 53 (single-doc), 166 (batch)
- **When to Change:** Only for major pipeline refactors (e.g., complete redesign)

```python
PIPELINE_NAME = "data-processing-and-insertion"

@dsl.pipeline(
    name="data-processing-and-insertion",
    description="..."
)
```

**Rationale:** Using a shared name simplifies management (one pipeline for all scenarios) and reduces cognitive overhead.

---

### 2. Pipeline Version Name (Dynamic)

**Convention:** `v{unix_timestamp}-{scenario}`

- **Example:** `v1731072345-acme`, `v1731072456-redhat`, `v1731072567-eu-ai-act`
- **Generated:** Automatically on each run
- **Location:** `run-batch-ingestion.sh` lines 147, 167

```python
version_name = f"v{int(time.time())}-{scenario}"
```

**Why Timestamps?**
- ✅ Guarantees uniqueness (no conflicts)
- ✅ Chronological ordering (latest = highest number)
- ✅ Traceable to exact execution time
- ✅ Works across distributed systems (no coordination needed)

**Scenario Suffix:**
- Helps identify which scenario triggered the version
- Useful when debugging or reviewing pipeline history
- Lowercase: `acme`, `redhat`, `eu-ai-act`

---

### 3. Semantic Version (Manual)

**Convention:** `v{major}.{minor}.{patch} - {description}`

- **Current:** `v1.0.2 - Unified ingestion for all scenarios`
- **Location:** 
  - `run-batch-ingestion.sh` line 118: `VERSION_DESCRIPTION`
  - `kfp/pipeline.py` lines 54, 167: `description` parameter
- **When to Update:** When making code changes (see guidelines below)

```python
VERSION_DESCRIPTION = "v1.0.2 - Unified ingestion for all scenarios"

@dsl.pipeline(
    name="data-processing-and-insertion",
    description="RAG Ingestion Pipeline v1.0.2 - Refactored with modular components..."
)
```

#### Semantic Versioning Guidelines

| Change Type | Version Update | Example |
|-------------|----------------|---------|
| **Breaking Changes** | Increment **major** | v1.0.2 → v2.0.0 |
| **New Features** | Increment **minor** | v1.0.2 → v1.1.0 |
| **Bug Fixes** | Increment **patch** | v1.0.2 → v1.0.3 |
| **Documentation Only** | No version change | v1.0.2 (unchanged) |

**Examples:**

**Breaking Changes (Major):**
- Changing component interfaces (input/output signatures)
- Removing pipeline parameters
- Changing data formats in Milvus schema
- Switching from LlamaStack to different vector store

**New Features (Minor):**
- Adding new pipeline parameters (with defaults)
- Adding new optional components
- Supporting additional document formats
- Improving error handling/logging

**Bug Fixes (Patch):**
- Fixing credential parsing issues
- Correcting chunk size calculations
- Fixing metadata field mappings
- Resolving caching issues

---

### 4. Experiment Name (Scenario-Based)

**Convention:** `rag-ingestion-{scenario}`

- **Examples:** 
  - `rag-ingestion-acme`
  - `rag-ingestion-redhat`
  - `rag-ingestion-eu-ai-act`
- **Location:** `run-batch-ingestion.sh` lines 212, 221

```python
experiment_name = f"rag-ingestion-{scenario}"
```

**Purpose:** Groups related runs by scenario in the KFP UI

---

### 5. Run Name (Job Name)

**Convention:** `{scenario}-batch-ingestion-{unix_timestamp}`

- **Examples:** 
  - `acme-batch-ingestion-1731072345`
  - `redhat-batch-ingestion-1731072456`
  - `eu-ai-act-batch-ingestion-1731072567`
- **Location:** `run-batch-ingestion.sh` line 196

```python
run_name = f"{SCENARIO}-batch-ingestion-{int(time.time())}"
```

**Components:**
- **Scenario prefix:** Identifies which scenario the run processes
- **`batch-ingestion`:** Describes the operation type
- **Timestamp:** Ensures uniqueness and ordering

---

## 📊 Complete Hierarchy Example

When executing `./run-batch-ingestion.sh acme`:

```
📦 Pipeline: data-processing-and-insertion
    │
    ├─ 📌 Version: v1731072345-acme
    │     └─ 📝 Description: "v1.0.2 - Unified ingestion for all scenarios"
    │
    └─ 🧪 Experiment: rag-ingestion-acme
          └─ ▶️ Run: acme-batch-ingestion-1731072345
                ├─ Parameters:
                │  ├─ s3_prefix: s3://llama-files/scenario2-acme/
                │  ├─ vector_db_id: acme_corporate
                │  ├─ chunk_size: 512
                │  └─ cache_buster: 1731072345
                └─ Status: Running/Succeeded/Failed
```

---

## 🔄 Version Update Workflow

### Step 1: Determine Version Type

Ask yourself:
- Does this break existing pipelines? → **Major version**
- Does this add new functionality? → **Minor version**
- Does this fix a bug? → **Patch version**

### Step 2: Update Version Strings

Update **2 files** with the new semantic version:

#### File 1: `run-batch-ingestion.sh`

```bash
# Line 118
VERSION_DESCRIPTION = "v1.0.3 - Fixed S3 credential parsing bug"
```

#### File 2: `kfp/pipeline.py`

```python
# Line 54 (single-doc pipeline)
@dsl.pipeline(
    name="data-processing-and-insertion-single",
    description="RAG Ingestion Pipeline v1.0.3 - Single document processing...",
)

# Line 167 (batch pipeline)
@dsl.pipeline(
    name="data-processing-and-insertion",
    description="RAG Ingestion Pipeline v1.0.3 - Refactored with modular components...",
)
```

### Step 3: Update This Documentation

Update the "Current Version" at the top of this document and add an entry to the version history below.

### Step 4: Commit with Conventional Commit Message

```bash
git commit -m "feat(kfp): Add support for Excel documents [v1.1.0]"
# or
git commit -m "fix(kfp): Correct metadata field mapping [v1.0.3]"
# or
git commit -m "feat(kfp)!: Migrate to Qdrant vector store [v2.0.0]"
```

---

## 📚 Version History

| Version | Date | Type | Description | Commit |
|---------|------|------|-------------|--------|
| **v1.0.2** | 2025-11-07 | Minor | Unified ingestion for all scenarios | c6f5636 |
| **v1.0.1** | 2025-11-07 | Patch | Schema alignment fix for Milvus | a055df1 |
| **v1.0.0** | 2025-11-07 | Major | Initial modular KFP v2 implementation | 2cab3b0 |

---

## 🔍 KFP UI Reference

### Where to Find Each Element

| Element | Location in KFP UI |
|---------|-------------------|
| **Pipeline Name** | Pipelines tab → Name column |
| **Pipeline Version** | Pipeline details → Versions tab |
| **Semantic Version** | Version description field |
| **Experiment Name** | Experiments tab → Name column |
| **Run Name** | Runs tab → Name column (within experiment) |
| **Timestamp** | Implicitly visible in run name suffix |

---

## 🎯 Quick Reference

### Current Conventions (v1.0.2)

```yaml
Pipeline:
  Name: "data-processing-and-insertion"
  Semantic_Version: "v1.0.2"
  
Version:
  Pattern: "v{timestamp}-{scenario}"
  Example: "v1731072345-acme"
  
Experiment:
  Pattern: "rag-ingestion-{scenario}"
  Example: "rag-ingestion-acme"
  
Run:
  Pattern: "{scenario}-batch-ingestion-{timestamp}"
  Example: "acme-batch-ingestion-1731072345"
```

### Update Checklist

When releasing a new version:

- [ ] Determine version type (major/minor/patch)
- [ ] Update `run-batch-ingestion.sh` line 118
- [ ] Update `kfp/pipeline.py` line 54 (single-doc)
- [ ] Update `kfp/pipeline.py` line 167 (batch)
- [ ] Update this document (version history + current version)
- [ ] Commit with conventional commit message
- [ ] Tag release: `git tag -a v1.0.3 -m "Release v1.0.3"`
- [ ] Push with tags: `git push origin main --tags`

---

## 📞 Support

For questions or clarifications about naming/versioning conventions:
- Review this document first
- Check the KFP v2 documentation: https://www.kubeflow.org/docs/components/pipelines/
- Consult the team lead for breaking changes (major version bumps)

---

## 📝 Notes

### Why Not Semantic Versioning for Pipeline Versions?

**We use timestamps instead of semantic versions for pipeline version names because:**

1. **KFP Limitations:** KFP doesn't support uploading the same version name twice
2. **Automation:** Timestamps are generated automatically without human intervention
3. **Uniqueness:** No risk of version conflicts in distributed/concurrent scenarios
4. **Ordering:** Natural chronological ordering in the UI

**Semantic versioning is preserved in the description field**, which provides human-readable version tracking while maintaining automatic version uniqueness.

### Alternative Pipeline for Single Documents

A separate pipeline `data-processing-and-insertion-single` exists for processing individual documents. It follows the same versioning convention but is rarely used (batch pipeline is preferred for efficiency).

---

**Document Version:** 1.0  
**Last Reviewed:** 2025-11-08  
**Next Review:** Quarterly or on major pipeline changes

