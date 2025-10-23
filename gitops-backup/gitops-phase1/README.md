# Private AI Demo - GitOps Configuration

This directory contains all Kubernetes manifests for the Private AI Demo, organized using Kustomize.

---

## 📁 Structure

```
gitops/
├── base/                    # Base resources (no stage-specific config)
│   ├── namespace/          # Core namespaces
│   ├── platform/           # DataScienceCluster base config
│   ├── secrets/            # Secrets (HuggingFace tokens, etc.)
│   └── vllm/               # vLLM InferenceServices
│
├── components/             # Reusable components (referenced by overlays)
│   ├── [stage1-components]/
│   ├── [stage2-components]/
│   └── [stage3-components]/
│
└── overlays/               # Stage-specific overlays (progressive inheritance)
    ├── stage1/             # Stage 1: Sovereign AI
    ├── stage2/             # Stage 1 + 2: Private Data RAG
    └── stage3/             # Stage 1 + 2 + 3: Enterprise Agentic AI
```

---

## 🎯 Component Matrix

| Component | Stage | Description | Dependencies |
|-----------|-------|-------------|--------------|
| **gpu-provisioning** | 1 | MachineConfigs for GPU nodes | - |
| **model-registry** | 1 | Model Registry with MySQL backend | gpu-provisioning |
| **model-loader** | 1 | Model download jobs | gpu-provisioning |
| **benchmarking** | 1 | Model performance benchmarks | model-loader |
| **milvus** | 2 | Vector database for RAG | - |
| **llama-stack** | 2 | RAG orchestration layer | milvus |
| **docling-pipeline** | 2 | PDF processing pipelines | llama-stack |
| **workbench** | 2 | JupyterLab environment | - |
| **acme-agent** | 3 | ACME LithoOps Calibration Agent | llama-stack, milvus |
| **mcp-servers** | 3 | Model Context Protocol servers | - |
| **rbac** | All | Cross-namespace permissions | - |

---

## 🔄 Progressive Overlays

The overlays use **progressive inheritance**:

```
Stage 1: Base + Stage 1 patches
         ↓
Stage 2: Stage 1 + Stage 2 patches (inherits Stage 1)
         ↓
Stage 3: Stage 2 + Stage 3 patches (inherits Stage 1 + 2)
```

### Stage 1: Sovereign AI
- Deploys: GPU provisioning, vLLM, Model Registry
- DSC Patch: Enables `modelregistry` component

### Stage 2: Private Data RAG
- Inherits: All Stage 1 components
- Adds: Milvus, Llama Stack, Docling, Workbenches
- DSC Patch: Enables `workbenches` component

### Stage 3: Enterprise Agentic AI
- Inherits: All Stage 1 + 2 components
- Adds: ACME Agent, MCP Servers
- DSC Patch: None (uses existing components)

---

## 🚀 Deployment

### Using deploy.sh Scripts (Recommended for Demos)

Each stage has a `deploy.sh` script that handles prerequisites, waiting, and logging:

```bash
# Stage 1
cd stage1-sovereign-ai && ./deploy.sh

# Stage 2 (requires Stage 1)
cd stage2-private-data-rag && ./deploy.sh

# Stage 3 (requires Stage 1 + 2)
cd stage3-enterprise-mcp && ./deploy.sh
```

### Using Kustomize Directly

For GitOps tools (ArgoCD, Flux) or manual deployment:

```bash
# Stage 1 only
oc apply -k gitops/overlays/stage1

# Stage 2 (includes Stage 1)
oc apply -k gitops/overlays/stage2

# Stage 3 (includes Stage 1 + 2)
oc apply -k gitops/overlays/stage3
```

---

## 🔍 Testing Overlays

Preview what will be deployed:

```bash
# Stage 1
kustomize build gitops/overlays/stage1 > /tmp/stage1.yaml
cat /tmp/stage1.yaml

# Stage 2 (includes Stage 1)
kustomize build gitops/overlays/stage2 > /tmp/stage2.yaml
diff /tmp/stage1.yaml /tmp/stage2.yaml  # See what Stage 2 adds

# Stage 3 (includes Stage 1 + 2)
kustomize build gitops/overlays/stage3 > /tmp/stage3.yaml
diff /tmp/stage2.yaml /tmp/stage3.yaml  # See what Stage 3 adds
```

Verify DataScienceCluster patches are merged correctly:

```bash
# Stage 1: Should show modelregistry: Managed
kustomize build gitops/overlays/stage1 | grep -A 20 "kind: DataScienceCluster"

# Stage 2: Should show modelregistry + workbenches: Managed
kustomize build gitops/overlays/stage2 | grep -A 25 "kind: DataScienceCluster"

# Stage 3: Should show all components from Stage 1 + 2
kustomize build gitops/overlays/stage3 | grep -A 25 "kind: DataScienceCluster"
```

---

## 🛠️ Managing Shared Resources

### DataScienceCluster (DSC)

The DSC is managed through **strategic merge patches**:

**Base:** `gitops/base/platform/datasciencecluster.yaml`
- Minimal configuration
- Only dashboard and kserve enabled

**Stage 1 Patch:** `gitops/overlays/stage1/datasciencecluster-patch.yaml`
- Enables: `modelregistry`

**Stage 2 Patch:** `gitops/overlays/stage2/datasciencecluster-patch.yaml`
- Enables: `workbenches`
- Inherits: `modelregistry` (from Stage 1)

**Result:** Kustomize merges all patches, no conflicts! ✅

### Other Shared Resources

The same pattern applies to:
- **ConfigMaps**: Each stage can add keys without overwriting
- **RBAC**: Each stage can add permissions incrementally
- **NetworkPolicies**: Each stage can add rules

---

## 📝 Best Practices

### ✅ DO

1. **Use overlays for deployment** - They're the source of truth
2. **Test with `kustomize build`** - Preview before applying
3. **Keep patches minimal** - Only specify what changes
4. **Document dependencies** - In component READMEs
5. **Use `deploy.sh` for demos** - Better UX with logging

### ❌ DON'T

1. **Don't modify base resources directly** - Use patches
2. **Don't create circular dependencies** - Keep stage order
3. **Don't skip stages** - Stage 2 requires Stage 1, etc.
4. **Don't duplicate manifests** - Use inheritance
5. **Don't patch what you don't need** - Keep it minimal

---

## 🔧 Adding a New Component

### 1. Create the component

```bash
mkdir -p gitops/components/my-new-component
cd gitops/components/my-new-component
# Add your manifests
```

### 2. Add to appropriate overlay

Edit `gitops/overlays/stage2/kustomization.yaml`:

```yaml
resources:
  - ../stage1
  - ../../components/my-new-component  # Add this
```

### 3. Test the build

```bash
kustomize build gitops/overlays/stage2
```

### 4. Update deploy.sh

Add deployment logic to `stage2-private-data-rag/deploy.sh`

---

## 📚 Related Documentation

- **`docs/GITOPS-ARCHITECTURE-DECISION.md`** - Why centralized GitOps
- **`docs/GITOPS-INCREMENTAL-STAGES.md`** - How progressive overlays work
- **`docs/MODEL-REGISTRY-DEPLOYMENT-GUIDE.md`** - Model Registry specifics

---

## 🎯 Quick Reference

| Task | Command |
|------|---------|
| Deploy Stage 1 | `cd stage1-sovereign-ai && ./deploy.sh` |
| Deploy Stage 2 | `cd stage2-private-data-rag && ./deploy.sh` |
| Deploy Stage 3 | `cd stage3-enterprise-mcp && ./deploy.sh` |
| Preview Stage 1 | `kustomize build gitops/overlays/stage1` |
| Preview Stage 2 | `kustomize build gitops/overlays/stage2` |
| Test DSC merge | `kustomize build gitops/overlays/stage2 \| grep -A 25 DataScienceCluster` |
| Apply with kubectl | `oc apply -k gitops/overlays/stage2` |

---

## Summary

- ✅ **Single GitOps directory** for all stages
- ✅ **Progressive overlays** with inheritance (stage2 includes stage1, stage3 includes stage2)
- ✅ **Strategic merge patches** for shared resources (no conflicts!)
- ✅ **Component-based architecture** for reusability
- ✅ **Kustomize-native** for GitOps tooling compatibility
- ✅ **Demo-friendly** with `deploy.sh` scripts for better UX

**This structure ensures clean, conflict-free, incremental deployments! 🎉**
