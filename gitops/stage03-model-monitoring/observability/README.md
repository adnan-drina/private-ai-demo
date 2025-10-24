# Observability Component

Red Hat pattern observability stack for Private AI Demo.

## Architecture

```
Applications → OTLP → OTEL Collector → Prometheus → Grafana
```

## Prerequisites

1. **OpenShift User Workload Monitoring** must be enabled
2. **Operators must be installed first** (via `deploy.sh`)

## Deployment

### Automated (Recommended)

The observability stack is deployed automatically by `stage2-private-data-rag/deploy.sh`:

```bash
cd stage2-private-data-rag
./deploy.sh
# Answer "Y" when prompted: "Enable Observability (Prometheus + Grafana)?"
```

### Manual Deployment

#### Step 1: Enable User Workload Monitoring

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF

# Wait for monitoring stack
sleep 60
```

#### Step 2: Install Operators

```bash
# OpenTelemetry Operator
oc apply -f otel-operator.yaml

# Grafana Operator
oc apply -f grafana-operator.yaml

# Wait for operators (2-3 minutes)
oc wait --for=condition=Ready pod -l control-plane=controller-manager \
  -n openshift-opentelemetry-operator --timeout=300s

oc wait --for=condition=Ready pod -l control-plane=controller-manager \
  -n grafana-operator-system --timeout=300s
```

#### Step 3: Deploy Observability Infrastructure

```bash
# Create namespace
oc create namespace grafana-system

# Deploy via Kustomize
oc apply -k .

# Wait for deployments
oc wait --for=condition=available deployment/otel-collector-collector \
  -n private-ai-demo --timeout=120s

oc wait --for=condition=available deployment/grafana-deployment \
  -n grafana-system --timeout=120s
```

## Components

### Operators (Phase 1)

- **OpenTelemetry Operator** (`otel-operator.yaml`)
  - Namespace: `openshift-opentelemetry-operator`
  - Source: Red Hat Operators
  - Manages: OpenTelemetry Collector lifecycle

- **Grafana Operator** (`grafana-operator.yaml`)
  - Namespace: `grafana-operator-system`
  - Source: Community Operators
  - Manages: Grafana instances, datasources, dashboards

### Infrastructure (Phase 2)

- **OTEL Collector** (`otel-collector.yaml`)
  - Namespace: `private-ai-demo`
  - Receivers: OTLP gRPC (:4317), OTLP HTTP (:4318)
  - Exporters: Prometheus (:8889/metrics)

- **Grafana Instance** (`grafana-instance.yaml`)
  - Namespace: `grafana-system`
  - Includes: Grafana CRD + Route
  - Access: External HTTPS route

- **Grafana Datasource** (`grafana-datasource.yaml`)
  - Points to: OTEL Collector Prometheus endpoint
  - Type: Prometheus
  - URL: `http://otel-collector-collector.private-ai-demo.svc.cluster.local:8889`

- **Grafana Dashboard** (`grafana-dashboard.yaml`)
  - Dashboard: Llama Stack Overview
  - Panels: Pod Status, CPU, Memory, Network I/O

- **PodMonitor** (`podmonitor.yaml`)
  - Target: Llama Stack pods
  - Interval: 30 seconds

## Access

### Grafana URL

```bash
oc get route grafana -n grafana-system -o jsonpath='{.spec.host}'
```

### Credentials

- **Username**: `admin`
- **Password**: `admin123`

### Dashboard Location

1. Log in to Grafana
2. Navigate to: **Dashboards** → **Browse**
3. Open: **Llama Stack Overview**

## Verification

### Check OTEL Collector

```bash
# Pod status
oc get pods -n private-ai-demo -l app.kubernetes.io/component=opentelemetry-collector

# Logs
oc logs -n private-ai-demo deployment/otel-collector-collector

# Test endpoint
oc exec -n private-ai-demo deployment/otel-collector-collector -c otc-container -- \
  curl -s http://localhost:8889/metrics | head -20
```

### Check Grafana

```bash
# Pod status
oc get pods -n grafana-system -l app=grafana

# Datasource status
oc get grafanadatasource -n grafana-system

# Dashboard status
oc get grafanadashboard -n grafana-system
```

## Troubleshooting

### OTEL Collector Not Starting

Check logs:
```bash
oc logs -n private-ai-demo -l app.kubernetes.io/component=opentelemetry-collector
```

Common issues:
- Invalid YAML syntax
- Deprecated exporters (use `debug`, not `logging`)

### Grafana Dashboard "No data"

1. Check datasource: `oc get grafanadatasource -n grafana-system`
2. Check OTEL Collector: `oc get pods -n private-ai-demo`
3. Wait 1-2 minutes for first scrape

### Route Not Working

Verify route port matches service:
```bash
oc get route grafana -n grafana-system -o yaml
oc get svc grafana-service -n grafana-system -o yaml
```

Route `targetPort` must match service port **name** (not number).

## Documentation

- **Comprehensive Guide**: `/docs/OBSERVABILITY-RED-HAT-IMPLEMENTATION.md`
- **Quick Start**: `/docs/GRAFANA-QUICK-START.md`
- **Setup Details**: `/docs/OBSERVABILITY-SETUP.md`

## Reference

- **Red Hat Pattern**: https://github.com/rh-ai-quickstart/lls-observability
- **OpenTelemetry Operator**: https://github.com/open-telemetry/opentelemetry-operator
- **Grafana Operator**: https://github.com/grafana-operator/grafana-operator

