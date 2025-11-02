# Pipeline Archives

This directory contains historical pipeline implementations and utilities that are **NOT deployed** but kept for reference.

## Contents

### v1-tasks/
Legacy Tekton tasks from the initial pipeline implementation.

**Historical Context:**
- Early pipeline task definitions
- Pre-dates the unified MinIO-first approach
- Documents the evolution of the pipeline architecture

**Status:** Archived for historical reference only

---

### modelcar/
ModelCar pipeline approach (build + push in single task).

**Historical Context:**
- Alternative pipeline architecture that combined build and push operations
- Used for testing different approaches to model container management
- Contains task-build-push-v2.yaml and task-mirror-to-internal.yaml

**Why Archived:**
- Superseded by the unified MinIO-first pipeline in `gitops/stage01-model-serving/serving/pipelines/active/`
- The active pipeline provides better separation of concerns and supports both quantized and full-precision models

**Status:** Archived for historical reference only

---

### maintenance/
Utility scripts and maintenance tasks.

**Contains:**
- `cleanup-migrate-to-top24.yaml` - Migration utility for TOP 24 property schema

**Status:** Kept for potential future utility, not actively deployed

---

## Active Pipeline

The current production pipeline is located at:
```
gitops/stage01-model-serving/serving/pipelines/active/
```

**Active Pipeline Features:**
- Unified MinIO-first architecture
- Supports all model sizes (quantized and full-precision)
- Separate tasks for download, build, and mirror operations
- Complete testing pipeline (lm-eval + GuideLLM + results publishing)

---

## Reference

For detailed pipeline documentation, see:
- `docs/02-PIPELINES/` - Pipeline documentation
- `docs/03-OPERATIONS/PRODUCTION-CAPACITY-RUNBOOK.md` - Operations guide
- `gitops/stage01-model-serving/serving/pipelines/README.md` - Active pipeline README

---

**Last Updated:** November 1, 2025  
**Moved from:** `gitops/stage01-model-serving/serving/pipelines/`

