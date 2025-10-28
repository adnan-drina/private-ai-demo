# Privileged SCC Requirement for ModelCar Pipeline

## Overview

The ModelCar pipeline requires the `model-build-sa` service account to have access to the **`privileged`** Security Context Constraint (SCC) in order to build container images with Buildah.

## Why This is Required

### The Technical Problem
Buildah needs to:
1. Create user namespaces for container isolation
2. Write to `/proc/[pid]/uid_map` and `/proc/[pid]/gid_map` for UID/GID mapping
3. Perform privileged storage operations with `vfs` driver

These operations require Linux capabilities (`CAP_SETUID`, `CAP_SETGID`, `CAP_SYS_ADMIN`) that are **not granted** by the default `anyuid` SCC.

### Why the Standard SCC Doesn't Work
The `anyuid` SCC allows:
- ✅ Running as any UID (including root)
- ✅ Setting fsGroup and supplementalGroups

But it does **NOT** grant:
- ❌ `CAP_SETUID` / `CAP_SETGID` (required for user namespace setup)
- ❌ `CAP_SYS_ADMIN` (required for certain container storage operations)
- ❌ Privileged container mode

**Result:** Buildah fails immediately with:
```
Error: error writing "0 0 4294967295\n" to /proc/31/uid_map: 
write /proc/31/uid_map: operation not permitted
```

## Security Context

### What the Privileged Step Does
Only the **build-and-push** step in the pipeline runs privileged:
- Downloads model: ✅ **Unprivileged** (standard `anyuid` SCC)
- **Build & push: ⚠️ Privileged** (requires `privileged` SCC)
- Mirror to internal: ✅ **Unprivileged**
- Register model: ✅ **Unprivileged**

### Security Boundaries
1. **Dedicated Service Account:** `model-build-sa` is used **only** for the build task
2. **Single Namespace:** Scoped to `private-ai-demo` namespace only
3. **Single Task:** Only the `build-and-push-v2` task uses privileged mode
4. **No Network Escalation:** Build task does not access cluster API, only Quay.io
5. **Auditable:** All builds are tracked via Tekton PipelineRuns

## Cluster Admin Action Required

### Command
```bash
oc adm policy add-scc-to-user privileged -z model-build-sa -n private-ai-demo
```

### Verification
```bash
# Check SCC binding
oc get scc privileged -o yaml | grep -A 5 "users:"

# Should show:
# users:
# - system:serviceaccount:private-ai-demo:model-build-sa

# Verify SA can use privileged SCC
oc describe sa model-build-sa -n private-ai-demo
```

### Rollback (if needed)
```bash
oc adm policy remove-scc-from-user privileged -z model-build-sa -n private-ai-demo
```

## Alternative: Custom SCC (More Complex)

If granting `privileged` SCC is not acceptable, a custom SCC can be created with minimum required capabilities:

```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: buildah-scc
allowPrivilegedContainer: false
runAsUser:
  type: RunAsAny
fsGroup:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
allowedCapabilities:
  - SETUID
  - SETGID
  - SYS_ADMIN
  - SYS_CHROOT
```

**Note:** This approach is more complex and requires careful capability tuning. The `privileged` SCC is the standard OpenShift Pipelines pattern for Buildah/Kaniko builds.

## Comparison with Other Solutions

### Why Not Kaniko?
- Kaniko is designed for unprivileged builds **but**:
  - Does not support `vfs` storage driver
  - Requires `overlay2` which would use node ephemeral storage
  - 80GB+ images would cause node eviction

### Why Not External Build?
- Breaks GitOps model
- Requires external credentials management
- Adds latency and complexity

### Why Buildah with Privileged SCC?
- ✅ Standard Red Hat OpenShift Pipelines pattern
- ✅ Supports `vfs` driver on PVC (no ephemeral storage issues)
- ✅ Handles massive (80GB+) model images safely
- ✅ Well-documented and supported

## Production Considerations

### Monitoring
- Pipeline runs are tracked in Tekton dashboard
- Build logs are retained per Tekton retention policy
- All image pushes are logged to Quay.io audit trail

### Compliance
- Service account is namespace-scoped
- No cluster-admin privileges granted
- Only one specific task uses privileged mode
- PVC access is controlled by fsGroup (1000970000)

### References
- [Red Hat OpenShift Pipelines - Buildah Task](https://docs.openshift.com/pipelines/latest/create/working-with-pipelines.html)
- [Buildah on OpenShift](https://www.redhat.com/en/blog/building-container-images-buildah-openshift)
- [Security Context Constraints](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)

---

**Status:** ⏳ **Awaiting cluster admin approval**

**Contact:** Submit request via standard cluster admin workflow

**Priority:** HIGH - Blocks model import pipeline

