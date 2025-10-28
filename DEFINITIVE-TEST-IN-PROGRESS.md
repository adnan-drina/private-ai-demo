# Definitive Test Run - In Progress

**Date:** 2025-10-27  
**PipelineRun:** `mistral-24b-quantized-wk62d`  
**Status:** 🔄 RUNNING

---

## 🎯 Test Objectives

This run will **definitively prove** one or both of:

### Hypothesis A: Directory Traversal Permissions
- Build task creates `/workspace/source/oci/` with restrictive perms (e.g., `0700`)
- Push-to-internal can't traverse parent directories → "Permission denied"
- **Evidence we'll see:** `ls -ld /workspace/source/oci` showing `drwx------` or missing group `x` bit

### Hypothesis B: Path/Transport Mismatch  
- Push tasks use different `skopeo` transports or paths
- One reads `oci-archive:/workspace/source/oci/image.tar`
- Other reads `dir:/workspace/source/oci` (directory layout)
- **Evidence we'll see:** `skopeo inspect` showing different digests for different paths

---

## 🔍 What the Debug Logs Will Show

### From Build Task (with validation):
```bash
📦 Exporting to OCI archive (for push tasks)...
✅ OCI archive created: /workspace/source/oci/image.tar
💾 Syncing to storage...
🔍 Validating OCI archive integrity...
{
  "Digest": "sha256:XXXXX..."   ← NOTE THIS DIGEST!
  ...
}
✅ OCI archive validated successfully
```

### From Push-to-Internal (CRITICAL - this failed before):
```bash
🔍 DEBUG: Security Context & File Access
Current user:
uid=0(root) gid=0(root) groups=0(root),1000970000   ← MUST include 1000970000!

Workspace listing:
drwxrwsr-x. 2 root 1000970000 ... oci              ← CHECK MODE! (should have g+rx)
-rw-r--r--. 1 root 1000970000 ... image.tar        ← CHECK MODE! (should have g+r)

File stat:
[detailed file metadata]

Verify OCI archive integrity:
{
  "Digest": "sha256:XXXXX..."   ← MUST MATCH BUILD TASK!
  ...
}

PVC mount info:
/dev/... on /workspace/source ...   ← NOTE DEVICE!
```

### From Push-to-Quay (runs AFTER internal now):
```bash
🔍 DEBUG: Security Context & File Access
[Same debug output as push-to-internal]

PVC mount info:
/dev/... on /workspace/source ...   ← MUST MATCH INTERNAL!
```

---

## 📋 Test Configuration

### Changes Applied:
1. ✅ **Serial execution:** build → push-internal → push-to-quay
2. ✅ **Full debug logging:** `id`, `ls -la`, `stat`, `skopeo inspect`, `mount`
3. ✅ **Build validation:** `sync` + `skopeo inspect` before task completes
4. ✅ **Clean PVCs:** Deleted old PVCs (note: one stuck in Terminating)

### Expected Timeline:
- Download: ~3-5 minutes
- Build: ~13-15 minutes (with sync/validation)
- Push-to-internal: ~1-2 minutes (CRITICAL - watching for "Permission denied")
- Push-to-quay: ~8-10 minutes (watching for digest match)
- Register: ~1 minute
- **Total: ~25-30 minutes**

---

## 🎯 Success Criteria

### If Everything Works:
- ✅ Build task validates OCI archive with digest X
- ✅ Push-to-internal debug shows:
  - `groups=0(root),1000970000` (has fsGroup)
  - `drwxrwsr-x` or `drwxr-xr-x` on `/workspace/source/oci` (group can traverse)
  - `skopeo inspect` shows digest X (matches build)
  - Push succeeds
- ✅ Push-to-quay debug shows:
  - Same groups and perms
  - Same digest X
  - Push succeeds
- ✅ Pipeline completes end-to-end

### If Hypothesis A is Confirmed (Dir Perms):
- ❌ Push-to-internal debug shows:
  - `drwx------` on `/workspace/source/oci` (no group traverse)
  - OR `ls -ld /workspace/source/oci` fails with "Permission denied"
- **Fix:** In build task, add:
  ```bash
  chmod g+rx /workspace/source /workspace/source/oci
  ```

### If Hypothesis B is Confirmed (Path Mismatch):
- ⚠️ Push-to-internal shows digest X
- ⚠️ Push-to-quay shows digest Y (different!)
- **Fix:** Ensure both push tasks use EXACT same path:
  ```bash
  oci-archive:/workspace/source/oci/image.tar
  ```

---

## 📊 Monitoring

**Current Status:**
```
mistral-24b-quantized-wk62d
  download-model:    🔄 Running (just started)
  build-image:       ⏳ Pending
  push-to-internal:  ⏳ Pending
  push-to-quay:      ⏳ Pending
  register-model:    ⏳ Pending
```

**Monitor:**
```bash
/tmp/monitor-debug-run.sh   # Single snapshot
watch -n 30 /tmp/monitor-debug-run.sh  # Continuous
```

**Check logs when push tasks start:**
```bash
# Push-to-internal (MOST CRITICAL!)
oc logs -f mistral-24b-quantized-wk62d-push-to-internal-pod -n private-ai-demo --all-containers

# Push-to-quay
oc logs -f mistral-24b-quantized-wk62d-push-to-quay-pod -n private-ai-demo --all-containers
```

---

## 🔑 Key Evidence to Capture

When push-to-internal starts, we need:

1. **`id` output** - proves fsGroup membership at runtime
2. **`ls -ld /workspace/source/oci`** - proves directory mode bits
3. **`stat /workspace/source/oci/image.tar`** - proves file permissions
4. **`skopeo inspect`** - proves file content/digest
5. **`mount | grep workspace`** - proves PVC device

These 5 data points will **definitively identify the root cause**.

---

## 📝 Next Actions After Test

### If Push-to-Internal Succeeds:
- 🎉 Problem solved! Fixes worked!
- Commit all changes to Git
- Run full precision pipeline
- Document solution

### If Push-to-Internal Fails:
- Debug output will show EXACTLY why
- Apply targeted fix based on evidence
- Retest immediately

---

**This is the definitive test.** The debug logs will tell us the truth. 🔬

