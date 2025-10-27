# Pipeline B - Model Registry Naming Mismatch Analysis
**Date:** October 27, 2025  
**Status:** 🔴 CRITICAL - Test results going to wrong model/version

---

## 🔍 Executive Summary

Pipeline B successfully runs eval and benchmark tests, but **publishes results to the WRONG model/version** in the Model Registry due to multiple naming mismatches.

**Root Cause:** InferenceService, Pipeline A, and Pipeline B are using inconsistent model/version names.

---

## 📊 Current State Analysis

### Model Registry Contains THREE Models

```
1. Mistral-Small-24B-Instruct (ID: 4) ← OLD, from 1 day ago
   └─ quantized-w4a16-2501 (ID: 5)
      - Image: oci://image-registry.openshift-image-registry.svc:5000/private-ai-demo/mistral-24b-quantized:w4a16-2501

2. Comparison-Test (ID: 6)
   └─ (not relevant)

3. Mistral-24B-Instruct (ID: 8) ← NEW, from today
   ├─ quantized-optimized-test (ID: 9)
   │  - Image: oci://quay.io/adrina/private-ai:mistral-quantized-optimized-test
   └─ 24b-w4a16-1gpu (ID: 10) ← Pipeline B is writing here!
      - Image: oci://quay.io/adrina/private-ai:mistral-24b-quantized-w4a16-2501
```

---

## 🎯 What's Actually Deployed

### InferenceService: `mistral-24b-quantized`

```yaml
# From: gitops/stage01-model-serving/serving/vllm/inferenceservice-mistral-24b-quantized.yaml
name: mistral-24b-quantized
storageUri: oci://image-registry.openshift-image-registry.svc:5000/private-ai-demo/mistral-24b-quantized:w4a16-2501

# Model Registry Labels (INCONSISTENT!)
modelregistry.opendatahub.io/registered-model-id: "4"    # Mistral-Small-24B-Instruct
modelregistry.opendatahub.io/model-version-id: "9"       # quantized-optimized-test (WRONG!)
```

**Reality:** 
- Image tag `w4a16-2501` matches Model ID 4, Version ID 5 (`quantized-w4a16-2501`)
- But labels point to Version ID 9 (which is under Model ID 8!)

---

## 📝 Pipeline Configurations

### Pipeline A (ModelCar Build) - Latest Run

```yaml
# From: pipelinerun-mistral-quantized.yaml (successful run: mistral-24b-quantized-wlzx8)
model_name: "Mistral-24B-Instruct"          # Model ID: 8 (NEW)
version_name: "24b-w4a16-1gpu"              # Version ID: 10
image_tag: "w4a16-2501"                     # Matches OLD model's image!
```

**Problem:** Pipeline A registered a NEW model/version but used the SAME image tag as the OLD model!

---

### Pipeline B (Model Testing) - Current Configuration

```yaml
# From: pipelinerun-test-mistral-quantized.yaml
inference_service_name: "mistral-24b-quantized"    # vLLM model name
model_name: "Mistral-24B-Instruct"                 # Model ID: 8 (NEW)
version_name: "24b-w4a16-1gpu"                     # Version ID: 10
```

**Problem:** Tests the OLD deployed model (w4a16-2501 image) but publishes to the NEW model registry entry!

---

## 🔴 Critical Issues Identified

### Issue #1: Model Name Mismatch (guidellm)
**Status:** ✅ **FIXED** (in current session)

```yaml
# BEFORE (WRONG):
guidellm --model "Mistral-24B-Instruct"  # Model Registry name

# AFTER (CORRECT):
guidellm --model "mistral-24b-quantized"  # vLLM model name (from inference_service_name)
```

**Fix Applied:** Updated `pipeline-model-testing.yaml` line 134 to use `$(params.inference_service_name)`

---

### Issue #2: Results Published to Wrong Model
**Status:** 🔴 **ACTIVE BUG**

**What's Happening:**
1. InferenceService serves image: `mistral-24b-quantized:w4a16-2501`
2. This image was originally registered as:
   - Model: "Mistral-Small-24B-Instruct" (ID: 4)
   - Version: "quantized-w4a16-2501" (ID: 5)
3. But Pipeline B publishes test results to:
   - Model: "Mistral-24B-Instruct" (ID: 8)
   - Version: "24b-w4a16-1gpu" (ID: 10)

**Impact:** User views Model ID 4 in UI, but test results go to Model ID 8!

---

### Issue #3: guidellm Results Not Saved to Workspace
**Status:** ✅ **FIXED** (in current session)

**Problem:** Permission denied when copying from `/tmp/benchmarks` to `/workspace/results/benchmarks`

**Fix Applied:** 
- Write directly to workspace from the start
- Fallback to `/tmp` if workspace not writable
- Use `$RESULTS_DIR` variable throughout

---

## ✅ Recommended Solutions

### Option A: Update Pipeline B to Match Deployed Model (QUICK FIX)
**Best for immediate validation**

```yaml
# pipelinerun-test-mistral-quantized.yaml
model_name: "Mistral-Small-24B-Instruct"    # Match OLD model (ID: 4)
version_name: "quantized-w4a16-2501"        # Match OLD version (ID: 5)
```

**Pros:** Tests and results match the actual deployed model  
**Cons:** Uses old naming convention

---

### Option B: Update InferenceService to Match Pipeline A (CORRECT FIX)
**Best for consistency going forward**

1. **Update InferenceService labels:**
```yaml
# inferenceservice-mistral-24b-quantized.yaml
modelregistry.opendatahub.io/registered-model-id: "8"    # Mistral-24B-Instruct
modelregistry.opendatahub.io/model-version-id: "10"      # 24b-w4a16-1gpu
```

2. **Keep Pipeline B as-is** (already correct)

**Pros:** Consistent naming across all components  
**Cons:** Requires InferenceService update and sync

---

### Option C: Use Explicit Pipeline Parameters (USER'S SUGGESTION)
**Best for maintainability**

**Add new parameter to model-testing pipeline:**
```yaml
# pipeline-model-testing.yaml
params:
  - name: vllm_model_name
    type: string
    description: "vLLM model name (used by guidellm, NOT Model Registry name)"
    default: ""
```

**Update guidellm task call:**
```yaml
- name: model_name
  value: $(params.vllm_model_name)  # Explicit vLLM name
```

**Update pipelinerun:**
```yaml
# pipelinerun-test-mistral-quantized.yaml
params:
  - name: inference_service_name
    value: "mistral-24b-quantized"
  - name: vllm_model_name  
    value: "mistral-24b-quantized"  # Explicit, no autodiscovery
  - name: model_name
    value: "Mistral-Small-24B-Instruct"  # Model Registry name
  - name: version_name
    value: "quantized-w4a16-2501"  # Model Registry version
```

**Pros:** 
- Clear separation of concerns
- No autodiscovery confusion
- Explicit control over all names

**Cons:** More parameters to maintain

---

## 🎯 Immediate Action Required

1. **Stop current Pipeline B run:**
   ```bash
   oc delete pipelinerun test-mistral-quantized-276pg -n private-ai-demo
   ```

2. **Choose solution** (recommend Option C for long-term)

3. **Update configurations** based on chosen solution

4. **Verify Model Registry alignment** before re-running

---

## 📊 Verification Checklist

Before running Pipeline B:

- [ ] Verify InferenceService deployed model version
- [ ] Check Model Registry for correct model ID
- [ ] Check Model Registry for correct version ID  
- [ ] Confirm guidellm receives vLLM model name (not Registry name)
- [ ] Confirm publish-results receives Registry model name (not vLLM name)
- [ ] Test results visible in correct Model Registry entry

---

## 🔗 Related Files

**GitOps:**
- `gitops/stage01-model-serving/serving/vllm/inferenceservice-mistral-24b-quantized.yaml`
- `gitops/stage01-model-serving/serving/pipelines/01-tasks/task-run-guidellm.yaml`
- `gitops/stage01-model-serving/serving/pipelines/02-pipeline/pipeline-model-testing.yaml`
- `gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-test-mistral-quantized.yaml`
- `gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-quantized.yaml`

**Model Registry API:**
- Model List: `http://{MR_ROUTE}/api/model_registry/v1alpha3/registered_models`
- Versions: `http://{MR_ROUTE}/api/model_registry/v1alpha3/registered_models/{id}/versions`

---

## 📈 Next Steps

1. **User decides on solution** (A, B, or C)
2. **Apply configuration changes**
3. **Re-run Pipeline B with correct parameters**
4. **Verify results in Model Registry UI**
5. **Update documentation** with chosen pattern

