# ArgoCD GitOps Alignment - Best Practices

> **Last Updated:** 2025-11-08  
> **Status:** Active  
> **Purpose:** Document ArgoCD application alignment with GitOps best practices

## 📋 Overview

This document outlines the GitOps best practices implemented for ArgoCD applications in the Private AI Demo project, focusing on handling operator-managed resources, immutable fields, and branch management.

## 🎯 GitOps Principles

1. **Single Source of Truth** - Git is the only source of truth for desired state
2. **Declarative Configuration** - All infrastructure defined declaratively
3. **Automated Sync** - Changes automatically propagated (with controls)
4. **Observability** - Clear visibility into drift and sync status
5. **Operator Tolerance** - Gracefully handle operator-managed mutations

## 🔧 ArgoCD Application Configuration

### Standard Sync Options

All applications should include these base `syncOptions`:

```yaml
syncOptions:
  - CreateNamespace=true           # Auto-create target namespace
  - PruneLast=true                 # Delete resources last during prune
  - RespectIgnoreDifferences=true  # Honor ignoreDifferences config
  - Replace=true                   # Recreate on immutable field changes
  - ApplyOutOfSyncOnly=true       # Only apply resources that differ
```

**Rationale:**
- `CreateNamespace=true`: Ensures namespace exists before resources
- `PruneLast=true`: Prevents orphaned resources
- `RespectIgnoreDifferences=true`: Allows operator tolerance
- `Replace=true`: Handles immutable field conflicts (selectors, etc.)
- `ApplyOutOfSyncOnly=true`: Reduces unnecessary API calls

### Automated Sync Policy

```yaml
syncPolicy:
  automated:
    prune: false      # Manual prune for safety (data-bearing resources)
    selfHeal: false   # Manual heal for controlled changes
```

**Conservative Approach:**
- `prune: false`: Prevents accidental deletion of resources with data (PVCs, Secrets)
- `selfHeal: false`: Allows manual intervention for critical changes
- **Exception**: Stage00 apps can use `selfHeal: true` for infrastructure

### Retry Configuration

```yaml
retry:
  limit: 3
  backoff:
    duration: 5s
    factor: 2
    maxDuration: 3m
```

## 📐 Ignore Differences Patterns

### Universal Patterns

Apply to all applications:

```yaml
ignoreDifferences:
  # Ignore managed fields metadata (Kubernetes internal)
  - group: "*"
    kind: "*"
    jsonPointers:
      - /metadata/managedFields
      - /metadata/resourceVersion
      - /metadata/generation
```

### Operator-Managed Resources

#### DataScienceCluster (RHOAI)

```yaml
- group: datasciencecluster.opendatahub.io
  kind: DataScienceCluster
  jsonPointers:
    - /status
    - /metadata/annotations
```

#### Istio/Knative Gateways

```yaml
- group: networking.istio.io
  kind: Gateway
  jsonPointers:
    - /spec               # Operator mutates spec
    - /status
    - /metadata/annotations
    - /metadata/labels
```

**Why?** Istio Service Mesh operator continuously reconciles gateways based on runtime state.

#### OpenShift Routes

```yaml
- group: route.openshift.io
  kind: Route
  jsonPointers:
    - /spec/host         # Cluster-generated hostname
    - /spec/tls/insecureEdgeTerminationPolicy
    - /status
    - /metadata/annotations
```

**Why?** OpenShift Ingress Controller injects host, TLS config, and annotations.

### Application-Specific Resources

#### Deployments (with HPA)

```yaml
- group: apps
  kind: Deployment
  jsonPointers:
    - /spec/replicas      # HPA manages replicas
```

#### Deployments (with Immutable Selectors)

```yaml
- group: apps
  kind: Deployment
  jsonPointers:
    - /spec/selector      # Immutable after creation
    - /spec/template/metadata/labels  # Must match selector
```

**Why?** Kubernetes prevents selector changes. Use `Replace=true` to recreate.

#### PersistentVolumeClaims

```yaml
- group: ""
  kind: PersistentVolumeClaim
  jsonPointers:
    - /spec/volumeName    # Bound after provisioning
    - /spec/volumeMode
    - /status
```

#### KFP/Tekton PipelineRuns

```yaml
- group: tekton.dev
  kind: PipelineRun
  jsonPointers:
    - /status
- group: tekton.dev
  kind: TaskRun
  jsonPointers:
    - /status
```

**Why?** PipelineRun/TaskRun status changes continuously during execution.

#### Custom Resources (Operators)

```yaml
# LlamaStack Operator
- group: llamastack.io
  kind: LlamaStackDistribution
  jsonPointers:
    - /status
    - /metadata/resourceVersion

# Docling Operator
- group: docling.io
  kind: DoclingServe
  jsonPointers:
    - /status
    - /spec/replicas              # If HPA-managed
    - /metadata/resourceVersion
```

## 🎯 Branch Management Strategy

### Production (`main` branch)

All production applications should target `main`:

```yaml
source:
  repoURL: https://github.com/adnan-drina/private-ai-demo.git
  targetRevision: main
  path: gitops/stage0X-component-name
```

### Development/Feature Branches

During active development, temporarily target feature branches:

```yaml
source:
  targetRevision: feature/stage2-implementation
```

**⚠️ Important:** Merge to `main` and update `targetRevision` before production deployment.

### Branch Lifecycle

1. **Development**: Point ArgoCD app to feature branch
2. **Testing**: Validate changes in feature branch
3. **Merge**: PR to `main` after validation
4. **Update ArgoCD**: Change `targetRevision` to `main`
5. **Sync**: ArgoCD automatically applies from `main`

## 🔍 Troubleshooting Common Issues

### Issue 1: OutOfSync (Healthy) with Operator-Managed Resources

**Symptom:** App shows OutOfSync but resources are Healthy

**Root Cause:** Operator mutates spec fields (Istio Gateway, Routes)

**Solution:** Add `ignoreDifferences` for the specific fields:

```yaml
ignoreDifferences:
  - group: networking.istio.io
    kind: Gateway
    jsonPointers:
      - /spec
      - /status
```

### Issue 2: ComparisonError (Manifest Generation Failed)

**Symptom:** ArgoCD can't render manifests

**Root Cause:** Application points to outdated branch with missing files

**Solution:** Update `targetRevision` to current branch:

```yaml
source:
  targetRevision: main  # or feature/current-branch
```

### Issue 3: SyncError (Immutable Field)

**Symptom:** `field is immutable` error during sync

**Root Cause:** Kubernetes prevents changes to immutable fields (selectors)

**Solution:** Two options:

**Option A:** Add `Replace=true` to recreate resource:
```yaml
syncOptions:
  - Replace=true
```

**Option B:** Ignore the immutable field (if operator-managed):
```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /spec/selector
```

### Issue 4: Deployment Selector Mismatch

**Symptom:** `selector does not match template labels`

**Root Cause:** Git manifest selector differs from live resource

**Solution:**
1. Check live resource: `oc get deployment <name> -o yaml | grep -A5 selector`
2. Update Git manifest to match live selector
3. Commit and sync

**Or recreate:**
```bash
oc delete deployment <name>
# ArgoCD recreates with Git selector
```

## 📊 Application Status Summary

### Stage 00: AI Platform Infrastructure

| App | Target Branch | Automated | Status Goal |
|-----|---------------|-----------|-------------|
| stage00-datasciencecluster | `main` | selfHeal: true | Synced/Healthy |
| stage00-gpu-infrastructure | `main` | selfHeal: true | Synced/Healthy |
| stage00-minio | `main` | selfHeal: true, prune: false | Synced/Healthy |
| stage00-operators | `main` | selfHeal: false, prune: false | Synced/Healthy |

### Stage 01: Model Serving

| App | Target Branch | Automated | Status Goal |
|-----|---------------|-----------|-------------|
| stage01-model-serving | `main` | selfHeal: false, prune: false | Synced/Healthy |
| stage01-model-registry | `main` | selfHeal: false, prune: false | Synced/Healthy |

### Stage 02: Model Alignment (RAG)

| App | Target Branch | Automated | Status Goal |
|-----|---------------|-----------|-------------|
| stage02-model-alignment | `main` | selfHeal: false, prune: false | Synced/Healthy |

## ✅ Checklist for New Applications

When creating a new ArgoCD application:

- [ ] Set `targetRevision: main` for production apps
- [ ] Include standard `syncOptions` (CreateNamespace, PruneLast, etc.)
- [ ] Set `automated.prune: false` for data-bearing apps
- [ ] Set `automated.selfHeal: false` for manual control
- [ ] Add `ignoreDifferences` for operator-managed resources
- [ ] Add `ignoreDifferences` for universal metadata fields
- [ ] Configure retry policy (limit: 3, backoff)
- [ ] Document in `info` section (purpose, dependencies)
- [ ] Test sync in non-production namespace first
- [ ] Verify no sensitive data in Git (use SealedSecrets/ExternalSecrets)

## 🔐 Security Best Practices

1. **No Secrets in Git**: Use SealedSecrets or ExternalSecrets Operator
2. **Least Privilege**: ArgoCD ServiceAccount should have minimal RBAC
3. **Audit Logging**: Enable ArgoCD audit logs for compliance
4. **Branch Protection**: Require PR reviews for `main` branch
5. **Signed Commits**: Enforce GPG-signed commits for production changes

## 📚 References

- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [GitOps Principles](https://opengitops.dev/)
- [Kubernetes Immutable Fields](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#selector)
- [OpenShift GitOps Operator](https://docs.openshift.com/gitops/latest/)

---

**Document Version:** 1.0  
**Last Reviewed:** 2025-11-08  
**Next Review:** Quarterly or on major infrastructure changes

