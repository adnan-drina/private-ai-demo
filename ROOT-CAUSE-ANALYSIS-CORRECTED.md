# Root Cause Analysis - OCI Archive Access Issue (CORRECTED)

**Date:** 2025-10-27  
**Status:** IN PROGRESS - Implementing fixes based on correct analysis

## Thank You Note

Big thanks to the user for the patient, detailed correction. My initial "buffer cache sync" theory was wrong. This document reflects the corrected understanding.

---

## 🎯 What We Know (Facts)

### Symptom A: push-to-internal fails with "Permission denied"
```
ls: cannot access '/workspace/source/oci/image.tar': Permission denied
```
- File exists (we'd get "No such file" otherwise)
- Process UID/GID doesn't have permission to access
- **This is NOT a sync issue** - EACCES means permissions problem

### Symptom B: push-to-quay succeeds but pushes wrong content
```
✅ OCI archive is accessible (attempt 1)
Copying blob sha256:7c47e871...  (OLD blob from 19:01)
```
- Expected: `sha256:2f1073e5...` (NEW blob from 19:23 build)
- File timestamp shows 19:23, but content is from 19:01
- **This is NOT a sync issue** - pods on same node share page cache

### Symptom C: Build task succeeds
```
-rw-r--r--. 1 root 1000970000 14G Oct 27 19:23 /workspace/source/oci/image.tar
✅ OCI archive created: /workspace/source/oci/image.tar
sha256:271e2fdbb300...
```
- File created successfully
- Correct permissions: owner=root, group=1000970000, mode=0644
- All pods on same node (via affinity assistant)

---

## 🔍 Corrected Root Cause Analysis

### Why "buffer cache sync" theory was wrong:

**Linux page cache behavior on SAME node:**
- When container A writes a file
- Container B (on same node) reads that file immediately after
- Container B sees the NEW data from the shared page cache
- **No `sync` needed for visibility between containers on same node**

The Affinity Assistant ensures all TaskRun pods are on the same node, so they share the kernel's page cache. Therefore:
- Lack of `sync` does **NOT** explain "permission denied"
- Lack of `sync` does **NOT** explain "stale content from 19:01"

### Actual Root Causes (High Probability):

## Root Cause #1: Security Context Inheritance Issue

**Investigation Findings:**

### Task Definitions Security Context:

**task-download-model.yaml:**
```yaml
stepTemplate:
  securityContext:
    runAsUser: 0
    runAsGroup: 0
```
- ⚠️ Has stepTemplate-level securityContext
- Sets UID=0, GID=0 (root)
- Could interfere with fsGroup inheritance

**task-push-internal.yaml & task-push-quay.yaml:**
```yaml
steps:
  - name: push-*
    securityContext:
      capabilities:
        add:
          - SETFCAP
```
- ✅ Only step-level capabilities
- Should NOT interfere with pod-level fsGroup

**task-build-image.yaml:**
```yaml
steps:
  - name: build-image
    securityContext:
      capabilities:
        add:
          - SETFCAP
```
- ✅ Only step-level capabilities  
- Should NOT interfere with pod-level fsGroup

### PipelineRun Configuration:

```yaml
spec:
  taskRunTemplate:
    serviceAccountName: model-pipeline-sa
    podTemplate:
      securityContext:
        fsGroup: 1000970000
        fsGroupChangePolicy: "OnRootMismatch"
```

### The Problem:

**When fsGroup is set at PipelineRun level:**
- All TaskRun pods should inherit `fsGroup: 1000970000`
- Files created on PVC get group ownership = 1000970000
- All pods should have supplementary group 1000970000
- **BUT:** If a step runs as UID=0 GID=0, it can read via owner permissions (root)
- **BUT:** If another step doesn't properly inherit the fsGroup supplementary group, it can't read via group permissions

**Why push-to-internal fails:**
- Might not be running with supplementary group 1000970000
- File is `-rw-r--r--` owned by `root:1000970000`
- Without group membership → Permission denied

**Why push-to-quay succeeds:**
- Might be running as root (UID 0)
- Can read file via owner permissions
- But reads stale cached content (different issue)

---

## Root Cause #2: Workspace Path Confusion

**Investigation Findings:**

### Pipeline Workspace Bindings:

```yaml
workspaces:
  - name: shared-workspace  # Pipeline-level workspace name

tasks:
  - name: download-model
    workspaces:
      - name: source
        workspace: shared-workspace  ✅
  
  - name: build-image
    workspaces:
      - name: source
        workspace: shared-workspace  ✅
  
  - name: push-to-internal
    workspaces:
      - name: source
        workspace: shared-workspace  ✅
  
  - name: push-to-quay
    workspaces:
      - name: source
        workspace: shared-workspace  ✅
```

**Status:** ✅ All tasks use `workspace: shared-workspace` - **CONSISTENT**

### Task Workspace Paths:

**task-build-image.yaml:**
```bash
mkdir -p $(workspaces.source.path)/oci
buildah push ... oci-archive:$(workspaces.source.path)/oci/image.tar
```

**task-push-internal.yaml:**
```bash
OCI_PATH="$(workspaces.source.path)/oci/image.tar"
```

**task-push-quay.yaml:**
```bash
Source: oci-archive:$(workspaces.source.path)/oci/image.tar
```

**Status:** ✅ All use `$(workspaces.source.path)/oci/image.tar` - **CONSISTENT**

### But Wait - Why Stale Content?

**Hypothesis:** Multiple PipelineRuns could be reusing the same workspace name pattern, leading to:
- Old PVC from previous run still exists
- New PipelineRun creates new PVC with similar name
- Tasks inadvertently bound to wrong PVC
- OR: PVC not properly cleaned up between runs

**Evidence:**
- File timestamp: Oct 27 19:23 (NEW)
- File content: Created 19:01 (OLD)
- This suggests partial write OR wrong PVC entirely

---

## Root Cause #3: Parallel Task Execution

**Current Configuration:**

```yaml
- name: push-to-internal
  runAfter: ["build-image"]  # Starts immediately

- name: push-to-quay
  runAfter: ["build-image"]  # Starts immediately (parallel)
```

**The Problem:**
- Both tasks start simultaneously
- Both try to read 14GB file at the same moment
- Harder to debug what's happening when
- No clear "first successful read" to validate the file

**Impact:**
- Makes troubleshooting much harder
- Can expose race conditions in file access
- No deterministic sequence

---

## 📋 Files Involved

### Primary Files (Need to modify):

1. **`gitops/stage01-model-serving/serving/pipelines/02-pipeline/pipeline-modelcar-refactored.yaml`**
   - Line 177: Change `runAfter: ["build-image"]` to `runAfter: ["push-to-internal"]` for push-to-quay
   - Serializes push tasks

2. **`gitops/stage01-model-serving/serving/pipelines/01-tasks/task-push-internal.yaml`**
   - Add debug logging (id, ls -l, stat) at start of script
   - Add skopeo inspect validation

3. **`gitops/stage01-model-serving/serving/pipelines/01-tasks/task-push-quay.yaml`**
   - Add debug logging (id, ls -l, stat) at start of script
   - Add skopeo inspect validation

4. **`gitops/stage01-model-serving/serving/pipelines/01-tasks/task-build-image.yaml`**
   - Add `skopeo inspect` validation after OCI export (fail-fast if broken)
   - Optional: Add `sync` for belt-and-braces

### Secondary Files (Check for SA overrides):

5. **`gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-quantized.yaml`**
   - Verify taskRunTemplate.podTemplate.securityContext is present
   - Verify no task-level overrides

6. **`gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-full.yaml`**
   - Verify taskRunTemplate.podTemplate.securityContext is present
   - Verify no task-level overrides

---

## 🔧 Recommended Fixes

### Fix #1: Serialize Push Tasks (CRITICAL)

**Change in `pipeline-modelcar-refactored.yaml`:**

```yaml
# Task 3b: Push to Quay.io (AFTER push-to-internal, not parallel)
- name: push-to-quay
  timeout: "30m"
  runAfter: ["push-to-internal"]  # Changed from ["build-image"]
```

**Why:** Creates deterministic sequence: build → internal → quay
**Impact:** Removes parallel-read confusion, makes debugging linear

### Fix #2: Add Debug Logging to Push Tasks

**Add to both `task-push-internal.yaml` and `task-push-quay.yaml` at script start:**

```bash
echo "════════════════════════════════════════════════════════════"
echo "🔍 DEBUG: Security Context & File Access"
echo "════════════════════════════════════════════════════════════"
echo "Current user:"
id
echo ""
echo "Workspace listing:"
ls -la $(workspaces.source.path)/oci/ || echo "⚠️  ls failed: $?"
echo ""
echo "File stat:"
stat $(workspaces.source.path)/oci/image.tar || echo "⚠️  stat failed: $?"
echo ""
echo "Verify OCI archive integrity:"
skopeo inspect oci-archive:$(workspaces.source.path)/oci/image.tar | head -20 || echo "⚠️  skopeo inspect failed: $?"
echo "════════════════════════════════════════════════════════════"
echo ""
```

**Why:** Immediately shows UID/GID, file permissions, and validates content
**Impact:** Will prove or disprove fsGroup and workspace hypotheses instantly

### Fix #3: Add Validation to Build Task

**Add to `task-build-image.yaml` after OCI export:**

```bash
echo "✅ OCI archive created: $(workspaces.source.path)/oci/image.tar"
ls -lh $(workspaces.source.path)/oci/image.tar

# Validate archive integrity (fail-fast if broken)
echo "🔍 Validating OCI archive..."
if ! skopeo inspect oci-archive:$(workspaces.source.path)/oci/image.tar > /dev/null 2>&1; then
  echo "❌ ERROR: OCI archive created but failed validation"
  exit 1
fi
echo "✅ OCI archive validated successfully"
```

**Why:** Fail-fast if archive is corrupt, provides confidence for push tasks
**Impact:** Build task won't succeed with broken archive

### Fix #4 (Optional): Add sync for belt-and-braces

**Add to `task-build-image.yaml` after OCI export:**

```bash
# Force filesystem sync (belt-and-braces for network storage)
echo "💾 Syncing to storage..."
sync
```

**Why:** Good hygiene for large files on network storage (EBS/gp3)
**Impact:** Ensures data is durable, but NOT required for visibility on same node

---

## 🧪 Testing Plan

1. **Apply fixes to GitOps**
2. **Cancel running pipelines**
3. **Clean up old PVCs** (to eliminate stale content confusion)
4. **Run fresh quantized pipeline**
5. **Check debug logs immediately when push tasks start**
6. **Expected outcomes:**
   - Debug logs show UID/GID and fsGroup membership
   - Debug logs show correct file permissions
   - skopeo inspect validates correct blob digest
   - push-to-internal succeeds
   - push-to-quay succeeds (serially after internal)

---

## 🎯 Expected Resolution

After applying fixes:
- **Fix #1** eliminates parallel execution confusion
- **Fix #2** provides immediate diagnostic data (UID/GID, perms, content)
- **Fix #3** validates archive integrity in build task
- We'll know EXACTLY which hypothesis is correct from the debug logs

If debug logs show:
- `id` output missing group 1000970000 → **fsGroup inheritance issue**
- `ls -la` showing different file or path → **workspace binding issue**  
- `skopeo inspect` showing wrong digest → **PVC confusion issue**

Then we can apply the targeted fix.

---

## 📚 Key Learnings

1. **Buffer cache is NOT the issue** - pods on same node share page cache
2. **Linux kernel doesn't return EACCES for unsynced data** - it's always a permissions issue
3. **Parallel execution makes debugging exponentially harder** - serialize for clarity
4. **Debug logging is essential** - id/ls/stat at task start shows the truth
5. **Validation is cheap** - skopeo inspect catches problems early

---

**Next Step:** Implement the 4 fixes and run a clean test.

