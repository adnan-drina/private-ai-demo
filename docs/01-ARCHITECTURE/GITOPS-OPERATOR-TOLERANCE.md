# GitOps Operator-Managed Resource Tolerance

## Overview

This document describes how our ArgoCD applications are configured to properly handle operator-managed resources, following Red Hat best practices for GitOps with OpenShift operators.

## Problem Statement

OpenShift and Red Hat OpenShift AI (RHOAI) operators frequently update resources they manage, including:
- Status fields
- Metadata annotations (tracking, reconciliation)
- Replica counts (autoscaling)
- Image references (operator-controlled versions)
- Service and Gateway specifications (Service Mesh)

When ArgoCD tracks these resources in Git, it detects these operator updates as "drift" and attempts to sync back to the Git state, creating conflicts with operator reconciliation.

## Solution: ignoreDifferences

ArgoCD's `ignoreDifferences` feature allows us to specify which fields should be ignored during drift detection, letting operators manage their resources while GitOps tracks the desired state.

---

## Stage 00: AI Platform Infrastructure

### DataScienceCluster Application

**File:** `gitops/argocd/applications/stage00/app-stage00-datasciencecluster.yaml`

**Ignored Resources:**

#### Namespace
```yaml
- kind: Namespace
  jsonPointers:
  - /metadata/annotations
```
- Operators add tracking annotations
- OpenShift adds quota/policy annotations

#### Gateway (Service Mesh)
```yaml
- group: networking.istio.io
  kind: Gateway
  jsonPointers:
  - /spec
  - /metadata/annotations
  - /metadata/labels
  - /status
```
- Service Mesh operator manages Gateway lifecycle
- Knative Serving modifies Gateway spec
- Status reflects mesh reconciliation state

#### Service (Service Mesh)
```yaml
- group: ""
  kind: Service
  jsonPointers:
  - /spec
  - /metadata/annotations
  - /metadata/labels
  - /status
```
- Service Mesh injects sidecar configuration
- Knative modifies service selectors
- Status reflects endpoint health

#### DataScienceCluster
```yaml
- group: datasciencecluster.opendatahub.io
  kind: DataScienceCluster
  jsonPointers:
  - /status
  - /metadata/annotations
```
- RHOAI operator manages component status
- Adds reconciliation annotations

#### ServiceMeshControlPlane
```yaml
- group: maistra.io
  kind: ServiceMeshControlPlane
  jsonPointers:
  - /status
  - /metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration
  - /metadata/annotations/platform.opendatahub.io
```
- Service Mesh operator manages control plane
- RHOAI integration adds annotations

---

### GPU Infrastructure Application

**File:** `gitops/argocd/applications/stage00/app-stage00-gpu-infrastructure.yaml`

**Ignored Resources:**

#### MachineSet
```yaml
- group: machine.openshift.io
  kind: MachineSet
  jsonPointers:
  - /status
  - /spec/replicas
  - /metadata/annotations
```
- Machine API operator manages status
- Autoscaling modifies replica count
- OpenShift adds machine annotations

#### ClusterPolicy (NVIDIA GPU Operator)
```yaml
- group: nvidia.com
  kind: ClusterPolicy
  jsonPointers:
  - /status
  - /metadata/annotations
```
- GPU Operator manages driver/toolkit deployment
- Status reflects GPU node readiness

#### NodeFeatureDiscovery
```yaml
- group: nfd.openshift.io
  kind: NodeFeatureDiscovery
  jsonPointers:
  - /status
  - /metadata/annotations
```
- NFD operator manages discovery pods
- Status reflects node feature detection

---

## Resource Removal

### knative-local-gateway Service

**File:** `gitops/stage00-ai-platform/datasciencecluster/istio-knative-gateways.yaml`

**Removed:** knative-local-gateway Service definition (17 lines)

**Reason:**
- Service Mesh operator fully manages this service
- Conflicts with operator-managed configuration
- Service Mesh creates and updates it automatically

**Result:**
- Service still exists (operator-managed)
- ArgoCD no longer attempts to manage it
- No drift warnings

---

## NodeFeatureDiscovery Alignment

**File:** `gitops/stage00-ai-platform/gpu-infrastructure/nodefeaturediscovery.yaml`

**Changes:**

### Removed Explicit Image Reference
```yaml
# REMOVED:
# image: registry.redhat.io/openshift4/ose-node-feature-discovery:v4.15.0-202410160958.p0.ga40c5c3.assembly.stream.el9
```

**Reason:**
- Operator manages image with valid digest
- Prevents digest conflict warnings
- Follows operator best practices

### Removed "device" from deviceLabelFields
```yaml
deviceLabelFields:
  - "vendor"
  # Removed "device" to emit vendor-level labels (pci-10de.present)
  # This is required for GPU Operator to recognize NVIDIA nodes
```

**Reason:**
- GPU Operator expects vendor-level labels
- Ensures `pci-10de.present` label is emitted
- Required for GPU node detection

---

## Benefits

### ArgoCD Dashboard
- ✅ Clean sync status (no constant drift warnings)
- ✅ Reduced manual intervention
- ✅ Focus on actual configuration changes

### Operator Compatibility
- ✅ No conflicts with operator reconciliation
- ✅ Operators can freely update managed fields
- ✅ GitOps tracks desired state, not runtime state

### Red Hat Best Practices
- ✅ Follows OpenShift GitOps guidance
- ✅ Aligns with RHOAI operator patterns
- ✅ Sustainable for long-term maintenance

---

## Guidelines for Future Resources

### When to Use ignoreDifferences

**Always ignore:**
- `/status` fields (operator-managed runtime state)
- `/metadata/annotations` (operator tracking, reconciliation)
- Operator-specific fields (e.g., `/spec/replicas` for autoscaled resources)

**Consider ignoring:**
- `/metadata/labels` (when operators add dynamic labels)
- Entire `/spec` (for fully operator-managed resources like Service Mesh)

### When to Remove from GitOps

**Remove resource from Git when:**
- Operator fully creates and manages it
- No user-configurable fields
- Conflicts with operator lifecycle
- Example: knative-local-gateway Service

### Testing ignoreDifferences

1. Apply the ArgoCD Application with `ignoreDifferences`
2. Observe ArgoCD sync status
3. Verify operator can still update the resource
4. Check for drift warnings in ArgoCD UI
5. Confirm resource functions correctly

---

## References

- [ArgoCD Diffing Customization](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/)
- [Red Hat OpenShift GitOps Best Practices](https://docs.openshift.com/gitops/)
- [RHOAI Operator Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai_self-managed/)

---

## Commit History

These improvements were implemented in the following commits:

1. `0dbb003` - Tolerate operator-managed infra drift
2. `44491f4` - Align NFD spec with operator defaults
3. `6ee55fd` - Ignore operator-managed gateway services
4. `9e1e7cf` - Broaden ignore rules for service and gateways
5. `648f32a` - Let ServiceMesh manage knative-local-gateway service

**Merged to:**
- `main` (commit `2da6b53`)
- `stage1-complete` (commit `02c118a`)

---

**Last Updated:** November 2, 2025  
**Applies to:** Stage 0 (AI Platform Infrastructure)

