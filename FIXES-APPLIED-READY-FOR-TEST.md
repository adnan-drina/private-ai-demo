# Fixes Applied - Ready for Testing

**Date:** 2025-10-27  
**Status:** ✅ FIXES APPLIED - Ready for clean test run

---

## 🙏 Acknowledgment

**Thank you** for the incredibly patient and thorough explanation that corrected my understanding. The "buffer cache sync" theory was wrong. The actual root causes are:
1. Security context / fsGroup inheritance
2. Workspace/PVC confusion
3. Parallel execution making debugging hard

---

## ✅ Fixes Applied to GitOps

### Fix #1: Serialize Push Tasks (CRITICAL)

**File:** `gitops/stage01-model-serving/serving/pipelines/02-pipeline/pipeline-modelcar-refactored.yaml`

**Change:**
```yaml
# Task 3b: Push to Quay.io (AFTER push-to-internal for deterministic sequence)
- name: push-to-quay
  timeout: "30m"
  runAfter: ["push-to-internal"]  # Changed from ["build-image"]
```

**Why:** Creates linear sequence: build → push-internal → push-quay  
**Impact:** Eliminates parallel-read confusion, makes debugging deterministic

---

### Fix #2: Debug Logging in Push Tasks

**Files:**
- `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-push-internal.yaml`
- `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-push-quay.yaml`

**Addition (after retry logic, before push):**
```bash
# Debug: Security context and file access
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
skopeo inspect oci-archive:$(workspaces.source.path)/oci/image.tar 2>&1 | head -20 || echo "⚠️  skopeo inspect failed: $?"
echo "════════════════════════════════════════════════════════════"
echo ""
```

**Why:** Immediately shows:
- UID/GID and supplementary groups (proves fsGroup inheritance)
- File permissions and ownership
- File content validation (blob digest)

**Impact:** Will instantly reveal root cause from debug output

---

### Fix #3: Validation in Build Task

**File:** `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-build-image.yaml`

**Addition (after OCI export):**
```bash
echo "✅ OCI archive created: $(workspaces.source.path)/oci/image.tar"
ls -lh $(workspaces.source.path)/oci/image.tar

# Force filesystem sync (belt-and-braces for network storage)
echo "💾 Syncing to storage..."
sync

# Validate archive integrity (fail-fast if broken)
echo "🔍 Validating OCI archive integrity..."
if ! skopeo inspect oci-archive:$(workspaces.source.path)/oci/image.tar > /dev/null 2>&1; then
  echo "❌ ERROR: OCI archive created but failed validation"
  skopeo inspect oci-archive:$(workspaces.source.path)/oci/image.tar 2>&1 || true
  exit 1
fi
echo "✅ OCI archive validated successfully"
```

**Why:**
- `sync`: Belt-and-braces for network storage (good hygiene, not root fix)
- `skopeo inspect`: Validates archive isn't corrupt before push tasks start
- Fail-fast: If archive is broken, build task fails (not push tasks)

**Impact:** Build task guarantees good archive or fails early

---

## 📊 Current Status

### Deployed to Cluster:
```
✅ pipeline.tekton.dev/modelcar-build-deploy-v2 configured
✅ task.tekton.dev/build-modelcar-image configured
✅ task.tekton.dev/push-to-internal-registry configured
✅ task.tekton.dev/push-to-quay configured
```

### Running Pipelines:
| Pipeline | Status | Details |
|----------|--------|---------|
| `mistral-24b-quantized-7bnf5` | ❌ Failed | push-to-internal failed (old code), push-to-quay succeeded with wrong content |
| `mistral-24b-full-6th4d` | 🔄 Running | build-image in progress (158m), will use OLD task definitions (started before fixes) |

---

## 🧪 Recommended Testing Plan

### Step 1: Wait for Full Pipeline to Complete or Cancel It

**Option A: Wait (Conservative)**
- Full pipeline is using OLD task definitions (started before fixes)
- Will likely hit same issues
- But provides data point

**Option B: Cancel (Aggressive)**
- Current build is 158m in (2h 38m)
- Will use old task definitions anyway
- Start fresh with new fixes immediately

### Step 2: Clean Up Old PVCs (IMPORTANT!)

```bash
# List all pipeline PVCs
oc get pvc -n private-ai-demo | grep "pvc-"

# Delete PVCs from failed/old runs to eliminate stale content
oc delete pvc pvc-6e99d5abea -n private-ai-demo  # Quantized run PVC
oc delete pvc pvc-27f34f1760 -n private-ai-demo  # Full run PVC (if canceling)
```

**Why:** Eliminates any stale OCI archives from previous runs

### Step 3: Run Fresh Quantized Pipeline

```bash
# Create new PipelineRun
oc create -f gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-quantized.yaml
```

**Expected:** 
- Download: 3-5 minutes
- Build: 13-15 minutes (with sync + validation)
- Push-to-internal: 1-2 minutes (with debug logs)
- Push-to-quay: 8-10 minutes (serial after internal)
- Total: ~25-30 minutes

### Step 4: Monitor Debug Logs Closely

**When push-to-internal starts, immediately check logs:**
```bash
# Get the new PipelineRun name
NEW_RUN=$(oc get pipelinerun -n private-ai-demo --sort-by=.metadata.creationTimestamp | grep "mistral-24b-quantized" | tail -1 | awk '{print $1}')

# Watch push-to-internal logs
oc logs -f ${NEW_RUN}-push-to-internal-pod -n private-ai-demo --all-containers
```

**Look for in debug output:**
```
🔍 DEBUG: Security Context & File Access
Current user:
uid=0(root) gid=0(root) groups=0(root),1000970000   <-- MUST include 1000970000!
```

If `groups=` **DOES NOT** include `1000970000`:
→ **Root Cause: fsGroup not inherited** - need to check PipelineRun `podTemplate.securityContext`

If `groups=` **DOES** include `1000970000` but still fails:
→ **Root Cause: Something else** - check `stat` output for file ownership

If `skopeo inspect` shows **wrong digest**:
→ **Root Cause: Workspace/PVC confusion** - wrong PVC mounted

---

## 🔍 What to Look For

### Expected Success Pattern:

**Build task logs:**
```
✅ OCI archive created: /workspace/source/oci/image.tar
-rw-r--r--. 1 root 1000970000 14G ...
💾 Syncing to storage...
🔍 Validating OCI archive integrity...
✅ OCI archive validated successfully
```

**Push-to-internal logs:**
```
🔍 DEBUG: Security Context & File Access
Current user:
uid=0(root) gid=0(root) groups=0(root),1000970000
                                          ^^^^^^^^^^^ MUST BE PRESENT!

Workspace listing:
-rw-r--r--. 1 root 1000970000 14G ... image.tar

File stat:
... (should show same permissions)

Verify OCI archive integrity:
"Digest": "sha256:271e2fdbb300..."  <-- Should match build task digest!

🚀 Copying from OCI archive to registry...
[SUCCESS]
```

**Push-to-quay logs:**
- Same debug output as push-to-internal
- Should run AFTER push-to-internal completes
- Should see same file, same digest

---

## 📋 Files Modified (Ready for Git Commit)

```
gitops/stage01-model-serving/serving/pipelines/
├── 01-tasks/
│   ├── task-build-image.yaml          (sync + validation added)
│   ├── task-push-internal.yaml        (debug logging added)
│   └── task-push-quay.yaml            (debug logging added)
└── 02-pipeline/
    └── pipeline-modelcar-refactored.yaml  (serialized push tasks)
```

**Ready to commit once validated!**

---

## 🎯 Success Criteria

- [x] Fixes applied to cluster
- [ ] Fresh PipelineRun created (clean PVCs)
- [ ] Build task: sync + validation succeeds
- [ ] Push-to-internal: debug shows UID/GID with group 1000970000
- [ ] Push-to-internal: succeeds without permission errors
- [ ] Push-to-quay: runs AFTER internal (serial)
- [ ] Push-to-quay: shows same digest as build task
- [ ] Push-to-quay: succeeds
- [ ] Register-model: completes
- [ ] Pipeline: Full success end-to-end

---

## 📝 Next Steps

1. **Decide:** Cancel full pipeline or let it finish?
2. **Clean:** Delete old PVCs to eliminate stale content
3. **Run:** Fresh quantized pipeline with new fixes
4. **Monitor:** Debug logs closely when push tasks start
5. **Analyze:** Debug output will reveal the actual root cause
6. **Document:** Update analysis with findings
7. **Commit:** Once validated, commit fixes to Git

---

## 🔑 Key Points to Remember

1. **`sync` is NOT the root fix** - it's belt-and-braces for durability, not visibility
2. **Pods on same node share page cache** - no sync needed for inter-container visibility
3. **Debug logging is diagnostic, not therapeutic** - it reveals the problem, doesn't fix it
4. **Serialized execution makes debugging linear** - easier to reason about cause and effect
5. **Clean PVCs are essential** - eliminates stale content confusion

---

**Ready to test!** The debug logs will tell us exactly what's wrong. 🔍

