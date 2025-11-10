# Observability Component

Red Hat pattern observability stack for Private AI Demo.

## Architecture

```
Applications → OTLP → OTEL Collector → Prometheus (metrics)
                                 └→ Tempo (traces)
                             Grafana (dashboards + Tempo Explorer)
```

## Prerequisites

1. **OpenShift User Workload Monitoring** must be enabled (handled in Stage 0)
2. **Operators must be installed first** (Grafana, OpenTelemetry, Tempo)

## Deployment

### Automated (Recommended)

The observability stack is deployed automatically by Stage 3 GitOps (`deploy.sh`). Operators and instances are created in order (operators → OTEL/Tempo/Grafana → dashboards/monitors).

### Manual Deployment

#### Step 1: Install Operators

```bash
oc apply -k ../operators
```

Wait for operator pods (Grafana, Tempo, OpenTelemetry) to become ready.

#### Step 2: Deploy Observability Infrastructure

```bash
oc apply -k .

# Verify collector, tempo, grafana deployments
oc get deployment otel-collector-collector -n private-ai-demo
oc get pods -n private-ai-demo -l app.kubernetes.io/name=tempo
oc get route grafana -n private-ai-demo
```

Tempo depends on an object-storage secret named `tempo-storage` in the same namespace. The deploy script generates the secret (and ensures the S3 bucket exists) from the MinIO credentials in `.env`; if applying manually, create both the bucket and secret yourself.
```

## Components

### Operators (Phase 1)

Operator namespaces and subscriptions live under `../operators/` and are applied first by `deploy.sh`:

- **OpenTelemetry Operator** (`operators/otel-operator.yaml`)
- **Tempo Operator** (`operators/tempo-operator.yaml`)
- **Grafana Operator** (`operators/grafana-operator.yaml`)

### Infrastructure (Phase 2)

- **Tempo Stack** (`tempo-stack.yaml`)
  - Provides Tempo distributor/query-front-end/ingester components
  - Static single-tenant configuration backed by MinIO/S3 object storage
- **OTEL Collector** (`otel-collector.yaml`)
  - Receivers: OTLP gRPC/HTTP
  - Pipelines: metrics → Prometheus exporter, traces → Tempo
- **Grafana Instance** (`grafana-instance.yaml`)
  - Namespace: `private-ai-demo`
  - Route exposed with OpenShift TLS
- **Grafana Datasources**
  - `grafana-datasource.yaml` – OTEL Prometheus endpoint (`http://otel-collector-collector:8889`)
  - `grafana-datasource-tempo.yaml` – Tempo query front-end (`http://tempo-query-frontend:3100`)
- **Dashboards**
  - `grafana-dashboard-ai-metrics.yaml`
  - `grafana-dashboard-eval-results.yaml`
  - `grafana-dashboard-traces.yaml`
- **TrustyAI Metrics**
  - `trustyai/service/trustyai-servicemonitor.yaml` – scrapes TrustyAI Service runtime (`/q/metrics`)
- **Monitoring CRDs**
  - `podmonitor.yaml`, `podmonitor-dcgm.yaml`
  - `pushgateway.yaml`

## Access

```bash
GRAFANA_URL=$(oc get route grafana -n private-ai-demo -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"
```

## Verification

```bash
# OTEL Collector metrics endpoint
oc exec -n private-ai-demo deployment/otel-collector-collector -- curl -s http://localhost:8889/metrics | head

# Tempo health
oc get pods -n private-ai-demo -l app.kubernetes.io/name=tempo

# Grafana datasources/dashboards
oc get grafanadatasource -n private-ai-demo
oc get grafanadashboard -n private-ai-demo
```

## Reference

- https://github.com/rh-ai-quickstart/lls-observability
- OpenTelemetry Operator documentation
- Tempo Operator documentation

