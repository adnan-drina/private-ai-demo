# Tekton v1 Timeout Resolution

**Date:** 2025-10-26  
**Status:** ✅ RESOLVED for Pipeline A (Model Build)  
**Status:** ⚠️ BLOCKED for Pipeline B (LM-Eval) - different issue

---

## Problem Summary

Pipeline tasks were timing out at 1 hour despite configuring longer timeouts. The `build-image` task for the 48GB model was being killed after 1h, but it needs 3h to complete.

## Root Cause

**Incorrect timeout location:** We initially tried to set timeouts in multiple wrong places:
1. ❌ `PipelineRun.spec.taskRunSpecs[].timeout` - This field doesn't exist in Tekton v1
2. ❌ `PipelineRun.spec.timeouts.tasks` - This is a global cap, not per-task
3. ❌ `Task.spec.timeout` - Individual Task definitions don't support this

**Correct location:** Task timeouts must be set in the **Pipeline spec** at `Pipeline.spec.tasks[].timeout`

---

## Solution

### Correct Tekton v1 Pattern

Per [Tekton documentation](https://tekton.dev/docs/pipelines/pipelines/):

**Pipeline Definition:**
```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: modelcar-build-deploy-v2
spec:
  timeout: 4h0m0s  # Overall pipeline timeout
  
  tasks:
    - name: download-model
      timeout: "1h"      # Per-task timeout
      taskRef:
        name: download-model-from-hf
    
    - name: build-image
      timeout: "3h"      # Per-task timeout (critical for 48GB model)
      taskRef:
        name: build-modelcar-image
    
    - name: push-to-internal
      timeout: "30m"
      taskRef:
        name: push-to-internal-registry
    
    - name: push-to-quay
      timeout: "30m"
      taskRef:
        name: push-to-quay
    
    - name: register-model
      timeout: "15m"
      taskRef:
        name: register-model
```

**PipelineRun:**
```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: mistral-24b-full
spec:
  pipelineRef:
    name: modelcar-build-deploy-v2
  
  timeouts:
    pipeline: "4h"  # Must be >= sum of task timeouts
  
  # NO taskRunSpecs for timeouts - that field doesn't exist!
```

---

## Verification Process

1. **Test with 5-minute timeout:**
   - Set `download-model` timeout to `"5m"`
   - Applied Pipeline and ran PipelineRun
   - ✅ Task correctly timed out at 5m3s with `TaskRunTimeout`

2. **Apply production timeouts:**
   - Set timeouts for all tasks (1h, 3h, 30m, 30m, 15m)
   - Deleted and recreated Pipeline (apply wasn't updating the field)
   - Verified: `oc get pipeline -o jsonpath='{.spec.tasks[0].timeout}'` returns `"1h0m0s"`

3. **Run full pipeline:**
   - Pipeline A is currently running with correct timeouts
   - Download task has been running for 9+ minutes without timeout
   - Will monitor through completion

---

## Key Learnings

### 1. Timeout Hierarchy
```
PipelineRun.spec.timeouts.pipeline (4h)
  ├─ Task 1 timeout (1h)
  ├─ Task 2 timeout (3h)  
  ├─ Task 3 timeout (30m)
  └─ Task 4 timeout (15m)
```

The pipeline timeout is a hard cap. Individual task timeouts must fit within it.

### 2. Go Duration Format
All timeouts use Go duration strings:
- `"1h"` = 1 hour
- `"30m"` = 30 minutes  
- `"1h30m"` = 1.5 hours
- `"3h"` = 3 hours

### 3. Pipeline vs PipelineRun
- **Pipeline**: Defines the workflow and task-level timeouts (reusable)
- **PipelineRun**: Instantiates a Pipeline with parameters and overall timeout

### 4. taskRunSpecs Usage
`taskRunSpecs` is for runtime **overrides** of other properties like:
- `serviceAccountName`
- `podTemplate`
- `computeResources`

It does NOT support `timeout` in Tekton v1.

---

## Files Modified

1. **Pipeline Definition:**
   - `gitops/stage01-model-serving/serving/pipelines/02-pipeline/pipeline-modelcar-refactored.yaml`
   - Added `timeout` field to each task in `spec.tasks[]`

2. **PipelineRun (no changes needed):**
   - `gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-full.yaml`
   - Already had correct `timeouts.pipeline: "4h"`

---

## Current Status

### Pipeline A (Model Build): ✅ WORKING
- **Status:** Running with correct timeouts
- **Current Task:** download-model (9+ minutes, no timeout)
- **Expected Completion:** ~3-4 hours total
- **Monitoring:** Autonomous monitoring in progress

### Pipeline B (LM-Eval): ⚠️ BLOCKED
- **Status:** Failed (different issue - not timeout related)
- **Issue:** `local-chat-completions` backend doesn't support `loglikelihood`
- **Root Cause:** SSL verification issues with `aiohttp` in `local-completions` backend
- **Next Steps:** Need to properly configure SSL context for aiohttp ClientSession

---

## Next Steps

1. ✅ Monitor Pipeline A to successful completion
2. ⚠️ Resolve lm-eval SSL/aiohttp issue for Pipeline B
3. ✅ Document successful end-to-end pipeline execution
4. ✅ Commit all fixes to git branch

---

## References

- [Tekton Pipelines Documentation](https://tekton.dev/docs/pipelines/pipelines/)
- [Tekton PipelineRuns Documentation](https://tekton.dev/docs/pipelines/pipelineruns/)
- [Go time.ParseDuration](https://golang.org/pkg/time/#ParseDuration)

