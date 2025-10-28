# Platform Request: Large Model Build Support

## Executive Summary

**Status:** Quantized model pipeline (8GB) fully operational ✅  
**Blocker:** Full model pipeline (48GB) fails due to node ephemeral storage exhaustion ❌

**Request:** Platform team intervention to enable large model builds (40-80GB models)

---

## Problem Statement

### What's Working
- ✅ Quantized model (8GB weights → 20GB image): Complete success
- ✅ Download task: 48GB model download to PVC successful
- ✅ Memory allocation: LimitRange provides 8Gi per container
- ✅ Security context: Privileged SCC for Buildah (required for container builds)
- ✅ PVC sharing: Affinity Assistant + fsGroup working correctly

### What's Failing
- ❌ Full model (48GB weights → 80GB image): Build task evicted

**Eviction Details:**
```
The node was low on resource: ephemeral-storage.
Container: step-build-and-push
Used:      46GB ephemeral storage
Available: 13GB on node
Result:    Pod evicted mid-build
```

---

## What We've Already Done (Application-Level Fixes)

### Attempt 1: Force Buildah storage to PVC
```yaml
export HOME=$(workspaces.source.path)/.buildah-home
export STORAGE_DRIVER=vfs  # Use PVC-backed storage
```
**Result:** Image layers go to PVC ✅

### Attempt 2: Redirect temp directories to PVC
```yaml
export TMPDIR=$(workspaces.source.path)/.buildah-tmp
export BUILDAH_TMPDIR=$(workspaces.source.path)/.buildah-tmp
```
**Result:** Reduced ephemeral usage 59GB → 44GB (25% improvement) ✅  
**But:** Still exceeds node capacity (44GB used vs 13GB available) ❌

### Attempt 3: Request ephemeral-storage via resources
```yaml
resources:
  requests:
    ephemeral-storage: "80Gi"
  limits:
    ephemeral-storage: "100Gi"
```
**Result:** Tekton CRDs reject the field - `Warning: unknown field "spec.steps[0].resources"` ❌

**Conclusion:** We've exhausted application-level optimizations. Buildah inherently uses node ephemeral storage for layer assembly, compression, and OCI operations during large model builds.

---

## Required Platform Changes (Pick ONE)

### **OPTION 1: NodeSelector to Large-Storage Worker** ⭐ RECOMMENDED

**What we need:**
- One or more worker nodes with ≥100Gi free ephemeral storage (container writable layer capacity)
- Label these nodes (e.g., `ai-build-node: "true"`)
- Allow us to add `nodeSelector` to our build TaskRuns

**Implementation:**
```bash
# Platform team action
oc label node <big-worker-name> ai-build-node=true
```

```yaml
# Application team config (in PipelineRun)
taskRunTemplate:
  serviceAccountName: model-build-sa
  podTemplate:
    nodeSelector:
      ai-build-node: "true"
```

**Why this is standard:**
- Most production ML platforms dedicate "build nodes" with large local SSD for image packaging
- Isolates heavy workloads from general-purpose workers
- Same pattern as CI/CD "builder nodes" in OpenShift
- No cluster-wide configuration changes required

**Effort:** LOW (labeling nodes)  
**Risk:** LOW (isolated to specific workload)

---

### **OPTION 2: Fix Tekton to Honor Ephemeral Storage Requests**

**What we need:**
- Upgrade OpenShift Pipelines / Tekton to version that supports per-step `resources`
- OR enable feature gate for resource passthrough
- Allow `ephemeral-storage` in `resources.requests` / `resources.limits`

**Why this is cleaner:**
- Kubernetes-native scheduling constraint
- Prevents pod from landing on undersized nodes
- Signals autoscalers to provision appropriate nodes
- Standard practice in cloud-native platforms

**Effort:** MEDIUM (operator upgrade or feature gate config)  
**Risk:** MEDIUM (affects all Tekton workloads cluster-wide)

**Current blocker:**
```bash
Warning: unknown field "spec.steps[0].resources"
Warning: unknown field "spec.stepTemplate.resources"
```

The cluster's Tekton admission webhook is rejecting resource fields on Task steps.

---

## Recommended Path Forward

### Immediate (Next 1-2 Days)
**Do Option 1:** Label one large-storage worker node for AI build workloads.

**Why:**
- Fastest unblock (< 1 hour work)
- Zero risk to existing pipelines
- Proven pattern in production

### Long-Term (Next Sprint/Quarter)
**Explore Option 2:** Upgrade OpenShift Pipelines to support per-step resource requests.

**Why:**
- More portable (no manual node labeling)
- Better for autoscaling environments
- Aligns with Kubernetes best practices

---

## Technical Context for Platform Team

### Why does Buildah need so much ephemeral storage?

Buildah's multi-phase build process for large images:
1. **Layer assembly:** Creates intermediate filesystem layers in container overlay
2. **Compression:** Compresses layers for OCI format (can require 1.5-2x model size)
3. **OCI operations:** Assembles final image manifest and config

Even with `STORAGE_DRIVER=vfs` (PVC-backed) and `TMPDIR` redirected to PVC:
- Some operations still write to `/var/tmp`, `/tmp`, or container rootfs
- These live on node ephemeral storage (not PVC)

For 48GB models:
- Compressed layers: ~60-80GB
- Intermediate files: ~10-20GB
- Peak usage: ~80-100GB

### Why can't we just use a different tool?

- Buildah is Red Hat's supported container build tool for OpenShift
- Alternatives (Docker, Kaniko) have similar ephemeral requirements
- This is inherent to building 80GB container images on-cluster

### Comparison to quantized model

| Model | Weights | Image Size | Ephemeral Used | Result |
|-------|---------|------------|----------------|--------|
| Quantized | 8GB | 20GB | ~15GB | ✅ Success |
| Full | 48GB | 80GB | ~44GB | ❌ Evicted (node has 13GB) |

---

## Risk Assessment

### If we do nothing:
- ❌ Can only deploy quantized models (8GB)
- ❌ Cannot deploy full-precision models (48GB+)
- ❌ Limits AI use cases requiring high-quality models

### If we implement Option 1 (nodeSelector):
- ✅ Full and quantized models both work
- ✅ Isolated to specific workload
- ✅ No impact on other namespaces/pipelines
- ⚠️  Requires manual node labeling (one-time setup)

### If we implement Option 2 (Tekton upgrade):
- ✅ Enables all workloads to request ephemeral storage
- ✅ More Kubernetes-native approach
- ⚠️  Requires operator upgrade or feature gate changes
- ⚠️  Affects all Tekton users cluster-wide

---

## Appendix: Evidence

### Quantized Model Pipeline (SUCCESS)
```
PipelineRun: mistral-24b-quantized-dq772
Status: SUCCEEDED
Tasks:
  1. download-model: ✅ Succeeded (8GB model to PVC)
  2. build-and-push-to-quay: ✅ Succeeded (~15GB ephemeral)
  3. mirror-to-internal: ✅ Succeeded
  4. register-model: ✅ Succeeded
```

### Full Model Pipeline (EVICTED)
```
PipelineRun: mistral-24b-full-bgzrj
Status: FAILED (Evicted)
Tasks:
  1. download-model: ✅ Succeeded (48GB model to PVC)
  2. build-and-push-to-quay: ❌ EVICTED
     Reason: The node was low on resource: ephemeral-storage
     Used: 46119920Ki (~44GB)
     Available: 13870624Ki (~13GB)
```

### Pod Events
```bash
$ oc describe pod mistral-24b-full-bgzrj-build-and-push-to-quay-pod
Status: Failed
Reason: Evicted
Message: The node was low on resource: ephemeral-storage. 
         Threshold quantity: 16015370671, available: 13870624Ki. 
         Container step-build-and-push was using 46119920Ki, 
         request is 0, has larger consumption of ephemeral-storage.
```

---

## Contact

**Namespace:** `private-ai-demo`  
**ServiceAccount:** `model-build-sa` (bound to `privileged` SCC)  
**PipelineRuns:**
- Quantized (working): `mistral-24b-quantized-dq772`
- Full (blocked): `mistral-24b-full-bgzrj`

**Next Action Required:**  
Platform team to label at least one worker node with ≥100Gi ephemeral storage for AI model builds.

