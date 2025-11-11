# Branch Strategy for Multi-Cluster Deployments

**Last Updated**: November 11, 2025  
**Status**: ✅ Active

---

## Overview

This project uses a **branch-per-cluster** strategy to enable parallel development and testing across multiple OpenShift environments without conflicts.

## Branch → Cluster Mapping

| Branch | Cluster | Purpose | ArgoCD Target |
|--------|---------|---------|---------------|
| `main` | **sandbox5294** (cluster-gmgrr) | Production/Stable | `targetRevision: main` |
| `feature/gitops-refactoring-dynamic-machinesets` | **sandbox1194** (cluster-zpqdx) | Testing/Validation | `targetRevision: feature/gitops-refactoring-dynamic-machinesets` |

### Cluster Details

#### sandbox5294 (Production)
```
Cluster: cluster-gmgrr.gmgrr.sandbox5294.opentlc.com
Status:  Stable, fully deployed
Stages:  0, 1, 2, 3 (all operational)
GPU:     2x nodes (g6.4xlarge, g6.12xlarge) - RUNNING
Branch:  main
Purpose: Production workloads, stable features
```

#### sandbox1194 (Testing)
```
Cluster: cluster-zpqdx.zpqdx.sandbox1194.opentlc.com
Status:  Fresh, validation in progress
Stages:  0 (partial), 1-3 (pending)
GPU:     Dynamic generation being tested
Branch:  feature/gitops-refactoring-dynamic-machinesets
Purpose: Reproducibility testing, GitOps refactoring validation
```

---

## Why This Strategy?

### Problem Without Branch Separation

```
┌──────────────────────────────────────────────────────┐
│  SINGLE BRANCH (main)                                │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ArgoCD on sandbox5294  ←──┐                        │
│                            │  Both pointing to       │
│  ArgoCD on sandbox1194  ←──┘  same branch!          │
│                                                      │
│  Result:                                             │
│  ❌ Apps overwrite each other                        │
│  ❌ Configs conflict                                 │
│  ❌ Can't test changes safely                        │
│  ❌ Breaking changes affect production               │
└──────────────────────────────────────────────────────┘
```

### Solution: Branch Per Cluster

```
┌─────────────────────────────────────────────────────────────┐
│  TWO BRANCHES                                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  sandbox5294 (cluster-gmgrr)  ←── main branch              │
│   ├─ Stable production code                                │
│   ├─ ArgoCD: targetRevision: main                          │
│   └─ No impact from testing                                │
│                                                             │
│  sandbox1194 (cluster-zpqdx)  ←── feature branch           │
│   ├─ Testing/validation code                               │
│   ├─ ArgoCD: targetRevision: feature/gitops-refactoring... │
│   └─ Can break without affecting production                │
│                                                             │
│  Result:                                                    │
│  ✅ Complete isolation                                      │
│  ✅ Safe testing                                            │
│  ✅ No conflicts                                            │
│  ✅ Merge feature → main when validated                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Workflow

### 1. Development on sandbox5294 (main)

```bash
# Work on production cluster
git checkout main

# Make changes, test, commit
git add <files>
git commit -m "fix: Production fix for sandbox5294"
git push origin main

# ArgoCD on sandbox5294 auto-syncs from main
```

**Use Cases**:
- Bug fixes in production
- Feature enhancements to deployed stages
- Configuration tuning
- Dashboard updates
- Stable improvements

### 2. Testing on sandbox1194 (feature branch)

```bash
# Work on test cluster
git checkout feature/gitops-refactoring-dynamic-machinesets

# Make changes, test, commit
git add <files>
git commit -m "refactor: Dynamic GPU MachineSets for sandbox1194"
git push origin feature/gitops-refactoring-dynamic-machinesets

# ArgoCD on sandbox1194 auto-syncs from feature branch
```

**Use Cases**:
- Reproducibility validation
- GitOps refactoring
- Breaking changes
- Infrastructure improvements
- Fresh deployment testing

### 3. Merging Back to Main

After successful validation on sandbox1194:

```bash
# Ensure both branches are up to date
git checkout main
git pull origin main

git checkout feature/gitops-refactoring-dynamic-machinesets
git pull origin feature/gitops-refactoring-dynamic-machinesets

# Merge feature to main
git checkout main
git merge feature/gitops-refactoring-dynamic-machinesets

# Resolve any conflicts
# Test on sandbox5294
# Push to main

git push origin main

# Delete feature branch (optional)
git branch -d feature/gitops-refactoring-dynamic-machinesets
git push origin --delete feature/gitops-refactoring-dynamic-machinesets
```

---

## ArgoCD Configuration

### For sandbox5294 Apps

```yaml
# gitops/argocd/applications/*/app-stage*.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-stage01-model-serving
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://github.com/adnan-drina/private-ai-demo
    targetRevision: main  # ← Points to main branch
    path: gitops/stage01-model-serving
```

### For sandbox1194 Apps

```yaml
# gitops/argocd/applications/*/app-stage*.yaml (on feature branch)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-stage01-model-serving
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://github.com/adnan-drina/private-ai-demo
    targetRevision: feature/gitops-refactoring-dynamic-machinesets  # ← Points to feature branch
    path: gitops/stage01-model-serving
```

---

## Commit Message Convention

To track which cluster a commit is for:

### Main Branch Commits (sandbox5294)

```bash
git commit -m "fix: Update Grafana dashboard

Cluster: sandbox5294 (cluster-gmgrr)
Branch: main"
```

### Feature Branch Commits (sandbox1194)

```bash
git commit -m "refactor: Dynamic GPU MachineSet generation

Cluster: sandbox1194 (cluster-zpqdx)
Branch: feature/gitops-refactoring-dynamic-machinesets"
```

---

## Branch Lifecycle

### Current State

```
main
├─ e9fc7e8 - fix: Update Stage 3 MinIO credentials and GPU dashboard queries
├─ df332c9 - Merge feature/stage3-implementation
└─ (production-ready, deployed on sandbox5294)

feature/gitops-refactoring-dynamic-machinesets
├─ 2e0e800 - docs: Add validation report and README
├─ 2d8f796 - refactor: Implement dynamic GPU MachineSet generation
└─ (testing on sandbox1194)
```

### Planned Merge

After successful validation:
1. Complete Stage 0 validation on sandbox1194
2. Test Stage 1-3 deployments
3. Verify end-to-end reproducibility
4. Merge feature branch to main
5. Deploy dynamic MachineSets on sandbox5294

---

## File Organization

### Files Changed on Main (sandbox5294 only)

```
gitops/stage03-model-monitoring/guidellm/
├─ cronjob-guidellm-daily.yaml          (MinIO secret fix)
└─ cronjob-guidellm-weekly.yaml         (MinIO secret fix)

gitops/stage03-model-monitoring/observability/
├─ grafana-dashboard-gpu-infra.yaml     (Query improvements)
└─ grafana-dashboard-guidellm.yaml      (Dashboard updates)
```

### Files Changed on Feature Branch (sandbox1194)

```
gitops/stage00-ai-platform/gpu-infrastructure/
├─ rbac-machineset-job.yaml              (NEW - dynamic generation)
├─ configmap-machineset-script.yaml      (NEW - generation script)
├─ job-generate-gpu-machineset.yaml      (NEW - job definition)
├─ kustomization.yaml                    (MODIFIED - use dynamic approach)
├─ README.md                             (NEW - documentation)
├─ machineset-cluster-gmgrr-*.yaml       (DELETED - hardcoded files)

docs/00-VALIDATION/
├─ GITOPS-REFACTORING-VALIDATION.md      (NEW - test results)
└─ BRANCH-STRATEGY.md                    (NEW - this file)
```

---

## Best Practices

### ✅ DO

- **Always check current branch** before making changes
  ```bash
  git branch --show-current
  ```

- **Commit cluster-specific changes to correct branch**
  - sandbox5294 work → main
  - sandbox1194 work → feature branch

- **Document which cluster** in commit messages

- **Keep branches synchronized** regularly
  ```bash
  git pull origin main
  git pull origin feature/gitops-refactoring-dynamic-machinesets
  ```

- **Test feature branch changes** on sandbox1194 before merging

### ❌ DON'T

- **Don't commit sandbox1194 changes to main** (breaks production)
- **Don't commit sandbox5294 changes to feature branch** (pollutes testing)
- **Don't update ArgoCD targetRevision** without coordinating
- **Don't force push** to main (breaks production)
- **Don't merge without validation** (untested code in production)

---

## Switching Between Clusters

### Quick Reference

```bash
# Working on sandbox5294 (production)?
git checkout main
oc login https://api.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com:6443

# Working on sandbox1194 (testing)?
git checkout feature/gitops-refactoring-dynamic-machinesets
oc login https://api.cluster-zpqdx.zpqdx.sandbox1194.opentlc.com:6443
```

### Shell Prompt Tip

Add to `.bashrc` or `.zshrc`:

```bash
parse_git_branch() {
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

export PS1="\u@\h \W\[\033[32m\]\$(parse_git_branch)\[\033[00m\] $ "
```

Shows current branch in prompt: `user@host dir (main) $`

---

## Troubleshooting

### Wrong Branch for Cluster

**Symptom**: Changes don't appear after ArgoCD sync

**Solution**:
```bash
# Check which cluster you're on
oc whoami --show-server

# Check which branch you're on
git branch --show-current

# If mismatched, switch to correct branch
git checkout <correct-branch>
```

### Accidentally Committed to Wrong Branch

**Solution**:
```bash
# Don't push yet! Cherry-pick to correct branch
git log -1  # Copy commit hash

git checkout <correct-branch>
git cherry-pick <commit-hash>
git push origin <correct-branch>

# Go back to wrong branch and reset
git checkout <wrong-branch>
git reset --hard HEAD~1  # Remove last commit
```

### ArgoCD Out of Sync

**Solution**:
```bash
# Verify ArgoCD app configuration
oc get application -n openshift-gitops app-stage01-model-serving -o yaml | grep targetRevision

# Should match:
# - main (for sandbox5294)
# - feature/gitops-refactoring-dynamic-machinesets (for sandbox1194)
```

---

## Related Documentation

- [GitOps Refactoring Validation](GITOPS-REFACTORING-VALIDATION.md) - Test results from sandbox1194
- [GPU Infrastructure README](../../gitops/stage00-ai-platform/gpu-infrastructure/README.md) - Dynamic MachineSet details
- [Main README](../../README.md) - Project overview

---

## Summary

| Aspect | sandbox5294 | sandbox1194 |
|--------|-------------|-------------|
| **Cluster** | cluster-gmgrr | cluster-zpqdx |
| **Branch** | main | feature/gitops-refactoring-dynamic-machinesets |
| **Purpose** | Production | Testing/Validation |
| **ArgoCD** | targetRevision: main | targetRevision: feature/... |
| **Stability** | Stable | Experimental |
| **Changes** | Production fixes | Refactoring, validation |

**Key Principle**: Never mix cluster-specific changes across branches to maintain clean separation and safe testing.

