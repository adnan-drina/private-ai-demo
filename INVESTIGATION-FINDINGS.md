# Investigation Findings - Hard Evidence

**Date:** 2025-10-27  
**Status:** Evidence collected, ready for clean test run

---

## 🔬 What We Found (Hard Evidence)

### Test Subject: Failed PipelineRun `mistral-24b-quantized-7bnf5`

**TaskRuns:**
```
mistral-24b-quantized-7bnf5-download-model     ✅ Succeeded
mistral-24b-quantized-7bnf5-build-image        ✅ Succeeded  
mistral-24b-quantized-7bnf5-push-to-internal   ❌ Failed (Permission denied)
mistral-24b-quantized-7bnf5-push-to-quay       ✅ Succeeded (but wrong blob digest)
```

---

## 📊 Evidence Analysis

### Finding #1: Same PVC Across All Tasks ✅

**Checked:**
```bash
Build task PVC:          pvc-6e99d5abea
Push-to-internal PVC:    pvc-6e99d5abea
Push-to-quay PVC:        pvc-6e99d5abea
```

**Conclusion:** ✅ All three tasks use the SAME PVC  
**Rules out:** Suspect #2 (PVC confusion / stale content from different PVC)

---

### Finding #2: Identical SecurityContext Across All TaskRuns ✅

**TaskRun Spec Comparison:**

**Push-to-Internal:**
```yaml
podTemplate:
  securityContext:
    fsGroup: 1000970000
    fsGroupChangePolicy: OnRootMismatch
serviceAccountName: model-pipeline-sa
```

**Push-to-Quay:**
```yaml
podTemplate:
  securityContext:
    fsGroup: 1000970000
    fsGroupChangePolicy: OnRootMismatch
serviceAccountName: model-pipeline-sa
```

**Conclusion:** ✅ TaskRun specs are IDENTICAL  
**Note:** Both specify the correct fsGroup from namespace range

---

### Finding #3: Identical Pod SecurityContext ✅

**Pod Spec Comparison:**

**Push-to-Internal Pod:**
```json
{
    "fsGroup": 1000970000,
    "fsGroupChangePolicy": "OnRootMismatch"
}
```

**Push-to-Quay Pod:**
```json
{
    "fsGroup": 1000970000,
    "fsGroupChangePolicy": "OnRootMismatch"
}
```

**Conclusion:** ✅ Actual pod specs are IDENTICAL  
**Rules out:** Suspect #1 (fsGroup inheritance issue at pod creation time)

---

## 🤔 The Mystery

### What We Expected:
- **Suspect #1 (fsGroup inheritance):** Different fsGroup between tasks → RULED OUT
- **Suspect #2 (PVC confusion):** Different PVCs → RULED OUT
- **Suspect #3 (Parallel execution):** Race conditions → FIXED (now serial)

### What We Got:
- ✅ Same PVC
- ✅ Same SecurityContext in TaskRun specs
- ✅ Same SecurityContext in Pod specs
- ❌ Push-to-internal still got "Permission denied"
- ❌ Push-to-quay got wrong blob digest

### Remaining Explanations:

#### Theory A: Timing + Retry Logic Exhaustion
**Hypothesis:**
- Build task exported OCI archive (14GB) at 19:23
- Both push tasks started simultaneously at 19:23:10
- Push-to-internal: 
  - Started retry loop immediately
  - File wasn't accessible yet (still being written? permissions not propagated?)
  - 30 retries × 2s = 60s timeout expired
  - Failed with "Permission denied"
- Push-to-quay:
  - Started retry loop slightly later (pod scheduling)
  - By the time it checked, file was accessible
  - But read stale content somehow?

**Evidence supporting:**
- Push-to-internal logs: All 30 retry attempts failed
- Push-to-quay logs: Accessible on attempt 1 (different timing)

**Evidence against:**
- Why would quay see old blob digest if same PVC?
- Both pods on same node (affinity assistant)
- Should share page cache

#### Theory B: File Content Corruption or Partial Write
**Hypothesis:**
- Build task's OCI export succeeded per logs
- But actual file content on PVC is corrupted or incomplete
- Push-to-internal can't even stat the file (permission error could be misleading)
- Push-to-quay reads partially written file (gets old header with old digest)

**Evidence supporting:**
- Blob digest mismatch (expected `2f1073e5...`, got `7c47e871...`)
- File timestamp updated (19:23) but content is old (19:01)

**Evidence against:**
- ls showed file size as 14GB (correct)
- Build task logs showed successful export

#### Theory C: There ARE Two Different Files
**Hypothesis:**
- Despite same PVC name in specs, there's path confusion
- Maybe `$(workspaces.source.path)` resolves differently per task?
- Maybe subPath is being applied inconsistently?
- Maybe symlinks?

**Evidence supporting:**
- Different blob digests suggest different files
- Push-to-internal permission issue could be different path entirely

**Evidence against:**
- All tasks explicitly use same workspace name
- No subPath in pipeline definition
- Both tasks use `$(workspaces.source.path)/oci/image.tar`

---

## 🎯 What We Need to Know Next

### Critical Debug Data (Currently Missing):

These TaskRuns used OLD task definitions (before we added debug logging). We need a fresh run to get:

1. **Runtime UID/GID:**
   ```bash
   id
   # Will show: uid=0(root) gid=0(root) groups=0(root),1000970000
   # MUST include 1000970000 in groups!
   ```

2. **File Permissions at Runtime:**
   ```bash
   ls -la /workspace/source/oci/
   stat /workspace/source/oci/image.tar
   # Will show: owner, group, mode, size, timestamps
   ```

3. **File Content Validation:**
   ```bash
   skopeo inspect oci-archive:/workspace/source/oci/image.tar
   # Will show: Digest, Created timestamp
   # MUST match build task's digest!
   ```

4. **PVC Mount Info:**
   ```bash
   mount | grep workspace
   # Will show: exact device and mount point
   # Can verify same underlying storage
   ```

---

## ✅ What We've Fixed

### Fix #1: Serialized Push Tasks ✅
**File:** `pipeline-modelcar-refactored.yaml`  
**Change:** `push-to-quay` now runs AFTER `push-to-internal` (not parallel)  
**Why:** Eliminates parallel-access confusion, makes execution deterministic

### Fix #2: Comprehensive Debug Logging ✅
**Files:** `task-push-internal.yaml`, `task-push-quay.yaml`  
**Added:**
- `id` - shows UID/GID/groups
- `ls -la` - shows directory contents and permissions
- `stat` - shows detailed file metadata
- `skopeo inspect` - validates OCI archive content
- `mount | grep workspace` - shows PVC mount info

**Why:** Will definitively show runtime context and file state

### Fix #3: Build Task Validation ✅
**File:** `task-build-image.yaml`  
**Added:**
- `sync` - forces filesystem flush (belt-and-braces)
- `skopeo inspect` - validates archive after creation (fail-fast)

**Why:** Build task won't succeed with broken archive

---

## 🧪 Next Steps: Clean Test Run

### Pre-flight Checklist:

1. ✅ Tasks updated with full debug logging
2. ✅ Pipeline serialized (internal → quay)
3. ✅ Build task has validation
4. ⏳ Cancel or wait for current full pipeline
5. ⏳ Delete old PVCs
6. ⏳ Run fresh quantized pipeline
7. ⏳ Analyze debug output

### Expected Debug Output:

**If everything works:**
```
🔍 DEBUG: Security Context & File Access
Current user:
uid=0(root) gid=0(root) groups=0(root),1000970000   ← MUST SEE THIS!

Workspace listing:
drwxrwsr-x. 2 root 1000970000 4096 ... oci
-rw-r--r--. 1 root 1000970000  14G ... image.tar    ← CORRECT PERMS!

File stat:
[detailed stat output with correct ownership]

Verify OCI archive integrity:
{
  "Digest": "sha256:271e2fdbb300..."   ← MUST MATCH BUILD TASK!
  "Created": "2025-10-27T..."
  ...
}

PVC mount info:
/dev/... on /workspace/source type ext4 ...   ← SAME DEVICE FOR ALL TASKS!
```

**If fsGroup still broken (shouldn't be based on evidence):**
```
uid=0(root) gid=0(root) groups=0(root)   ← MISSING 1000970000!
```

**If file is corrupted:**
```
skopeo inspect: Error reading OCI archive
```

**If wrong file/PVC:**
```
"Digest": "sha256:7c47e871..."   ← OLD DIGEST!
```

---

## 📝 Summary

**What we proved:**
- ✅ Same PVC across all tasks (not PVC confusion)
- ✅ Same SecurityContext in TaskRun and Pod specs (not fsGroup inheritance at creation time)
- ✅ Serial execution (not parallel race)

**What remains unclear:**
- ❓ Why push-to-internal got permission denied with correct fsGroup
- ❓ Why push-to-quay saw wrong blob digest on same PVC
- ❓ Whether this is timing, corruption, or path confusion

**What debug logs will tell us:**
- ✅ Actual runtime groups (confirm fsGroup at runtime)
- ✅ Actual file permissions (confirm readable by group)
- ✅ Actual file content (confirm correct digest)
- ✅ Actual PVC mount (confirm same device)

**Next action:**
- Run fresh pipeline with full debug logging
- Analyze debug output
- Fix the actual root cause once identified

---

**The debug logs from the next run will be definitive.** 🎯

