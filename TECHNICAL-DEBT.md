# Technical Debt & Future Improvements

This document tracks technical debt and areas for improvement that were deferred for faster delivery.

---

## 🔴 HIGH PRIORITY

### 1. Build Task Security: Remove anyuid SCC Requirement

**Current State:**
- `build-runtime-image` task requires `anyuid` SCC
- Containerfile uses `USER root` but buildah runs as non-root

**Proper Solution:**
Rewrite Containerfile to run entirely as non-root user (1001) or use multi-stage build.

**Files:** `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-build-runtime-image.yaml`

**Effort:** 2-4 hours

---

## 🟡 MEDIUM PRIORITY

### 2. Docling Deployment

**Current State:**
- Operator subscription exists but package not available
- Need alternative deployment (standard Deployment)

### 3. LlamaStack Provider Configuration

**Current State:**
- Using environment variables instead of `spec.providers`
- RHOAI 2.25 CRD doesn't support providers field yet

---

## Tracking

| Item | Priority | Status |
|------|----------|--------|
| Remove anyuid SCC | HIGH | Open |
| Deploy Docling | MEDIUM | Blocked |
| LlamaStack providers | MEDIUM | Monitor RHOAI |

---

**Last Updated:** 2025-11-02
