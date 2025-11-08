# ArgoCD App-of-Apps Sync Guide

> **Date:** 2025-11-08  
> **Issue:** Application definitions updated in Git but not reflected in cluster  
> **Root Cause:** App-of-Apps pattern creates two-level configuration hierarchy

## 🎯 Problem Summary

When using the App-of-Apps pattern, there are **two levels** of configuration:

1. **Level 1 (ROOT):** The App-of-Apps Application itself (`private-ai-demo-root`)
   - Location: `gitops/argocd/bootstrap/app-of-apps.yaml`
   - Controls: Which **branch** the Application definitions come from
   
2. **Level 2 (APPS):** Individual Application definitions
   - Location: `gitops/argocd/applications/stageXX/*.yaml`
   - Controls: Which **branch** each app's manifests come from

**The Issue:** If the root app points to the wrong branch, it won't see your updated Application definitions!

## 🔧 What Was Fixed

### Before (Broken State)

```yaml
# gitops/argocd/bootstrap/app-of-apps.yaml
source:
  targetRevision: feature/stage2-implementation  # ❌ OLD BRANCH
  path: gitops/argocd/applications
```

**Result:** App-of-apps reads Application definitions from the feature branch, not from `main` where the fixes are!

### After (Fixed State)

```yaml
# gitops/argocd/bootstrap/app-of-apps.yaml
source:
  targetRevision: main  # ✅ PRODUCTION BRANCH
  path: gitops/argocd/applications
```

**Result:** App-of-apps now reads Application definitions from `main`, including all our fixes!

## 📊 Files Modified

### Critical Fix
- `gitops/argocd/bootstrap/app-of-apps.yaml` - **Updated targetRevision to `main`**

### Supporting Fixes (already applied in previous commit)
- `gitops/argocd/applications/stage00/app-stage00-minio.yaml` - Added Route ignoreDifferences
- `gitops/argocd/applications/stage01/app-stage01-model-serving.yaml` - Changed to `main`
- `gitops/argocd/applications/stage02/app-stage02-model-alignment.yaml` - Changed to `main` + selectors

### Legacy File (Updated for Consistency)
- `gitops/argocd/stage02-model-alignment-app.yaml` - Added ignoreDifferences (may not be used)

## 🚀 How to Apply These Changes

### Option 1: Sync via ArgoCD UI (Recommended)

1. **Sync the Root App:**
   ```
   ArgoCD UI → Applications → private-ai-demo-root → Sync
   ```
   
2. **Wait for Application definitions to update** (30-60 seconds)

3. **Sync Each Stage App:**
   ```
   ArgoCD UI → Applications → stage00-minio → Sync
   ArgoCD UI → Applications → stage01-model-serving → Sync
   ArgoCD UI → Applications → stage02-model-alignment → Sync
   ```

### Option 2: Sync via ArgoCD CLI

```bash
# Step 1: Sync the root app-of-apps
argocd app sync private-ai-demo-root

# Step 2: Wait for Application CRDs to update
sleep 30

# Step 3: Sync individual applications
argocd app sync stage00-minio
argocd app sync stage01-model-serving  
argocd app sync stage02-model-alignment

# Step 4: Verify all apps are synced
argocd app list | grep -E "stage0|stage1|stage2"
```

### Option 3: Manual Application Update (Emergency)

If the app-of-apps sync doesn't work:

```bash
# Update the root app directly
oc apply -f gitops/argocd/bootstrap/app-of-apps.yaml

# Update individual app definitions
oc apply -f gitops/argocd/applications/stage00/app-stage00-minio.yaml
oc apply -f gitops/argocd/applications/stage01/app-stage01-model-serving.yaml
oc apply -f gitops/argocd/applications/stage02/app-stage02-model-alignment.yaml

# Force refresh in ArgoCD
argocd app get private-ai-demo-root --refresh
argocd app get stage00-minio --refresh
argocd app get stage01-model-serving --refresh
argocd app get stage02-model-alignment --refresh
```

## 📋 Verification Steps

### Step 1: Verify Root App is Synced

```bash
argocd app get private-ai-demo-root
```

Expected output:
```
Source:
  Repo:            https://github.com/adnan-drina/private-ai-demo.git
  Target:          main  ← Should say "main", not "feature/stage2-implementation"
  Path:            gitops/argocd/applications
```

### Step 2: Verify Individual Apps Point to Main

```bash
argocd app get stage01-model-serving -o yaml | grep targetRevision
argocd app get stage02-model-alignment -o yaml | grep targetRevision
```

Expected output:
```
targetRevision: main  ← Should say "main" for both
```

### Step 3: Check for Drift

```bash
argocd app list | grep -E "stage0|stage1|stage2"
```

Expected output (after all fixes):
```
stage00-datasciencecluster  ... Synced/Healthy   or OutOfSync/Healthy (acceptable)
stage00-gpu-infrastructure  ... Synced/Healthy
stage00-minio               ... Synced/Healthy
stage00-operators           ... Synced/Healthy
stage01-model-serving       ... Synced/Healthy
stage02-model-alignment     ... Synced/Healthy
```

## 🔍 Understanding the App-of-Apps Pattern

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ private-ai-demo-root (App-of-Apps)                              │
│ Source: main branch → gitops/argocd/applications/               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │ stage00-minio    │  │ stage01-serving  │  │ stage02-rag   │ │
│  │ Source: main     │  │ Source: main     │  │ Source: main  │ │
│  │ Path: stage00/   │  │ Path: stage01/   │  │ Path: stage02/│ │
│  └──────────────────┘  └──────────────────┘  └───────────────┘ │
│         │                       │                      │         │
│         ▼                       ▼                      ▼         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │ MinIO Manifests  │  │ vLLM Manifests   │  │ RAG Manifests │ │
│  │ (PVC, Deploy,    │  │ (ISVC, PVC,      │  │ (LlamaStack,  │ │
│  │  Service, Route) │  │  Pipeline)       │  │  Milvus, etc.)│ │
│  └──────────────────┘  └──────────────────┘  └───────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Why Two Levels?

**Level 1 (App-of-Apps):**
- Manages the **Application CRDs** themselves
- Allows you to add/remove entire applications by changing Git
- Provides a single entrypoint for managing all apps

**Level 2 (Individual Apps):**
- Each Application manages its own **Kubernetes resources**
- Can point to different branches for testing
- Independent sync policies and ignore rules

## ⚠️ Common Mistakes

### Mistake 1: Only Updating Application Definitions

```bash
# ❌ WRONG: This updates Git but ArgoCD doesn't see it
git commit -m "fix: Update app definitions"
git push

# ArgoCD still reads from the OLD branch defined in app-of-apps!
```

**Fix:** Update the app-of-apps `targetRevision` too!

### Mistake 2: Forgetting to Sync the Root App

```bash
# ❌ WRONG: Syncing child apps without syncing parent first
argocd app sync stage01-model-serving

# The Application CRD itself hasn't been updated yet!
```

**Fix:** Always sync the root app first, then child apps.

### Mistake 3: Duplicate Application Definitions

If you have files like:
- `gitops/argocd/stage02-model-alignment-app.yaml` (legacy)
- `gitops/argocd/applications/stage02/app-stage02-model-alignment.yaml` (active)

**Problem:** Confusion about which is authoritative!

**Fix:** 
- Use the app-of-apps pattern exclusively
- Remove standalone app files from `gitops/argocd/` root
- Keep all apps in `gitops/argocd/applications/stageXX/`

## 📚 Best Practices

### 1. Always Use Main for Production

```yaml
# ✅ GOOD: Production apps point to main
source:
  targetRevision: main
```

```yaml
# ⚠️ DEVELOPMENT ONLY: Feature branches
source:
  targetRevision: feature/my-test
```

### 2. Sync Order Matters

```
1. Root app (private-ai-demo-root)
   ↓ (wait 30-60 seconds)
2. Individual apps (stage00, stage01, stage02)
   ↓
3. Verify status
```

### 3. Test in Non-Production First

```bash
# Create a test app-of-apps pointing to your feature branch
oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: private-ai-demo-test
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://github.com/adnan-drina/private-ai-demo.git
    targetRevision: feature/my-test  # ← Test branch
    path: gitops/argocd/applications
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
EOF
```

## 🎓 Key Takeaways

1. **App-of-Apps = Two-Level Config**
   - Root app controls Application definitions
   - Individual apps control resource manifests

2. **Branch Mismatches Break Everything**
   - Root app on wrong branch = outdated Application definitions
   - Application on wrong branch = outdated resource manifests

3. **Sync Order is Critical**
   - Root first, children second
   - Wait for Application CRDs to update between steps

4. **Duplicate Files Cause Confusion**
   - Use app-of-apps pattern exclusively
   - Remove standalone application files

---

**Document Version:** 1.0  
**Next Review:** After app-of-apps sync is verified working

