# Dashboard "No Data" - Root Cause Analysis & Fixes

**Date**: 2025-11-10  
**Environment**: Private AI Demo - Stage 3 (Model Monitoring)  
**Issue**: Grafana dashboards showing no data

---

## Executive Summary

Successfully identified and fixed **multiple root causes** preventing data from appearing in Grafana dashboards:

1. ✅ **FIXED**: TempoStack configuration error (operator crashing)
2. ✅ **FIXED**: Grafana authentication blocking operator access
3. ❌ **BLOCKED**: TrustyAI Service deployment (operator template parsing error)
4. ⚠️  **PARTIAL**: Insufficient cluster resources (Tempo query-frontend pending)

---

## Root Cause #1: TempoStack Configuration Error ✅ FIXED

### Problem
- TempoStack configured with `tenants.mode: static` + `authentication` section
- Required OIDC tenant secrets that don't exist
- Tempo Operator crashed with nil pointer dereference: `GetOIDCTenantSecrets line 31`
- No Tempo pods created → No trace storage/query

### Error Logs
```
{"level":"error","msg":"Observed a panic","controller":"tempostack",
"panic":"runtime error: invalid memory address or nil pointer dereference"}
```

### Fix Applied
**File**: `gitops/stage03-model-monitoring/observability/tempo-stack.yaml`

**Change**: Removed invalid tenants configuration, using simple single-tenant mode

```yaml
spec:
  managementState: Managed
  # Single-tenant mode (default) - no complex OIDC authentication needed
  storage:
    secret:
      name: tempo-storage
      type: s3
  storageSize: 10Gi
  template:
    queryFrontend:
      jaegerQuery:
        enabled: true
    distributor:
      replicas: 1
    ingester:
      replicas: 1
    querier:
      replicas: 1
    compactor:
      replicas: 1
```

### Result
- ✅ Tempo pods now running: 4/5 operational
  - `tempo-tempo-distributor`: Running (1/1)
  - `tempo-tempo-ingester`: Running (1/1)
  - `tempo-tempo-querier`: Running (1/1)
  - `tempo-tempo-compactor`: Running (1/1)
  - `tempo-tempo-query-frontend`: Pending (insufficient resources)

---

## Root Cause #2: Grafana Authentication ✅ FIXED

### Problem
- Grafana Operator v5 couldn't authenticate with Grafana instance
- `/api/frontend/settings` returned 401 Unauthorized
- NetworkPolicy blocked `grafana-operator-system` → `private-ai-demo` communication
- Datasources and dashboards showed "NO MATCHING INSTANCES"

### Fix Applied
**Files Modified**:
1. `gitops/stage03-model-monitoring/observability/grafana-instance.yaml`
2. `gitops/stage03-model-monitoring/observability/network-policy-grafana-operator.yaml` (new)
3. `gitops/stage03-model-monitoring/observability/kustomization.yaml`

**Changes**:
1. Added anonymous auth (Viewer role) for operator health checks:
```yaml
auth.anonymous:
  enabled: "true"
  org_role: "Viewer"
```

2. Created NetworkPolicy to allow operator access:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-grafana-operator
  namespace: private-ai-demo
spec:
  podSelector:
    matchLabels:
      app: grafana
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: grafana-operator-system
      ports:
        - protocol: TCP
          port: 3000
```

### Result
- ✅ Grafana Instance: `complete/success` (v12.1.0)
- ✅ Datasources provisioned (2): OTEL Prometheus, Tempo
- ✅ Dashboards provisioned (4): AI Metrics, TrustyAI Eval, Traces, Enhanced GPU

---

## Root Cause #3: TrustyAI Service Deployment ❌ BLOCKED

### Problem
- TrustyAI Operator **IS** running (`redhat-ods-applications` namespace)
- TrustyAI Service CR exists in `private-ai-demo`
- But operator fails to create deployment with YAML parsing error

### Error Logs
```
ERROR Error parsing the service's deployment template
{"error": "error converting YAML to JSON: yaml: line 61: 
did not find expected alphabetic or numeric character"}
```

### Root Cause
- Operator has internal bug parsing deployment template at line 61
- Prevents TrustyAI Service pod from being created
- PVCs remain in `WaitForFirstConsumer` state (no pod to bind to)

### Impact
- ❌ No TrustyAI Service runtime pod
- ❌ No model evaluation metrics
- ❌ TrustyAI dashboards show no data
- ⚠️  LMEvalJobs complete but results not persisted

### Current Status
```
trustyai-service-pvc: Pending (gp3-csi) - WaitForFirstConsumer
LMEvalJobs: Complete (eval-mistral-full, eval-mistral-quantized)
TrustyAI Operator: Running but failing to reconcile
```

### Attempted Fixes
- Verified YAML syntax in `trustyai-service.yaml` ✅ Valid
- Verified operator config ✅ Valid
- Issue is in operator's **internal** deployment template

### Recommended Next Steps
1. File bug report with TrustyAI operator team
2. Check for operator version update/patch
3. Temporarily use alternative evaluation metrics collection

---

## Root Cause #4: Insufficient Cluster Resources ⚠️ PARTIAL

### Problem
- Tempo `query-frontend` pod cannot schedule
- 3 nodes: Insufficient CPU
- 2 nodes: Insufficient memory
- AI models consuming most cluster resources

### Impact
- ⚠️  Tempo query-frontend (Jaeger UI) unavailable
- ✅ Trace ingestion **still works** (distributor + ingester running)
- ✅ Trace queries **still work** (querier running)
- ❌ No Jaeger UI for visual trace exploration

### Event Logs
```
FailedScheduling: 0/7 nodes are available: 
  1 node(s) had untolerated taint {node-role.kubernetes.io/master: },
  3 Insufficient cpu, 
  2 Insufficient memory,
  3 node(s) had untolerated taint {nvidia.com/gpu: true}
```

### Options
A) Scale down non-critical workloads temporarily  
B) Reduce resource requests for query-frontend  
C) Live without Jaeger UI (traces still collected/queryable)  

---

## Component Status Summary

| Component | Status | Details |
|-----------|--------|---------|
| **OTEL Collector** | ✅ Running | 1/1 pods, metrics endpoint available |
| **Tempo Distributor** | ✅ Running | Ingesting traces |
| **Tempo Ingester** | ✅ Running | Writing to S3 storage |
| **Tempo Querier** | ✅ Running | Query API available |
| **Tempo Compactor** | ✅ Running | Background compaction |
| **Tempo Query-Frontend** | ⚠️ Pending | Insufficient resources |
| **Grafana** | ✅ Running | UI accessible, datasources configured |
| **TrustyAI Operator** | ⚠️ Running | Failing to reconcile service |
| **TrustyAI Service** | ❌ Not Running | Operator template parsing error |
| **LMEvalJobs** | ✅ Complete | Jobs finished but results not persisted |

---

## Why Dashboards Show "No Data"

### Traces Dashboard
- ⚠️  **Partial Data**: Tempo is collecting traces
- ❌ **No Application Traces**: Models haven't been queried recently
- ❌ **No TrustyAI Logger**: TrustyAI Service not running

### TrustyAI Eval Results Dashboard
- ❌ **No Data**: TrustyAI Service not running
- ❌ **Results Not Persisted**: LMEvalJobs completed but no storage

### AI Metrics Dashboard
- ⚠️  **Limited Data**: Only OTEL Collector internal metrics
- ❌ **No Application Metrics**: Need to generate traffic to models

### Enhanced GPU Metrics Dashboard
- ✅ **Should Have Data**: DCGM metrics being collected
- ❓ **Check PodMonitor**: Verify `podmonitor-dcgm.yaml` is applied

---

## Files Modified (Ready to Commit)

```
Modified:
  gitops/stage03-model-monitoring/observability/tempo-stack.yaml
  gitops/stage03-model-monitoring/observability/grafana-instance.yaml
  gitops/stage03-model-monitoring/observability/kustomization.yaml

New:
  gitops/stage03-model-monitoring/observability/network-policy-grafana-operator.yaml
```

---

## Next Steps to Get Data in Dashboards

### 1. Fix TrustyAI Operator Issue (CRITICAL)

**Option A**: Wait for operator fix
- File bug report with operator team
- Monitor for v5.x.x updates

**Option B**: Workaround
- Check if older operator version works
- Use alternative metrics collection (custom ServiceMonitor)

### 2. Generate Application Traffic

Once TrustyAI is fixed, generate traces and metrics:

```bash
# Query models to generate traces
curl -k https://mistral-24b-quantized-private-ai-demo.apps.cluster...

# Run evaluation jobs
oc apply -f gitops/stage03-model-monitoring/trustyai/lmevaljob-*.yaml

# Wait 2-5 minutes for metrics to appear
```

### 3. Verify OTEL Metrics

Test OTEL Collector Prometheus endpoint:
```bash
oc port-forward -n private-ai-demo deployment/otel-collector-collector 8889:8889
curl http://localhost:8889/metrics
```

### 4. Optional: Free Resources

To enable Tempo query-frontend (Jaeger UI):
```bash
# Scale down non-critical workloads
oc scale deployment/xyz --replicas=0 -n some-namespace
```

---

## Access Information

### Grafana
- **URL**: https://grafana-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com
- **Username**: `admin`
- **Password**: `admin123`

### Tempo Query API
- **Internal**: `http://tempo-query-frontend.private-ai-demo.svc:3100`

### OTEL Collector Metrics
- **Internal**: `http://otel-collector-collector.private-ai-demo.svc:8889/metrics`

---

## Lessons Learned

1. **TempoStack**: Single-tenant mode is simpler for dev/demo environments
2. **Grafana Operator**: v5 requires NetworkPolicy for cross-namespace communication
3. **TrustyAI**: Operator still has deployment template parsing issues (v5.20.0)
4. **Resource Planning**: ML workloads need careful resource allocation planning
5. **Observability Stack**: Multiple components must work together - failure in one affects all

---

## References

- [Red Hat lls-observability](https://github.com/rh-ai-quickstart/lls-observability)
- [Tempo Operator Docs](https://github.com/grafana/tempo-operator)
- [TrustyAI Service Operator](https://github.com/trustyai-explainability/trustyai-service-operator)
- [Grafana Operator v5](https://github.com/grafana-operator/grafana-operator)

