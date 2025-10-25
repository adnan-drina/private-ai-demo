# Stage 01: Model Serving - App-of-Apps Structure

## Architecture Overview

This directory contains the **App-of-Apps** pattern for Stage 01 (Model Serving), following **Red Hat GitOps best practices** of **one ArgoCD Application per namespace**.

## ArgoCD Applications

### 1. `stage01-model-serving` (App-of-Apps)
- **Type**: App-of-Apps (parent)
- **Purpose**: Orchestrates the two child applications
- **Path**: `gitops-apps/stage01/`
- **Sync Wave**: 1

### 2. `stage01-model-registry`
- **Namespace**: `rhoai-model-registries`
- **Purpose**: Model Registry infrastructure
- **Path**: `gitops/stage01-model-serving/model-registry-app/`
- **Sync Wave**: 2
- **Resources**:
  - MySQL database (Deployment, Service, PVC, ConfigMap, Secret)
  - ModelRegistry CR
  - RBAC (cross-namespace access for pipelines and dashboard)

### 3. `stage01-application`
- **Namespace**: `private-ai-demo`
- **Purpose**: MLOps pipeline and model serving workload
- **Path**: `gitops/stage01-model-serving/application/`
- **Sync Wave**: 3
- **Resources**:
  - Namespace infrastructure (Namespace, LimitRange, ResourceQuota, ServiceAccount)
  - Model Registry ConfigMap (used by pipelines)
  - NetworkPolicies (allow access to Model Registry)
  - ImageStreams (for ModelCar images)
  - PVC workspaces (for pipeline artifacts)
  - Tekton Pipelines (ModelCar build & deploy pipeline)
  - vLLM (InferenceServices, ServingRuntimes, PVCs)
  - Workbench/Notebooks (testing and development)

## Design Rationale

### Namespace-Based Grouping

Following Red Hat's recommendation, resources are grouped by namespace:
- **Benefits**:
  - ✅ Clear namespace boundaries
  - ✅ Easier RBAC management
  - ✅ Better isolation
  - ✅ Simpler troubleshooting
  - ✅ Logical resource grouping
  - ✅ Independent lifecycle management

### Cross-Namespace Dependencies

The Model Registry ConfigMap is deployed in `private-ai-demo` namespace (where pipelines run) rather than `rhoai-model-registries` because:
1. It's consumed by Tekton pipelines in `private-ai-demo`
2. It contains connection information, not Model Registry infrastructure
3. Following the principle: "deploy resources where they're consumed"

## Sync Waves

```
Wave 1: App-of-Apps (creates child applications)
  └─> Wave 2: Model Registry Infrastructure (MySQL, ModelRegistry CR)
       └─> Wave 3: Application Workload (Pipelines, vLLM, Workbench)
```

## References

- [Red Hat OpenShift GitOps Recommended Practices](https://developers.redhat.com/blog/2025/03/05/openshift-gitops-recommended-practices)
- [GitOps Directory Structure Best Practices](https://developers.redhat.com/articles/2022/09/07/how-set-your-gitops-directory-structure)
- [Managing Namespaces in Multi-Tenant Clusters](https://developers.redhat.com/articles/2022/04/13/manage-namespaces-multitenant-clusters-argo-cd-kustomize-and-helm)
