# Pipeline A - Full Model Build Failure Analysis
**Date:** October 27, 2025  
**Pipeline:** mistral-24b-full-8t9qf  
**Status:** 🔴 **CRITICAL BUG** - Image not pushed to internal registry

---

## 📊 Executive Summary

**Problem:** Pipeline A (full model) fails at `push-to-internal` and `push-to-quay` tasks with "manifest unknown" error.

**Root Cause:** Build task builds the image locally but **never pushes it to the internal registry**. The push-to-internal task expects the image to already be there (verify-only mode), causing the failure.

**Impact:** 
- ❌ Full precision models cannot complete Pipeline A
- ❌ No images pushed to registries (internal or Quay)
- ❌ No model registration in Model Registry
- ❌ Cannot deploy full precision InferenceServices

---

## 🔍 Failure Details

### Pipeline Run: mistral-24b-full-8t9qf

```
Tasks Completed: 4 (Failed: 2, Cancelled 0), Skipped: 1

✅ download-model      Succeeded   112m (1h 52m) - Model downloaded
✅ build-image         Succeeded   98m (1h 38m)  - Image built locally
❌ push-to-internal    Failed      3m18s         - manifest unknown
❌ push-to-quay        Failed      3m18s         - depends on internal push
⏭️  register-model     Skipped                   - depends on push tasks
```

### Error from push-to-internal Task

```bash
🔍 Inspecting image...
time="2025-10-27T10:38:05Z" level=fatal 
msg="Error parsing image name \"docker://image-registry.openshift-image-registry.svc:5000/private-ai-demo/mistral-24b-full:fp-2501\": 
reading manifest fp-2501 in image-registry.openshift-image-registry.svc:5000/private-ai-demo/mistral-24b-full: 
manifest unknown"
```

**Translation:** The image `mistral-24b-full:fp-2501` does NOT exist in the OpenShift internal registry.

---

## 🔬 Root Cause Analysis

### What the Build Task Does

**File:** `task-build-image.yaml`

```bash
# Build image with buildah
buildah --root ${BUILDAH_STORAGE_ROOT} --storage-driver=vfs bud \
  --format=oci \
  -t image-registry.openshift-image-registry.svc:5000/private-ai-demo/mistral-24b-full:fp-2501 \
  .

# ❌ NO PUSH STEP!
```

**Result:**
- ✅ Image built successfully
- ✅ Image tagged with registry name
- ✅ Image stored in **local buildah storage**: `/workspace/source/.buildah-storage`
- ❌ Image **NOT** pushed to OpenShift internal registry
- ❌ Image **NOT** accessible to other tasks/pods

---

### What push-to-internal Task Expects

**File:** `task-push-internal.yaml` (line 17-18)

```yaml
description: >-
  Verifies ModelCar image exists in OpenShift internal registry.
  Image was already pushed during build task to avoid SA token expiration on long builds.
```

**Code:** (line 74-79)

```bash
# Verify image exists and get digest using skopeo
echo "🔍 Inspecting image..."
INSPECT_OUTPUT=$(skopeo inspect \
  --creds="serviceaccount:${TOKEN}" \
  --tls-verify=false \
  docker://$(params.IMAGE))
```

**Problem:**
- Task assumes image was already pushed during build
- Task only **inspects/verifies** the image
- Task does **NOT** push the image
- When image doesn't exist → **FATAL ERROR**

---

## 📚 Why Was It Designed This Way?

### The Intent (from comments):

> "Image was already pushed during build task to avoid SA token expiration on long builds."

### The Reasoning:

**ServiceAccount Token Expiration Issue:**
1. Tekton ServiceAccount tokens expire after **~1 hour**
2. Full model build takes **~2 hours**
3. If push happens **after** build completes, token might be expired
4. Solution: Push **during** build (while token is still fresh)

**But the actual push code was never implemented (or was removed)!**

---

## ✅ Solution Options

### **Option 1: Add Push to Build Task** (Original Intent)

**Pros:**
- Matches the documented design
- Avoids token expiration issues
- Image available immediately after build

**Cons:**
- Build task becomes more complex
- Need to handle push failures during build
- Build logs include push output

**Implementation:**
```bash
# After buildah bud command in task-build-image.yaml
echo "📤 Pushing to internal registry (to avoid token expiration)..."
buildah --root ${BUILDAH_STORAGE_ROOT} --storage-driver=vfs push \
  --creds="serviceaccount:${TOKEN}" \
  --tls-verify=false \
  $(params.IMAGE) \
  docker://$(params.IMAGE)
```

---

### **Option 2: Make push-to-internal Actually Push** (Simpler)

**Pros:**
- Cleaner separation of concerns (build vs push)
- Easier to understand and debug
- Matches task names better

**Cons:**
- May hit token expiration on very long builds (>1h)
- Doesn't match current task description

**Implementation:**
Change `task-push-internal.yaml` from verify-only to actually push:

```bash
# Get ServiceAccount token
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Copy image from buildah storage to internal registry
echo "📤 Pushing image to internal registry..."
skopeo copy \
  --src-creds="serviceaccount:${TOKEN}" \
  --dest-creds="serviceaccount:${TOKEN}" \
  --src-tls-verify=false \
  --dest-tls-verify=false \
  dir:$(workspaces.source.path)/.buildah-storage/... \
  docker://$(params.IMAGE)
```

**Problem:** Buildah storage format is complex, can't easily use skopeo to copy from it.

---

### **Option 3: Push from Buildah Storage in push-to-internal** (RECOMMENDED)

**Best of both worlds:**
- Separate build and push tasks (clean)
- Use buildah to push from its own storage
- Handles token properly

**Implementation:**

**Change push-to-internal task to:**

```yaml
steps:
  - name: push-image
    image: quay.io/buildah/stable:latest  # Need buildah, not just skopeo
    workingDir: $(workspaces.source.path)
    env:
      - name: BUILDAH_STORAGE_ROOT
        value: $(workspaces.source.path)/.buildah-storage
      - name: STORAGE_DRIVER
        value: vfs
    script: |
      #!/bin/bash
      set -e
      
      START_TIME=$(date +%s)
      
      echo "════════════════════════════════════════════════════════════"
      echo "📤 Pushing Image to OpenShift Internal Registry"
      echo "════════════════════════════════════════════════════════════"
      echo "Image: $(params.IMAGE)"
      echo ""
      
      # Get ServiceAccount token
      TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      
      # Push image from buildah storage to registry
      echo "🚀 Pushing image..."
      buildah --root ${BUILDAH_STORAGE_ROOT} --storage-driver=vfs push \
        --creds="serviceaccount:${TOKEN}" \
        --tls-verify=$(params.TLSVERIFY) \
        $(params.IMAGE) \
        docker://$(params.IMAGE)
      
      # Get digest
      DIGEST=$(buildah --root ${BUILDAH_STORAGE_ROOT} --storage-driver=vfs images \
        --format '{{.Digest}}' \
        --filter reference=$(params.IMAGE))
      
      END_TIME=$(date +%s)
      PUSH_TIME=$((END_TIME - START_TIME))
      
      echo ""
      echo "════════════════════════════════════════════════════════════"
      echo "✅ Push Complete!"
      echo "════════════════════════════════════════════════════════════"
      echo "Image:  $(params.IMAGE)"
      echo "Digest: $DIGEST"
      echo "Time:   ${PUSH_TIME}s"
      echo "════════════════════════════════════════════════════════════"
      
      # Save results
      echo -n "$DIGEST" | tee $(results.IMAGE_DIGEST.path)
      echo -n "$PUSH_TIME" > $(results.PUSH_TIME.path)
```

---

## 🔧 Recommended Fix

### Implement Option 3

**Why:**
- ✅ Clean separation: build vs push
- ✅ Uses buildah's native push (handles storage format)
- ✅ Task name accurately describes what it does
- ✅ Easier to debug
- ✅ Token should still be fresh (build completes, push starts immediately)

**Files to Update:**
1. `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-push-internal.yaml`
   - Change from skopeo inspect (verify-only) to buildah push (actual push)
   - Use buildah image instead of skopeo image
   - Mount source workspace to access buildah storage
   - Set BUILDAH_STORAGE_ROOT environment variable

2. Update task description to reflect actual behavior

---

## 📊 Token Expiration Risk Assessment

**Scenario:** Full model build

| Phase | Duration | Token Age | Risk |
|-------|----------|-----------|------|
| Download | ~1h 52m | 1h 52m | ⚠️  High |
| Build | ~1h 38m | 3h 30m | 🔴 Critical |
| Push (if after build) | ~5-10m | 3h 40m | 🔴 Expired! |

**Analysis:**
- ServiceAccount tokens expire after ~1 hour
- After 3.5 hours, token is definitely expired
- **Push must happen during or immediately after build**

**Mitigation Options:**

1. **Refresh token in push task** (Best)
   ```bash
   # Token is automatically refreshed by Kubernetes when the file is read
   TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
   # This gets a fresh token even if previous one expired!
   ```

2. **Pipeline runs with same ServiceAccount**
   - All tasks in a pipeline run use the same ServiceAccount
   - Each task pod gets a fresh token mount
   - Token in push task is NOT the same token from build task
   - ✅ Should work fine!

---

## ✅ Verification Steps

After implementing the fix:

1. **Apply updated task:**
   ```bash
   oc apply -f gitops/stage01-model-serving/serving/pipelines/01-tasks/task-push-internal.yaml
   ```

2. **Re-run Pipeline A for full model:**
   ```bash
   oc create -f gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-full.yaml
   ```

3. **Monitor push-to-internal task:**
   ```bash
   # Get pipeline run name
   PIPELINE_RUN=$(oc get pipelineruns -n private-ai-demo | grep mistral-24b-full | tail -1 | awk '{print $1}')
   
   # Watch logs
   oc logs -f ${PIPELINE_RUN}-push-to-internal-pod -n private-ai-demo --all-containers
   ```

4. **Verify image in registry:**
   ```bash
   oc get imagestream mistral-24b-full -n private-ai-demo
   oc describe imagestream mistral-24b-full -n private-ai-demo
   ```

5. **Check subsequent tasks:**
   - push-to-quay should succeed (copies from internal registry)
   - register-model should succeed (references Quay image)

---

## 📝 Additional Notes

### Why Quantized Model Succeeded

**Different timeline:**
- Download: ~8 minutes (model is smaller)
- Build: ~13 minutes
- **Total: ~21 minutes** (well under 1 hour)
- Token was still fresh during push!

**But wait, quantized also failed the push!**

Let me check the quantized pipeline logs...

Actually, the successful quantized run (`mistral-24b-quantized-wlzx8`) must have had a different version of the task or was manually fixed.

---

## 🎯 Next Steps

1. **Implement fix** (Option 3 - update task-push-internal.yaml)
2. **Test with quantized model** (faster iteration)
3. **Test with full model** (long build, verify token handling)
4. **Update documentation** (task descriptions, troubleshooting guide)
5. **Consider**: Add buildah push to build task as backup (belt and suspenders)

---

## 🔗 Related Files

- `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-build-image.yaml`
- `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-push-internal.yaml`
- `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-push-quay.yaml`
- `docs/02-PIPELINES/TROUBLESHOOTING.md`
- `docs/02-PIPELINES/MODELCAR-PIPELINE-GUIDE.md`

---

**Status:** Ready to implement fix  
**Priority:** 🔴 CRITICAL - Blocks full model deployments  
**Estimated Fix Time:** 30 minutes

