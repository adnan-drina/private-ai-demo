# ArgoCD Test - Drift Detection

**Purpose**: Test current GitOps structure with ArgoCD to identify drift between Git and cluster state

**Phase**: Phase 1 of GitOps Refactoring  
**Status**: Testing  
**Branch**: `gitops-refactoring`

---

## Objective

Use ArgoCD to monitor the `private-ai-demo` namespace and identify:
- What's deployed in the cluster but NOT in Git
- What's in Git but NOT deployed
- What's different between Git and cluster (configuration drift)

This baseline understanding will inform the GitOps refactoring plan.

---

## Setup

### 1. Configure Git Remote (Required)

Before deploying the ArgoCD Application, you need to push this repository to GitHub:

```bash
# Add GitHub remote
git remote add origin https://github.com/YOUR_ORG/private-ai-demo.git

# Push branch
git push -u origin gitops-refactoring

# Update app-drift-detection.yaml with your repo URL
```

### 2. Deploy ArgoCD Application

```bash
# From project root
oc apply -f gitops/argocd/test/app-drift-detection.yaml
```

### 3. Access ArgoCD UI

```bash
# Get ArgoCD route
oc get route openshift-gitops-server -n openshift-gitops \
  -o jsonpath='{.spec.host}'

# Get admin password
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d && echo
```

---

## ArgoCD Application Configuration

**Application Name**: `private-ai-demo-drift-test`  
**Project**: `default` (we'll create custom projects later)  
**Source**: Current GitOps structure (`gitops/components/`)  
**Destination**: `private-ai-demo` namespace  
**Sync Policy**: Manual (no auto-sync, no auto-prune)

**Key Settings**:
- ✅ **Annotation Tracking** - Following Red Hat best practice
- ❌ **Auto-Sync Disabled** - We want to see drift, not fix it automatically
- ❌ **Auto-Prune Disabled** - Safety measure during testing
- ✅ **Diff Ignore** - Ignoring known dynamic fields (replicas, etc.)

---

## Expected Outcomes

### What We'll Discover

1. **Resources in Cluster but NOT in Git**
   - Manually created resources
   - Operator-managed resources
   - Resources created by deploy.sh scripts but not captured in GitOps

2. **Configuration Drift**
   - Resources modified manually after deployment
   - Different labels, annotations, or configurations
   - Environmental differences

3. **Resources in Git but NOT in Cluster**
   - Unused manifests
   - Test/development resources
   - Deprecated components

### ArgoCD Status Indicators

- **🟢 Synced**: Resource matches Git exactly
- **🟡 OutOfSync**: Resource exists but differs from Git
- **🔴 Missing**: Resource in Git but not in cluster
- **⚪ Unknown**: Resource health cannot be determined

---

## Analysis Process

### 1. Overall Application Status

Check the main application sync status:
- Is it Synced or OutOfSync?
- What percentage of resources match?

### 2. Resource-by-Resource Review

For each resource type, document:
- **Deployments**: Any manual scaling or configuration changes?
- **Services**: Any manual endpoint modifications?
- **ConfigMaps**: Any manual config updates?
- **Secrets**: Managed properly?
- **PVCs**: Storage differences?
- **InferenceServices**: KServe modifications?
- **Custom Resources**: Operator-managed resources appearing as "extra"?

### 3. Categorize Findings

**Category A: Legitimate Drift** (needs GitOps update)
- Manual changes that should be in Git
- Missing resources that should be added

**Category B: Ignore in ArgoCD** (expected differences)
- Operator-managed resources (add to ignoreDifferences)
- Dynamic fields (replicas, timestamps, etc.)
- Runtime-generated resources

**Category C: Cleanup Candidates** (no longer needed)
- Resources in Git but not deployed
- Deprecated components
- Test artifacts

---

## Documentation Template

Use this template to document findings:

```markdown
## Drift Analysis - [Date]

### Summary
- Total Resources: X
- Synced: Y
- OutOfSync: Z
- Missing: W

### Out of Sync Resources

#### [Resource Type/Name]
- **Status**: OutOfSync
- **Git State**: [description]
- **Cluster State**: [description]
- **Cause**: [manual change / operator / etc.]
- **Action**: [update Git / ignore / fix cluster]

### Missing Resources (in Git, not in cluster)

#### [Resource Type/Name]
- **Reason**: [never deployed / deleted / etc.]
- **Action**: [remove from Git / deploy / etc.]

### Extra Resources (in cluster, not in Git)

#### [Resource Type/Name]
- **Source**: [manual creation / operator / etc.]
- **Action**: [add to Git / ignore / cleanup]

### Recommendations

1. [Action item 1]
2. [Action item 2]
3. [Action item 3]
```

---

## Red Hat Best Practices Applied

Following [Red Hat OpenShift GitOps Recommended Practices](https://developers.redhat.com/blog/2025/03/05/openshift-gitops-recommended-practices):

✅ **Use annotation tracking** - Configured in Application  
✅ **Don't use Default AppProject** - Will create custom projects in Phase 2  
✅ **Version manifests** - Will implement in Phase 2  
✅ **Validate manifests** - Will add linting in Phase 2  

---

## Next Steps After Drift Analysis

1. **Document Findings** - Complete drift analysis document
2. **Update GitOps** - Add missing resources to Git
3. **Clean Deprecated** - Remove unused manifests
4. **Configure Ignores** - Add operator-managed resources to ignoreDifferences
5. **Move to Phase 2** - Start building new modular structure

---

## Troubleshooting

### Application Doesn't Sync

**Issue**: ArgoCD can't reach Git repository

**Solution**:
```bash
# Verify Git remote is configured
git remote -v

# Verify repository is accessible
curl -I https://github.com/YOUR_ORG/private-ai-demo
```

### Too Many OutOfSync Resources

**Issue**: Hundreds of resources showing as OutOfSync

**Solution**:
- This is expected! The goal is to discover drift
- Focus on application resources (Deployments, Services, etc.)
- Ignore operator-managed resources for now
- We'll configure proper ignoreDifferences in Phase 2

### Authentication Errors

**Issue**: ArgoCD can't authenticate to Git

**Solution**:
```bash
# For private repos, create SSH key or token
# Add to ArgoCD:
oc create secret generic private-repo-creds \
  --from-literal=url=https://github.com/YOUR_ORG/private-ai-demo \
  --from-literal=password=YOUR_TOKEN \
  -n openshift-gitops

oc label secret private-repo-creds \
  argocd.argoproj.io/secret-type=repository \
  -n openshift-gitops
```

---

## Files in This Directory

- `README.md` (this file) - Complete guide for drift detection
- `app-drift-detection.yaml` - ArgoCD Application manifest
- `kustomization.yaml` - Kustomize configuration (for easy deployment)

---

## References

- [Red Hat GitOps Best Practices](https://developers.redhat.com/blog/2025/03/05/openshift-gitops-recommended-practices)
- [ArgoCD Application Spec](https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/)
- [GitOps Refactoring Plan](/docs/GITOPS-REFACTORING-PLAN.md)

---

**Status**: Ready for testing  
**Next**: Push to GitHub and deploy ArgoCD Application  

