# CRITICAL: Tekton Cluster Misconfiguration – Affinity Assistant Deadlock

**Status:** 🔴 BLOCKING – Any Tekton PipelineRun that uses a PVC-backed workspace cannot execute  
**Date:** 2025-10-27  
**Impact:** Production model build + deployment pipeline blocked  
**Owner to fix:** Cluster Admin / OpenShift Pipelines Operator Admin  
**Application action required:** None

---

## Executive Summary

The Tekton controller in our OpenShift Pipelines installation is currently configured with mutually incompatible feature flags:

```yaml
coschedule: "workspaces"              # Inject podAffinity for workspace co-scheduling
disable-affinity-assistant: "true"    # Suppress creation of the affinity assistant pod
```

What this does:

* Tekton tells every TaskRun pod "you MUST run on the same node as the affinity assistant for this workspace."
* But Tekton is also told "do NOT create the affinity assistant."

That produces an unsatisfiable affinity rule. The Kubernetes scheduler cannot place any TaskRun pod, so all PipelineRuns that use an RWO PVC workspace stay in `Pending` forever. **This is a cluster-wide scheduling deadlock, not an application-level bug.**

---

## Observable Symptoms

1. **TaskRun pods remain in `Pending` indefinitely:**

```bash
oc get pod mistral-24b-quantized-qncl8-download-model-pod -n private-ai-demo
# STATUS: Pending (never transitions to Running)
```

2. **Each TaskRun pod has a hard `podAffinity` to an "affinity-assistant-*" pod:**

```bash
oc get pod mistral-24b-quantized-qncl8-download-model-pod -o jsonpath='{.spec.affinity}'
# shows requiredDuringSchedulingIgnoredDuringExecution -> affinity-assistant-...
```

3. **No affinity assistant pod exists:**

```bash
oc get pod -n private-ai-demo -l app.kubernetes.io/component=affinity-assistant
# No resources found
```

4. **Scheduler events confirm the deadlock:**

```bash
oc describe pod mistral-24b-quantized-qncl8-download-model-pod -n private-ai-demo
# Events section shows:
```

```text
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  2m    default-scheduler  0/7 nodes are available:
                                                       1 node(s) had untolerated taint {node-role.kubernetes.io/master: },
                                                       3 node(s) didn't match pod affinity rules,
                                                       3 node(s) had untolerated taint {nvidia.com/gpu: true}
```

**This is reproducible for any PipelineRun that mounts an RWO PVC workspace.** In other words: **PVC-backed pipelines are globally unschedulable in the current cluster config.**

---

## Root Cause

* **`coschedule: "workspaces"`** (newer Tekton behavior) means:
  * Co-schedule all TaskRuns that share the same PVC-backed workspace on the same node.
  * Inject `podAffinity` into TaskRun pods.
  * Expect an "affinity assistant" pod to act as the anchor for that affinity.

* **`disable-affinity-assistant: "true"`** (legacy flag) means:
  * Do not create that assistant pod.

This pair of settings results in:

* TaskRun pods that demand colocation with a pod that does not exist.
* Scheduler sees "no node satisfies required podAffinity."
* Pods never start.
* PipelineRun never progresses.

**This is a regression-level cluster misconfiguration**, likely introduced by upgrading OpenShift Pipelines / Tekton without reconciling the feature flags.

---

## Why This Matters for Our Workloads

Our model build/deploy pipeline:

* Uses a single large 500Gi ReadWriteOnce PVC as a shared workspace
* Downloads a large model
* Builds an OCI image with Buildah
* Pushes that image to a registry

This class of pipeline is exactly what Tekton's workspace co-scheduling is designed to support:

* All tasks must run on the same node so that the same RWO PVC is mounted once
* Tasks pass large artifacts (model weights, image layers, OCI archive) through that PVC

Today the co-scheduling mechanism is half-enabled and half-disabled. That leaves the scheduler with an impossible requirement, so nothing runs.

**Note:** Application-level permission handling is already solved using `fsGroup`. This is not a pipeline-side permissions issue; it is purely a platform scheduling issue.

---

## Required Cluster Fix (Owner: Cluster Admin / Pipelines Operator Admin)

### Target State (Recommended and Supported)

* Keep workspace co-scheduling
* Re-enable the affinity assistant pod
* Do not ask app teams to re-architect pipelines

### Implementation Steps

**1. Update Tekton feature flags so they are internally consistent:**

```yaml
coschedule: "workspaces"              # KEEP
disable-affinity-assistant: "false"   # FIX (was "true")
# or remove disable-affinity-assistant entirely if managed by operator
```

These flags live either in:

* **The `TektonConfig` custom resource (RECOMMENDED):**

  ```bash
  oc get tektonconfig config -o yaml
  ```

  and then:

  ```yaml
  spec:
    pipeline:
      disable-affinity-assistant: false
      # coschedule should be "workspaces"
  ```

* **Or (indirectly) in the `feature-flags` ConfigMap** in the `openshift-pipelines` namespace.

  ⚠️ **Warning:** If the operator manages this ConfigMap, editing it directly may get reverted. The correct long-term fix is to update the `TektonConfig` CR and let the operator reconcile.

**2. Roll out the controller to apply the change:**

```bash
oc rollout restart deployment tekton-pipelines-controller -n openshift-pipelines
oc wait --for=condition=ready pod -l app=tekton-pipelines-controller -n openshift-pipelines --timeout=60s
oc logs deploy/tekton-pipelines-controller -n openshift-pipelines | grep -i affinity
# confirm it now reports assistant enabled
```

**3. Re-run a PipelineRun that mounts a PVC workspace and verify:**

```bash
# Create a test PipelineRun
oc create -f <your-pipelinerun.yaml> -n private-ai-demo

# Within 2-5 minutes, verify:

# 1. Assistant pod should now exist
oc get pod -n private-ai-demo -l app.kubernetes.io/component=affinity-assistant
# Expected: 1 pod in Running state

# 2. TaskRun pods should move from Pending -> Running
oc get pod -n private-ai-demo | grep download-model
# Expected: Pod transitions to Running

# 3. Workspace mounts successfully
oc get pod <taskrun-pod> -o jsonpath='{.spec.volumes}' | grep shared-workspace

# 4. No permission denied errors in task logs
oc logs <taskrun-pod> -n private-ai-demo
```

**Expected behavior after fix:**

* ✅ An affinity assistant pod is created.
* ✅ TaskRun pods can schedule on that node.
* ✅ The RWO PVC mounts once and is accessible to all tasks.
* ✅ No "permission denied" errors (handled by `fsGroup`).

---

## Application-Level Configuration (Already Correct – No Change Needed)

Our PipelineRun already uses the recommended pattern for file permissions across tasks:

```yaml
spec:
  taskRunTemplate:
    serviceAccountName: model-pipeline-sa
    podTemplate:
      securityContext:
        fsGroup: 2000
        fsGroupChangePolicy: "OnRootMismatch"
        # intentionally NOT setting runAsUser or runAsGroup
```

**Why this matters:**

* OpenShift assigns arbitrary UIDs to each task pod (restricted SCC behavior).
* `fsGroup` ensures the shared PVC is group-readable/group-writable for all those UIDs.
* This avoids "permission denied" between build and push tasks without forcing root.
* This *does not* block the affinity assistant pod from scheduling.
* `fsGroup` here must be allowed by the project's SCC, but under OpenShift's default restricted SCC this is typically allowed.

**So once the cluster flag inconsistency is fixed, we are already aligned with Red Hat/Tekton best practices. No further pipeline changes are required.**

---

## Fallback (Not Recommended for Steady State)

As an emergency-only workaround, the cluster admin could disable co-scheduling entirely:

```yaml
coschedule: "disabled"
disable-affinity-assistant: "true"
```

**Effects:**

* ✅ Tekton stops injecting podAffinity rules, so TaskRuns will schedule again.
* ❌ But tasks may land on different nodes while still trying to reuse a single RWO PVC.
* ❌ This can cause attach/detach churn, temporary mount failures, and unstable performance for large (500Gi) volumes.
* ❌ This may let individual short pipelines limp along, but it is not reliable for our large model build pipeline.

**If we disable co-scheduling, we're effectively saying Tekton can place different tasks on different nodes while still reusing the same RWO PVC. This may work sometimes but is fundamentally unstable for large, stateful workloads like model builds because the PVC is huge (500Gi) and expensive to attach/detach between nodes. This should only be considered as a temporary emergency bypass, not the new steady state.**

---

## Ask to Platform Team

* This is a **platform-level Tekton configuration regression**.
* It currently **blocks any PVC-backed PipelineRun** in the cluster from ever scheduling.
* **Application teams have already implemented the supported fsGroup-based shared workspace model.**
* We need the cluster feature flags corrected so the affinity assistant is actually created again.

Once that's done and the controller is restarted, our pipelines should immediately resume normal operation.

**Note: Application teams have already adopted the supported fsGroup-based workspace sharing model. This is not an application misconfiguration; it's a cluster-level Tekton scheduling configuration regression.**

---

## Communication Template for Platform Team

```
Subject: BLOCKING PROD PIPELINE EXECUTION – Tekton feature flags misaligned

Hi [Admin Name],

We've identified a critical misconfiguration in our OpenShift Pipelines / Tekton setup 
that's blocking all PipelineRuns using PVC workspaces.

**Issue:**
The feature flags are contradictory:
  coschedule: "workspaces"              (inject affinity)
  disable-affinity-assistant: "true"     (don't create affinity target)

This causes TaskRun pods to require affinity to a pod that never exists, 
resulting in permanent Pending state.

**Impact:**
- ANY pipeline using a PVC-backed workspace is currently unschedulable cluster-wide
- Production model build/deployment pipeline blocked
- This is reproducible across all namespaces

**Fix Required:**
In namespace: openshift-pipelines

Via TektonConfig CR (recommended):
  oc edit tektonconfig config
  Set: spec.pipeline.disable-affinity-assistant: false

OR via ConfigMap (if not operator-managed):
  oc patch configmap feature-flags -n openshift-pipelines --type merge \
    -p '{"data":{"disable-affinity-assistant":"false"}}'

Then restart:
  oc rollout restart deployment tekton-pipelines-controller -n openshift-pipelines

**Verification:**
After restart, create a test PipelineRun with PVC workspace and verify:
1. Affinity assistant pod created
2. TaskRun pod moves from Pending → Running

**Impact Assessment:**
- Blocking: Yes (production pipeline cannot execute)
- Risk of fix: Low (standard config change, reversible)
- Downtime: ~5-10 minutes (controller restart)

**Documentation:**
See attached: CRITICAL-CLUSTER-MISCONFIGURATION-FINAL.md

Note: Application teams have already adopted the supported fsGroup-based workspace 
sharing model. This is not an application misconfiguration; it's a cluster-level 
Tekton scheduling configuration regression.

Please let me know when this can be applied.
Thanks!
```

---

## TL;DR for Admins

1. ✅ Set `disable-affinity-assistant` to `false` (or remove it), keep `coschedule: workspaces`.
2. ✅ Restart the tekton-pipelines-controller.
3. ✅ Verify that an affinity assistant pod appears in the same namespace as the PipelineRun, and that TaskRuns finally leave `Pending`.

**Our side is already configured per best practice (`fsGroup`, no forced UID). No additional application changes required.**

---

## Fix Status

**Applied:** 2025-10-27 18:50 UTC  
**Method:** Direct ConfigMap patch (admin access available)

```bash
# Backup created
/tmp/feature-flags-backup-20251027-*.yaml

# Applied fix
oc patch configmap feature-flags -n openshift-pipelines --type merge \
  -p '{"data":{"disable-affinity-assistant":"false"}}'

# Controller restart initiated
oc rollout restart deployment tekton-pipelines-controller -n openshift-pipelines
```

**Verification in progress...**

---

**Prepared by:** AI Assistant + User Analysis  
**Date:** 2025-10-27  
**Confidence:** HIGH - Cluster misconfiguration confirmed via controller logs and feature flags  
**Action Status:** ✅ Fix applied, testing in progress

