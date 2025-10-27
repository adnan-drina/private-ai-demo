# CRITICAL: Node Ephemeral Storage Exhaustion
**Date:** October 27, 2025  
**Status:** 🔴 **BLOCKING ALL LARGE MODEL PIPELINES**  
**Priority:** P0 - CRITICAL

---

## 📊 Executive Summary

**Problem:** Nodes run out of ephemeral storage when pushing large model images (48GB+), causing pipeline failures.

**Root Cause:** Buildah/Skopeo copy operations require ephemeral storage on the node for temp files, layers, and caching. Large models exhaust available node storage.

**Impact:**  
- ❌ Full precision model pipelines cannot complete (any model >20GB)
- ❌ Push tasks fail with "node was low on resource: ephemeral-storage"
- ✅ Quantized models work (8GB is small enough)

**Evidence:**
- Build task: ✅ SUCCESS (uses PVC, not node storage)
- Push task: ❌ FAILED (requires node ephemeral storage)
- Test push: ❌ FAILED (same error - node storage exhausted)

---

## 🔍 Test Results - Image Exists in PVC

### Verification Steps Performed

1. ✅ **PVC Still Exists:** `pvc-5e4d78e141` (500Gi, from failed pipeline)
2. ✅ **Buildah Storage Present:** `/workspace/.buildah-storage` directory exists
3. ✅ **Image Found:** Buildah successfully started copying blob
4. ❌ **Push Failed:** Node ran out of ephemeral storage during push

### Test Task Run: test-push-internal-full

```bash
# Task started successfully
📤 Pushing Image to OpenShift Internal Registry
Image: image-registry.../mistral-24b-full:fp-2501
Storage: /workspace/source/.buildah-storage

🚀 Pushing image from buildah storage...
Getting image source signatures
Copying blob sha256:637fd57557f43e6f34d06a03773c50b9c6f12e067a74176fc47d521d5d5ebf85

# Then FAILED with:
Message: The node was low on resource: ephemeral-storage. 
Threshold quantity: 16015370671
Available: 13389604Ki
Container step-push-image was using 60Ki, request is 0, has larger consumption of ephemeral-storage.
```

**Analysis:**
- ✅ Image WAS in buildah storage (blob found and copy started)
- ✅ Task configuration is correct
- ❌ Node ran out of ephemeral storage during blob copy operation
- Image size: ~48GB (full precision model)
- Node available: ~13GB ephemeral storage
- **48GB > 13GB** → Operation impossible

---

## 🔬 Understanding the Problem

### What is Ephemeral Storage?

**Ephemeral Storage** = Temporary storage on the Kubernetes node itself:
- `/var/lib/containers` (container layers)
- `/var/lib/kubelet/pods` (pod volumes like emptyDir)
- Container writable layers
- Temp files created during image operations

**NOT the same as PVC storage!**

### Why Push Tasks Need Ephemeral Storage

When buildah/skopeo pushes an image:

1. **Read from source** (PVC buildah storage) ✅ No problem
2. **Decompress layers** → Writes to `/tmp` or container layer (node storage) ⚠️
3. **Create manifest** → Writes to node storage ⚠️
4. **Stream to registry** → Buffering in node storage ⚠️
5. **Cache operations** → Uses node storage ⚠️

**For 48GB image:**
- Decompression can temporarily require 1.5-2x the compressed size
- Total ephemeral storage needed: **70-100GB**
- Node available: **~13GB**
- **IMPOSSIBLE**

---

## 📊 Why Quantized Model Works

**Quantized Model:**
- Model size: ~8GB (W4A16 quantization)
- Ephemeral storage needed: ~12-15GB
- Node available: ~13GB
- **BARELY FITS** ✅

**Full Precision Model:**
- Model size: ~48GB (FP16)
- Ephemeral storage needed: ~70-100GB  
- Node available: ~13GB
- **IMPOSSIBLE** ❌

---

## ✅ Solution Options

### Option 1: Use Nodes with More Ephemeral Storage (RECOMMENDED)

**Pros:**
- Simplest solution
- No code changes needed
- Reliable

**Implementation:**
```yaml
# Add to task-push-internal.yaml and task-push-quay.yaml
spec:
  steps:
    - name: push-image
      resources:
        requests:
          ephemeral-storage: "100Gi"  # Request sufficient storage
        limits:
          ephemeral-storage: "150Gi"
```

**Requirements:**
- Nodes must have storage available
- May need to provision larger nodes or add storage to existing nodes

---

### Option 2: Stream Push Without Decompression

**Use skopeo with `--src-compress` and `--dest-compress`:**

```bash
# In push tasks, use skopeo dir-to-docker instead of buildah push
skopeo copy \
  --src-compress=false \
  --dest-compress=false \
  dir:/workspace/.buildah-storage/vfs/.../manifest \
  docker://registry/image:tag
```

**Pros:**
- Reduces ephemeral storage usage
- May work with current node sizes

**Cons:**
- Complex - need to find manifest location in buildah storage
- Buildah storage format is not well-documented
- May not save enough space

---

### Option 3: Push Directly from Build Task (Original Intent)

**Idea:** Push DURING build, before image is fully committed to storage.

```yaml
# In task-build-image.yaml, after buildah bud:
buildah push \
  --creds="serviceaccount:${TOKEN}" \
  $(params.IMAGE) \
  docker://$(params.IMAGE)
```

**Pros:**
- Avoids second copy operation
- Reduces total ephemeral storage needed

**Cons:**
- ServiceAccount token may expire during 2h build
- Build logs become cluttered with push output
- Harder to debug (build and push mixed)

**Token Mitigation:**
- Refresh token before push: `TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)`
- Tokens auto-refresh when read from file

---

### Option 4: Use Image Registry's Copy Feature (If Available)

**Some registries support server-side copy:**

```bash
# Copy within cluster without pulling to node
oc tag image-registry.../source:tag image-registry.../dest:tag
```

**Pros:**
- No node storage used
- Fast (server-side operation)

**Cons:**
- Only works within same registry
- Doesn't help for Quay push
- May not preserve all image metadata

---

### Option 5: Split Image into Layers and Push Separately

**Complex but possible:**

1. Extract individual layers from buildah storage
2. Push each layer separately (smaller ephemeral storage per operation)
3. Construct manifest on registry side

**Pros:**
- Could work with limited node storage

**Cons:**
- Very complex implementation
- Fragile (registry-specific)
- Not worth the effort

---

## 🎯 Recommended Approach

### Implement Option 1 + Option 3 (Hybrid)

**Step 1:** Request ephemeral storage in push tasks (Option 1)
```yaml
resources:
  requests:
    ephemeral-storage: "100Gi"
```

**Step 2:** If nodes still don't have enough storage, add push to build task (Option 3)
```yaml
# In task-build-image.yaml after buildah bud:
echo "📤 Pushing to internal registry (to avoid token expiration and reduce storage usage)..."
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)  # Fresh token
buildah push \
  --creds="serviceaccount:${TOKEN}" \
  --tls-verify=false \
  $(params.IMAGE) \
  docker://$(params.IMAGE)
```

**Why This Works:**
- Ephemeral storage request ensures scheduler places pod on suitable node
- If no suitable node, push-during-build uses less storage (no double-buffering)
- Token refresh mitigates expiration risk

---

## 🔧 Implementation Plan

### Phase 1: Add Ephemeral Storage Requests (Quick Fix)

**Files to Update:**
1. `task-push-internal.yaml`
2. `task-push-quay.yaml`

**Changes:**
```yaml
steps:
  - name: push-image  # or copy-image for quay
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
        ephemeral-storage: "100Gi"  # ADD THIS
      limits:
        memory: "2Gi"
        cpu: "1"
        ephemeral-storage: "150Gi"  # ADD THIS
```

**Test:**
```bash
oc apply -f task-push-internal.yaml
oc apply -f task-push-quay.yaml
oc create -f /tmp/test-push-task.yaml  # Re-run test
```

---

### Phase 2: If Phase 1 Fails, Add Push to Build

**File:** `task-build-image.yaml`

**Add after buildah bud (around line 150):**
```bash
# After build completes, immediately push to internal registry
echo ""
echo "════════════════════════════════════════════════════════════"
echo "📤 Pushing to Internal Registry"
echo "════════════════════════════════════════════════════════════"
echo "Pushing immediately after build to:"
echo "  - Avoid ServiceAccount token expiration"
echo "  - Reduce ephemeral storage usage"
echo "  - Enable parallel push-to-quay task"
echo ""

# Get fresh token
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Push from buildah storage to internal registry
buildah --root ${BUILDAH_STORAGE_ROOT} --storage-driver=vfs push \
  --creds="serviceaccount:${TOKEN}" \
  --tls-verify=$(params.TLSVERIFY) \
  $(params.IMAGE) \
  docker://$(params.IMAGE)

echo "✅ Push to internal registry complete"
```

**Update push-to-internal task to verify-only mode (original design):**
```yaml
# Change back to verification since build now pushes
steps:
  - name: verify-image
    image: quay.io/skopeo/stable
    script: |
      TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      skopeo inspect \
        --creds="serviceaccount:${TOKEN}" \
        docker://$(params.IMAGE)
```

---

## 📊 Resource Requirements Analysis

### Current Node Ephemeral Storage

```bash
# Check available ephemeral storage on nodes
oc get nodes -o custom-columns=NAME:.metadata.name,STORAGE:.status.allocatable.ephemeral-storage

# Check node where task failed
oc describe node <node-name> | grep -A 5 "Allocated resources"
```

**Typical AWS Node Storage:**
- t3.xlarge: ~20GB ephemeral
- m5.2xlarge: ~50GB ephemeral  
- m5.4xlarge: ~100GB ephemeral
- **For 48GB models: Need m5.4xlarge or larger**

---

## 🎯 Next Steps

1. **Check node storage capacity:**
   ```bash
   oc get nodes -o json | jq '.items[] | {name:.metadata.name, ephemeral:.status.allocatable."ephemeral-storage"}'
   ```

2. **Add ephemeral storage requests** (Phase 1)

3. **Test with existing failed pipeline's PVC:**
   ```bash
   oc create -f /tmp/test-push-task.yaml  # With updated task
   ```

4. **If still fails, implement Phase 2** (push during build)

5. **Consider node scaling:**
   - Add nodes with more ephemeral storage
   - Or use nodes with attached EBS volumes for container storage

---

## 🔗 Related Issues

- `analysis/FINAL-DIAGNOSIS-PVC-PERMISSIONS.md` - Original ephemeral storage issue identified
- `docs/02-PIPELINES/TROUBLESHOOTING.md#storage-issues` - Storage troubleshooting
- Pipeline run: `mistral-24b-full-8t9qf` - Failed with this issue
- Pipeline run: `mistral-24b-full-r5r2h` - Also failed with this issue

---

## 📝 Conclusion

**The Design Was Correct:** Build in PVC, push in separate task with fresh token.

**The Problem Is Infrastructure:** Nodes don't have enough ephemeral storage for 48GB image push operations.

**The Solution:** Request sufficient ephemeral storage OR push during build OR upgrade nodes.

---

**Priority:** 🔴 P0 - Blocks all large model deployments  
**Owner:** Platform team + Pipeline team  
**Status:** Diagnosis complete, awaiting infrastructure decision

