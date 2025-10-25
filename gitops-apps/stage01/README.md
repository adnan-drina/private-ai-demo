# Stage 01: Model Serving - ArgoCD App-of-Apps

## Architecture Decision

Stage 01 deploys resources to **multiple namespaces** following Red Hat's architecture:

| Namespace | Resources | Purpose |
|-----------|-----------|---------|
| `private-ai-demo` | Pipelines, InferenceServices, Workbench | Main application |
| `redhat-ods-applications` | HardwareProfile, AcceleratorProfile | RHOAI dashboard integration |
| `rhoai-model-registries` | ModelRegistry CR, Network policies | Model Registry instance |
| `model-registry` | MySQL, services, config | Model Registry backend |

**Problem with single ArgoCD app:**
- ArgoCD apps are scoped to one destination namespace
- Using `namespace: private-ai-demo` means cross-namespace resources fail to sync
- Manifests with explicit `namespace:` fields work, but ArgoCD UI shows them as "orphaned"

**Solution: App-of-Apps Pattern**

Split Stage 01 into 3 logical applications with proper namespace scoping:

## Application Structure

```
stage01-model-serving (App-of-Apps)
├── stage01-infrastructure (Wave 1)
│   ├── Namespace: <defined in manifests>
│   ├── HardwareProfiles → redhat-ods-applications
│   ├── AcceleratorProfiles → redhat-ods-applications
│   └── Network policies → rhoai-model-registries
│
├── stage01-model-registry (Wave 2)
│   ├── Namespace: <defined in manifests>
│   ├── ModelRegistry CR → rhoai-model-registries
│   ├── MySQL deployment → model-registry
│   └── RBAC → model-registry, rhoai-model-registries
│
└── stage01-application (Wave 3)
    ├── Namespace: private-ai-demo
    ├── ImageStreams
    ├── Pipelines & PipelineRuns
    ├── InferenceServices
    └── Workbench (Notebooks)
```

## Sync Waves

1. **Wave 1: Infrastructure** - Hardware profiles, network policies
2. **Wave 2: Model Registry** - Registry CR, MySQL, RBAC
3. **Wave 3: Application** - Pipelines, models, workbench

## Deployment

### Option 1: Deploy App-of-Apps (Recommended)

```bash
# Deploy the parent app (manages all 3 child apps)
oc apply -f gitops-apps/stage01/app-of-apps-stage01.yaml

# ArgoCD will automatically create and sync:
# - stage01-infrastructure
# - stage01-model-registry
# - stage01-application
```

### Option 2: Deploy Individual Apps

```bash
# Deploy in order (respects sync waves)
oc apply -f gitops-apps/stage01/app-stage01-infrastructure.yaml
oc apply -f gitops-apps/stage01/app-stage01-model-registry.yaml
oc apply -f gitops-apps/stage01/app-stage01-application.yaml
```

## Sync Policies

### Infrastructure App
- **Auto-sync:** Yes
- **Self-heal:** Yes
- **Prune:** No (safety - don't auto-delete hardware profiles)

### Model Registry App
- **Auto-sync:** Yes
- **Self-heal:** Yes
- **Prune:** No (safety - don't auto-delete registry)

### Application App
- **Auto-sync:** Yes
- **Self-heal:** Yes
- **Prune:** Yes (safe to prune application resources)

## Migration from Old Single App

```bash
# 1. Delete old single app (DON'T prune resources!)
oc delete application stage01-model-serving -n openshift-gitops --cascade=orphan

# 2. Deploy new App-of-Apps
oc apply -f gitops-apps/stage01/app-of-apps-stage01.yaml

# 3. ArgoCD will discover existing resources and adopt them
# 4. Monitor sync status:
argocd app list | grep stage01
```

## Benefits

✅ **Proper namespace scoping** - Each app targets correct namespaces  
✅ **Clear separation of concerns** - Infrastructure, Registry, Application  
✅ **Independent sync policies** - Different prune/heal settings per concern  
✅ **Better ArgoCD UI** - No more "orphaned" resources  
✅ **Sync wave ordering** - Infrastructure → Registry → Application  
✅ **Easier debugging** - Clear which app manages which resources  

## Monitoring

```bash
# Check all Stage 01 apps
argocd app list | grep stage01

# Check specific app
argocd app get stage01-infrastructure
argocd app get stage01-model-registry
argocd app get stage01-application

# Sync specific app
argocd app sync stage01-application

# View in UI
https://<argocd-url>/applications/stage01-model-serving
```

## Troubleshooting

### Resources not syncing

1. Check which app should manage the resource
2. Verify namespace in manifest matches app destination
3. Check sync waves (infrastructure before application)

### "Orphaned" resources

- This is expected for cross-namespace resources in the old single-app setup
- Fix: Migrate to App-of-Apps pattern

### Sync conflicts

- Infrastructure and Application apps should not have overlapping resources
- Check `kustomization.yaml` components don't duplicate resources

## References

- [Red Hat GitOps Best Practices](https://developers.redhat.com/articles/2022/07/20/git-workflows-best-practices-gitops-deployments)
- [ArgoCD App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [OpenShift AI Architecture](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.24/)

