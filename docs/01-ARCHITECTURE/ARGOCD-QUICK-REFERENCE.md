# ArgoCD Quick Reference Card

## 🚀 Quick Actions

### Sync All Applications
```bash
argocd app sync -l stage=00
argocd app sync -l stage=01
argocd app sync stage02-model-alignment
```

### Check Status
```bash
argocd app list
argocd app get stage02-model-alignment
```

### Force Refresh
```bash
argocd app get stage02-model-alignment --refresh
```

## 🎯 Common Issues & Fixes

### OutOfSync (Healthy) - Operator-Managed Resources
**Status:** Acceptable  
**Action:** None required (resources are healthy)  
**Reason:** Operators continuously reconcile state

### ComparisonError - Branch Mismatch
**Status:** Critical  
**Fix:** Update `targetRevision` to correct branch  
**Location:** `gitops/argocd/applications/stageXX/*.yaml`

### SyncError - Immutable Field
**Status:** Requires action  
**Fix Option 1:** Add to `ignoreDifferences`  
**Fix Option 2:** Delete resource, let ArgoCD recreate

## 📋 ignoreDifferences Quick Reference

### Routes (OpenShift)
```yaml
- group: route.openshift.io
  kind: Route
  jsonPointers:
    - /spec/host
    - /status
```

### Deployments (Immutable)
```yaml
- group: apps
  kind: Deployment
  jsonPointers:
    - /spec/selector
    - /spec/template/metadata/labels
```

### Operator CRs
```yaml
- group: <operator-group>
  kind: <CustomResource>
  jsonPointers:
    - /status
    - /metadata/resourceVersion
```

## 🔧 Emergency Commands

### Recreate Deployment (Selector Mismatch)
```bash
oc delete deployment <name> -n private-ai-demo
# ArgoCD recreates from Git
```

### Force Sync (Ignore Errors)
```bash
argocd app sync <app-name> --force
```

### Hard Refresh
```bash
argocd app get <app-name> --hard-refresh
```

## 📚 Full Documentation

- **Best Practices:** `docs/01-ARCHITECTURE/ARGOCD-GITOPS-ALIGNMENT.md`
- **Fix Details:** `docs/01-ARCHITECTURE/ARGOCD-SYNC-STATUS-FIX.md`
- **App Definitions:** `gitops/argocd/applications/`

