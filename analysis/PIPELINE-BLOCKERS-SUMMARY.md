# ModelCar Pipeline Blockers Summary

**Date:** October 25, 2025  
**Pipeline:** mistral-24b-full-modelcar  
**Status:** 🚧 **BLOCKED - Multiple Issues Identified**

---

## Issue Timeline

### Issue #1: PVC Size (RESOLVED ✅)
- **Symptom:** Pipeline failed at 300GB PVC usage
- **Diagnosis:** Initially thought PVC was too small
- **Action:** Increased from 300Gi → 500Gi  
- **Result:** Not the root cause, but 500Gi is adequate

### Issue #2: Authentication Missing (RESOLVED ✅)
- **Symptom:** `authentication required` when pushing to internal registry
- **Diagnosis:** Buildah not using ServiceAccount credentials
- **Action:** Added `--creds="serviceaccount:${TOKEN}"` to buildah push
- **Result:** Authentication mechanism implemented
- **Commit:** `1c98217`

### Issue #3: Wrong ServiceAccount Field (RESOLVED ✅)
- **Symptom:** Warning: `unknown field "spec.serviceAccountName"`
- **Diagnosis:** Tekton v1 uses different field structure
- **Action:** Changed to `spec.taskRunTemplate.serviceAccountName`
- **Result:** Warning eliminated, proper SA configuration
- **Commit:** `bf368d8`

### Issue #4: Security Context Constraint (RESOLVED ✅)
- **Symptom:** Pod forbidden: `capability may not be added: SETFCAP`
- **Diagnosis:** model-pipeline-sa lacks SCC permissions for Buildah
- **Action:** `oc adm policy add-scc-to-user anyuid system:serviceaccount:private-ai-demo:model-pipeline-sa`
- **Result:** SCC access granted
- **Error Message:**
  ```
  pods "mistral-24b-full-modelcar-6sz6c-build-and-push-pod" is forbidden: 
  unable to validate against any security context constraint: 
  [provider "anyuid": Forbidden: not usable by user or serviceaccount,
   provider restricted-v2: .containers[0].capabilities.add: Invalid value: "SETFCAP": 
   capability may not be added]
  ```

### Issue #5: Script Permission Denied (🚧 CURRENT BLOCKER)
- **Symptom:** `/tekton/scripts/script-0-vsr2d: line 12: download_model.py: Permission denied`
- **Location:** prepare-modelcar-context task
- **Diagnosis:** Script file created without execute permissions under restricted context
- **Potential Solutions:**
  1. Use `python download_model.py` instead of `./download_model.py`
  2. Add `chmod +x download_model.py` before execution
  3. Adjust security context in task definition
  4. Grant additional SCC permissions to task

---

## Root Cause Analysis

### Why So Many Security Issues?

1. **Tekton Pods Run with Restricted Security:**
   - OpenShift applies strict SecurityContextConstraints
   - Buildah requires elevated capabilities (SETFCAP)
   - File permissions are restricted

2. **ServiceAccount Configuration:**
   - Initial setup used default `pipeline` ServiceAccount
   - `model-pipeline-sa` created but not configured in PipelineRuns
   - SCC bindings not applied to ServiceAccount

3. **Tekton API Evolution:**
   - Project using Tekton v1 API
   - Field names changed from earlier versions
   - Documentation may reference older formats

### Comparison with Test Pod Success

**Why did test pod work but pipeline fail?**

| Aspect | Test Pod | Pipeline |
|--------|----------|----------|
| **ServiceAccount** | model-pipeline-sa (explicit) | Initially missing |
| **SCC** | Inherited from SA | Needed explicit grant |
| **Script Execution** | Direct container command | Tekton step wrapper |
| **Security Context** | Pod-level | Task-level (more restricted) |

---

## Current State

### Working Components ✅
- [x] PVC sizing (500Gi adequate)
- [x] Authentication mechanism (SA token extraction)
- [x] ServiceAccount configuration (taskRunTemplate)
- [x] SCC anyuid granted to model-pipeline-sa
- [x] HuggingFace token secret exists
- [x] Buildah task with auth fix
- [x] Pipeline and task definitions

### Blocked Components 🚧
- [ ] prepare-modelcar-context task execution
- [ ] Model download phase
- [ ] Image build and push
- [ ] Model registration
- [ ] Complete end-to-end pipeline

---

## Next Steps

### Immediate Actions Required

1. **Fix Script Execution in prepare-modelcar-context:**
   ```yaml
   # Current (failing):
   cat > download_model.py << 'EOFPY'
   ...
   EOFPY
   ./download_model.py  # Permission denied
   
   # Solution A: Use python explicitly
   python download_model.py
   
   # Solution B: Make executable
   chmod +x download_model.py
   ./download_model.py
   
   # Solution C: Inline execution
   python << 'EOFPY'
   ...
   EOFPY
   ```

2. **Test with Simpler Model:**
   - Current: Mistral 24B (48GB) - long feedback loop
   - Alternative: TinyLlama 1.1B (2.2GB) - 5 minute test cycles
   - Validate pipeline fixes faster

3. **Consider Red Hat ModelCar Pre-built Images:**
   - Skip download/build entirely for testing
   - Use: `quay.io/redhat-ai-services/modelcar-catalog:tinyllama-1.1b-chat-v1.0`
   - Focus on deployment and serving validation

### Strategic Decisions

**Option A: Fix Current Approach (Recommended)**
- Pro: Complete control, custom models
- Pro: Learning exercise for ModelCar patterns
- Con: More complexity, more troubleshooting
- Timeline: 2-3 more iterations (4-6 hours)

**Option B: Use Pre-built ModelCar Images**
- Pro: Immediate progress, focus on serving
- Pro: Validates InferenceService configuration
- Con: Limited to Red Hat catalog models
- Con: Doesn't test our build pipeline
- Timeline: 1 hour to validate serving

**Option C: Hybrid Approach**
- Phase 1: Use pre-built images to validate serving ✅
- Phase 2: Fix pipeline for custom models
- Pro: Parallel progress on multiple fronts
- Timeline: Best of both worlds

---

## Lessons Learned (Updated)

### Security in OpenShift

1. **ServiceAccount != Permissions:**
   - Creating SA doesn't grant capabilities
   - Must explicitly bind to SCC
   - Test with `oc auth can-i` commands

2. **Buildah Requires Elevated Access:**
   - `SETFCAP` capability needed
   - `anyuid` or `privileged` SCC
   - Can't run fully rootless in default config

3. **Tekton Security Model:**
   - Step containers inherit task security context
   - File permissions enforced strictly
   - Script execution needs careful handling

### Pipeline Development Best Practices

1. **Start Simple, Add Complexity:**
   - ❌ Started with 48GB model (2 hour cycles)
   - ✅ Should start with 2GB model (5 min cycles)

2. **Test Components in Isolation:**
   - ✅ Test pod validated auth approach
   - 🚧 Should test each task independently

3. **Use Incremental Validation:**
   - Create minimal pipeline
   - Add one component at a time
   - Validate each addition

### Red Hat Patterns

1. **ModelCar Catalog is Reference, Not Tutorial:**
   - Shows working Containerfiles
   - Doesn't show Tekton integration
   - Local builds use different tooling

2. **Internal Registry Auth is Non-Trivial:**
   - Not automatic with role bindings
   - Requires explicit token passing
   - Different from external registries

---

## Technical Debt

### Items to Document

1. **SCC Configuration:**
   - Document why `anyuid` is needed
   - Alternative: Custom SCC with minimal permissions
   - Security implications

2. **Authentication Pattern:**
   - Document SA token approach
   - Compare with dockercfg method
   - When each is appropriate

3. **Pipeline Best Practices:**
   - Timeouts and retry logic
   - Progress reporting
   - Error handling patterns

### Items to Clean Up

1. **Git Branch:**
   - Multiple commits for same issue
   - Should squash before merge
   - Clean commit history

2. **Test Resources:**
   - Remove test pods after validation
   - Clean up test ImageStreams
   - Document test methodology

3. **Documentation:**
   - Move from `analysis/` to proper docs
   - Create troubleshooting guide
   - Add runbook for common issues

---

## Comparison: Expected vs Actual

### Expected (Based on Red Hat Examples)
```
1. Download model (15 min)
2. Build image (30 min)
3. Push to registry (5 min)
4. Register in Model Registry (5 min)
Total: ~1 hour
```

### Actual (Current Experience)
```
1. PVC sizing issues (2 hours debugging)
2. Authentication problems (3 hours debugging)
3. SCC configuration (1 hour)
4. Script permission issues (ongoing)
5. Model download: NOT YET REACHED
Total so far: 6+ hours, pipeline not complete
```

### Gap Analysis

**Why the difference?**

1. **Red Hat examples assume:**
   - Pre-configured cluster
   - Proper SCC bindings
   - Experienced operator

2. **Our reality:**
   - Fresh cluster configuration
   - Learning Tekton + OpenShift security
   - Discovering issues iteratively

3. **Missing from examples:**
   - Tekton-specific patterns
   - Security context setup
   - Troubleshooting guide

---

## Recommendations

### For This Project

1. **Immediate:** Fix script execution in prepare-context task
2. **Short-term:** Test with TinyLlama for faster iteration
3. **Medium-term:** Document all SCC/security requirements
4. **Long-term:** Create reusable GitOps templates

### For Future Projects

1. **Start with Red Hat Pre-built Images:**
   - Validate serving first
   - Build custom pipelines second

2. **Create Security Baseline:**
   - Document required SCCs
   - Create dedicated ServiceAccounts
   - Test auth patterns early

3. **Implement Progressive Testing:**
   - Unit test tasks individually
   - Integration test with small models
   - Production test with full models

---

## References

- **Previous Analysis:** `analysis/MODELCAR-PIPELINE-AUTH-FIX.md`
- **Red Hat ModelCar:** [github.com/redhat-ai-services/modelcar-catalog](https://github.com/redhat-ai-services/modelcar-catalog)
- **OpenShift SCC Docs:** [docs.openshift.com/security-context-constraints](https://docs.openshift.com)
- **Tekton Security:** [tekton.dev/docs/pipelines/security](https://tekton.dev)

---

**Document Version:** 1.0  
**Last Updated:** October 25, 2025  
**Status:** In Progress - Actively Troubleshooting

