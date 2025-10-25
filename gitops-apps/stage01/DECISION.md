# ArgoCD Configuration Decision

**Date:** 2025-10-25  
**Decision:** Keep single ArgoCD app for now, refactor to App-of-Apps later

## Current State

### Single App Configuration

```yaml
name: stage01-model-serving
namespace: openshift-gitops
spec:
  source:
    repoURL: https://github.com/adnan-drina/private-ai-demo.git
    path: gitops/stage01-model-serving
  destination:
    namespace: private-ai-demo
  syncPolicy:
    automated:
      selfHeal: true
    retry:
      limit: 3
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - RespectIgnoreDifferences=true
```

### Status: ✅ WORKING

- Auto-sync: **Enabled**
- Self-heal: **Enabled**
- Retry policy: **Configured**
- Resources: **Deploying correctly**

## Cross-Namespace Resources

While the app is scoped to `private-ai-demo`, it successfully deploys resources to other namespaces:

| Namespace | Resources | Status |
|-----------|-----------|--------|
| `private-ai-demo` | Pipelines, InferenceServices, Workbench | ✅ Working |
| `redhat-ods-applications` | HardwareProfile, AcceleratorProfile | ✅ Working |
| `rhoai-model-registries` | ModelRegistry CR, Network policies | ✅ Working |
| `model-registry` | MySQL, services, config | ✅ Working |

**How it works:**
- Manifests have explicit `namespace:` fields
- ArgoCD respects these and deploys to correct namespaces
- UI shows them as "managed" resources

## Why Not App-of-Apps Now?

### Technical Reasons

1. **Kustomize Structure Needs Refactoring**
   - Current structure uses components in flat directory
   - App-of-Apps needs separate kustomization.yaml per app
   - Would require significant restructuring

2. **Pipeline Running**
   - Mistral 24B full model pipeline in progress (~2h)
   - Don't want to disrupt active deployment
   - Risk of sync conflicts

3. **Working Configuration**
   - Current app already has auto-sync + self-heal
   - Successfully managing cross-namespace resources
   - No immediate problem to solve

### Operational Reasons

1. **Time Priority**
   - Pipeline completion is critical path
   - App-of-Apps refactoring can wait
   - Focus on validating authentication fix

2. **Risk Management**
   - App-of-Apps migration during active pipeline = risky
   - Better to refactor when cluster is stable
   - Can test App-of-Apps in separate environment first

## When to Refactor to App-of-Apps?

### Good Time

✅ After pipeline completes  
✅ After models are deployed and validated  
✅ During a maintenance window  
✅ When all resources are in sync  

### Prerequisites

1. Restructure GitOps folder:
   ```
   gitops/stage01-model-serving/
   ├── infrastructure/
   │   ├── kustomization.yaml
   │   ├── hardware-profiles/
   │   └── network-policies/
   ├── model-registry/
   │   ├── kustomization.yaml
   │   ├── mysql/
   │   └── registry-cr/
   └── application/
       ├── kustomization.yaml
       ├── pipelines/
       ├── vllm/
       └── workbench/
   ```

2. Test in development cluster first

3. Document migration procedure

4. Have rollback plan ready

## Benefits of App-of-Apps (Future)

When we do migrate:

### Better Organization

- **Infrastructure** app: Hardware profiles, network policies
- **Model Registry** app: Registry CR, MySQL, RBAC
- **Application** app: Pipelines, models, workbench

### Independent Sync Policies

- Infrastructure: No prune (safety)
- Model Registry: No prune (safety)
- Application: Prune enabled (safe to recreate)

### Clearer Ownership

- Each app has clear scope
- Easier to debug issues
- Better visibility in UI

### Proper Namespace Scoping

- Infrastructure app: No destination namespace (resources define own)
- Model Registry app: No destination namespace (resources define own)
- Application app: `destination.namespace: private-ai-demo`

## Current Action Plan

1. **Keep current single app** ✅
2. **Monitor pipeline completion** ⏳
3. **Validate model deployment** 📋
4. **Document App-of-Apps design** ✅ (This file + README.md)
5. **Refactor later** 🔮

## Files Prepared for Future

The App-of-Apps structure is designed and documented:

- `app-of-apps-stage01.yaml` - Parent app (NOT deployed yet)
- `app-stage01-infrastructure.yaml` - Infrastructure child app
- `app-stage01-model-registry.yaml` - Model Registry child app
- `app-stage01-application.yaml` - Application child app
- `README.md` - Full documentation

These files are ready to use when we decide to migrate.

## Conclusion

**Decision: Keep single app, refactor later**

**Rationale:**
- Current setup works well
- Pipeline is running (don't disrupt)
- App-of-Apps requires significant restructuring
- Can migrate safely later

**Next Steps:**
1. Monitor Mistral pipeline (⏳ ~2h remaining)
2. Validate authentication fix works
3. Deploy and test models
4. Consider App-of-Apps migration during next maintenance window

