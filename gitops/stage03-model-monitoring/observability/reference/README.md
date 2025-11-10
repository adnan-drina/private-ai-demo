# Reference Dashboards & Templates

**Purpose:** Reference implementations and upstream templates for observability components

---

## Files in This Directory

### `dcgm-exporter-dashboard.json`

**Type:** Grafana Dashboard JSON (standalone)  
**Source:** [Grafana.com Dashboard #12239](https://grafana.com/grafana/dashboards/12239)  
**Version:** v1 (Grafana 6.7.3 format)  
**Upstream:** [NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)

**Description:**  
Standard NVIDIA DCGM Exporter dashboard template for monitoring GPU metrics in Kubernetes clusters.

**Metrics Covered:**
- GPU Temperature (`DCGM_FI_DEV_GPU_TEMP`)
- GPU Power Usage (`DCGM_FI_DEV_POWER_USAGE`)
- GPU SM Clocks (`DCGM_FI_DEV_SM_CLOCK`)
- GPU Utilization (`DCGM_FI_DEV_GPU_UTIL`)
- GPU Framebuffer Memory Used (`DCGM_FI_DEV_FB_USED`)
- Tensor Core Utilization (`DCGM_FI_PROF_PIPE_TENSOR_ACTIVE`)

---

## Why Keep Reference Files?

### 1. Comparison with Current Implementation

Our project already has GPU monitoring dashboards deployed:
- `grafana-dashboard-ai-metrics.yaml` - Model comparison dashboard
- `grafana-dashboard-enhanced.yaml` - Llama Stack overview with GPU panels

This reference dashboard shows the **upstream standard layout** and metrics coverage, which helps us:
- Identify gaps in our current dashboards
- Compare metric expressions
- Validate we're using best practices

### 2. Additional Metrics

This reference dashboard includes metrics **NOT currently in our deployed dashboards**:
- **GPU Clocks** - Useful for understanding GPU performance states
- **Power Usage** - Critical for cost optimization and capacity planning
- **Temperature** - Important for thermal management and alerting
- **Tensor Core Utilization** - Specific to Tensor Core usage (AI workloads)

These can be added to our dashboards if needed.

### 3. Future Enhancements

When adding new GPU monitoring features, this serves as:
- A tested, community-maintained template
- Reference for metric naming and query patterns
- Starting point for new dashboard panels

---

## Usage

### Option 1: Manual Import (Quick Test)

To use this dashboard in Grafana directly:

```bash
# 1. Access Grafana UI
GRAFANA_URL=$(oc get route grafana -n private-ai-demo -o jsonpath='{.spec.host}')
echo "Grafana: https://${GRAFANA_URL}"

# 2. Log in (admin/admin123)
# 3. Navigate to: Dashboards → Import
# 4. Upload file: dcgm-exporter-dashboard.json
# 5. Select datasource: Prometheus (OTEL Collector)
# 6. Import
```

### Option 2: Convert to Kubernetes CR (Production)

To deploy via GitOps, convert to `GrafanaDashboard` CR:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: nvidia-dcgm-exporter
  namespace: private-ai-demo
spec:
  instanceSelector:
    matchLabels:
      dashboards: "grafana"
  json: |
    # Paste dcgm-exporter-dashboard.json content here
```

Then add to `kustomization.yaml`:
```yaml
resources:
  - grafana-dashboard-dcgm.yaml
```

### Option 3: Merge Selected Panels

Add specific panels to existing dashboards:

```yaml
# Example: Add GPU Temperature to grafana-dashboard-ai-metrics.yaml
{
  "title": "GPU Temperature",
  "type": "timeseries",
  "targets": [{
    "expr": "DCGM_FI_DEV_GPU_TEMP{namespace=\"private-ai-demo\"}",
    "legendFormat": "{{pod}} GPU {{gpu}}"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "celsius"
    }
  }
}
```

---

## Current DCGM Monitoring Setup

**PodMonitor:** `podmonitor-dcgm.yaml`
```yaml
selector:
  matchLabels:
    app: nvidia-dcgm-exporter
namespaceSelector:
  matchNames:
    - nvidia-gpu-operator
```

**Metrics Endpoint:** `nvidia-dcgm-exporter` pods in `nvidia-gpu-operator` namespace  
**Scrape Interval:** 30 seconds  
**Prometheus:** Metrics available via OTEL Collector endpoint

---

## Metrics Naming

DCGM metrics follow the pattern: `DCGM_FI_<CATEGORY>_<METRIC_NAME>`

| Metric | Description | Unit |
|--------|-------------|------|
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature | Celsius |
| `DCGM_FI_DEV_POWER_USAGE` | GPU power consumption | Watts |
| `DCGM_FI_DEV_SM_CLOCK` | SM clock frequency | MHz |
| `DCGM_FI_DEV_GPU_UTIL` | GPU utilization | Percent (0-100) |
| `DCGM_FI_DEV_FB_USED` | Framebuffer memory used | MB |
| `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | Tensor core activity | Percent (0-1) |

**Labels available:**
- `gpu` - GPU index (0, 1, 2, 3, ...)
- `pod` / `exported_pod` - Pod name
- `instance` - Node name
- `namespace` - Kubernetes namespace

---

## Related Documentation

- **Observability README:** [../README.md](../README.md)
- **Current Dashboards:**
  - [grafana-dashboard-ai-metrics.yaml](../grafana-dashboard-ai-metrics.yaml)
  - [grafana-dashboard-enhanced.yaml](../grafana-dashboard-enhanced.yaml)
- **DCGM PodMonitor:** [../podmonitor-dcgm.yaml](../podmonitor-dcgm.yaml)

---

## External References

- [NVIDIA DCGM Exporter GitHub](https://github.com/NVIDIA/dcgm-exporter)
- [DCGM Exporter Metrics](https://docs.nvidia.com/datacenter/dcgm/latest/dcgm-api/dcgm-api-field-ids.html)
- [Grafana Dashboard #12239](https://grafana.com/grafana/dashboards/12239)
- [OpenShift GPU Operator Docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html)

---

**Last Updated:** 2025-10-28  
**Status:** Reference only, not actively deployed  
**Maintenance:** Update when new DCGM Exporter versions release

