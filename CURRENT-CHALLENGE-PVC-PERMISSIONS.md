# Current Challenge: PVC Permissions & Pod Scheduling

**Status**: Pipelines stuck - cannot schedule pods due to Tekton affinity assistant issue

## Timeline of Issues

### 1️⃣ **Original Problem** (18:24)
- **Issue**: `push-to-quay` task failed with `permission denied` when reading OCI archive from PVC
- **Root Cause**: 
  - Build task (running as root) creates OCI archive: `-rw-r--r--. 1 root root 14G`
  - Push task (running as different UID) cannot read the file
- **Log Evidence**:
  ```
  time="2025-10-27T15:11:02Z" level=fatal msg="Invalid source name oci-archive:/workspace/source/oci/image.tar: faccessat /workspace/source/oci/image.tar: permission denied"
  ```

### 2️⃣ **First Fix Attempt** (18:30)
- **Solution**: Added `podTemplate.securityContext` to ensure all tasks run with consistent UID/GID
- **Configuration**:
  ```yaml
  spec:
    taskRunTemplate:
      serviceAccountName: model-pipeline-sa
    podTemplate:  # ❌ WRONG INDENTATION - sibling of taskRunTemplate
      securityContext:
        fsGroup: 1001
        runAsUser: 1001
  ```
- **Result**: Configuration was **ignored** (got warning: `unknown field "spec.podTemplate"`)
- **Evidence**: Pod security context was empty `{}`

### 3️⃣ **Second Fix Attempt** (18:31)
- **Solution**: Fixed indentation - moved `podTemplate` inside `taskRunTemplate`
- **Configuration**:
  ```yaml
  spec:
    taskRunTemplate:
      serviceAccountName: model-pipeline-sa
      podTemplate:  # ✅ CORRECT INDENTATION
        securityContext:
          fsGroup: 1001
          runAsUser: 1001
  ```
- **Result**: Security context now applied, BUT pods stuck in `Pending` state
- **New Problem**: **Pod scheduling failure**

### 4️⃣ **Current Problem** (18:32 - Now)
- **Issue**: Pods cannot be scheduled - stuck in "Pending" forever
- **Error Message**:
  ```
  0/7 nodes are available: 
    1 node(s) had untolerated taint {node-role.kubernetes.io/master: }, 
    3 node(s) didn't match pod affinity rules, 
    3 node(s) had untolerated taint {nvidia.com/gpu: true}
  ```

## Root Cause Analysis

### The Affinity Assistant Problem

Tekton uses an "**affinity assistant**" pod to ensure all tasks sharing a PVC run on the same node:

1. **Expected Flow**:
   - PipelineRun starts
   - Tekton creates an affinity-assistant pod
   - All task pods have `requiredDuringSchedulingIgnoredDuringExecution` affinity to this assistant
   - Tasks schedule on same node as assistant (to access shared PVC)

2. **What's Happening**:
   - PipelineRun starts
   - Affinity assistant is **NOT being created** ❌
   - Task pods require affinity to non-existent assistant
   - Result: **No node matches the pod affinity rules**

3. **Why Affinity Assistant Isn't Created**:
   - Possibly due to the `securityContext` settings conflicting with OpenShift's SCC policies
   - The `runAsUser: 1001` or `fsGroup: 1001` may be incompatible with how Tekton creates the assistant
   - Or there's a configuration issue with Tekton's affinity assistant feature

### What We've Verified

✅ **ServiceAccount has anyuid SCC**:
```bash
oc adm policy who-can use scc anyuid -n private-ai-demo | grep model-pipeline-sa
# Shows: model-pipeline-sa has anyuid
```

✅ **Nodes are available**:
- 3 regular worker nodes (no GPU)
- 3 GPU worker nodes
- But pods can't schedule on ANY of them due to affinity rules

❌ **Affinity Assistant Missing**:
```bash
oc get pod -n private-ai-demo | grep affinity-assistant
# Returns: NOTHING (should show affinity-assistant pod)
```

## Investigation Needed

### Questions to Answer:

1. **Why isn't Tekton creating the affinity-assistant pod?**
   - Check Tekton controller logs: `oc logs -n openshift-pipelines -l app=tekton-pipelines-controller`
   - Check if there's an SCC conflict preventing assistant creation

2. **Does the previous working pipeline have a different configuration?**
   - Compare: `mistral-24b-quantized-4x7qq` (failed but scheduled) vs `mistral-24b-quantized-mvd5r` (stuck)
   - Key difference: First had **no** `podTemplate.securityContext`, second has it

3. **Can we disable affinity assistant?**
   - Tekton has a feature flag: `disable-affinity-assistant`
   - Check: `oc get configmap feature-flags-config -n openshift-pipelines -o yaml`
   - But this may break PVC sharing

4. **Alternative: Use explicit node affinity instead of assistant?**
   - Manually select a node
   - All tasks target that specific node
   - Bypass the affinity assistant entirely

## Proposed Solutions

### Option A: Revert to No Security Context + Alternative Permissions
- Remove `podTemplate.securityContext` entirely
- Make OCI archive world-readable: `chmod 644` (already done)
- Let OpenShift assign random UIDs
- **Risk**: Build task creates as UID X, push task runs as UID Y, still can't read

### Option B: Fix Affinity Assistant
- Investigate why assistant isn't being created
- May need to adjust Tekton configuration
- Check OpenShift Pipelines operator settings

### Option C: Use `fsGroup` Only (Third Attempt - In Progress)
- Changed from `fsGroup: 1001, runAsUser: 1001` to `fsGroup: 0`
- Using root group (GID 0) is Red Hat best practice for build workloads
- **Status**: Still testing, same scheduling issue

### Option D: Manual Node Selection
- Add explicit `nodeSelector` to target a specific non-GPU node
- Skip affinity assistant entirely
- All tasks run on same manually-selected node

## Files Modified

1. `gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-quantized.yaml`
2. `gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-full.yaml`

## Current State

```
Pipeline: mistral-24b-quantized-mvd5r
Status: Stuck in "Pending" (cannot schedule)

All tasks: ⏳ Pending (waiting for download-model pod to schedule)

Pod: mistral-24b-quantized-mvd5r-download-model-pod
Status: Pending (72 seconds and counting)
Issue: No node matches pod affinity rules
```

## Next Steps for Investigation

```bash
# 1. Check Tekton controller logs
oc logs -n openshift-pipelines -l app=tekton-pipelines-controller --tail=100

# 2. Check Tekton feature flags
oc get configmap feature-flags-config -n openshift-pipelines -o yaml

# 3. Compare working vs stuck pipeline
oc get pipelinerun mistral-24b-quantized-4x7qq -n private-ai-demo -o yaml > working.yaml
oc get pipelinerun mistral-24b-quantized-mvd5r -n private-ai-demo -o yaml > stuck.yaml
diff working.yaml stuck.yaml

# 4. Check if affinity assistant is supposed to be created
oc get pipelinerun mistral-24b-quantized-mvd5r -n private-ai-demo -o jsonpath='{.spec.podTemplate}' | jq

# 5. Try creating a simple test TaskRun with same security context
# See if the issue is Pipeline-specific or applies to all TaskRuns
```

## References

- Tekton Affinity Assistant: https://tekton.dev/docs/pipelines/workspaces/#specifying-workspace-order-in-a-pipeline-and-affinity-assistants
- OpenShift SCC: https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html
- Red Hat Build Best Practices: fsGroup=0 for root group access

