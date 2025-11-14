# Stage 3: Model Monitoring with TrustyAI, Tempo, OpenTelemetry, and Grafana

## Overview

Stage 3 equips the Private AI Demo with full observability, safety, and quality insights. It combines:

- **TrustyAI** LMEvalJobs to benchmark the deployed models.
- **TrustyAI Service** runtime to persist evaluation history and expose metrics.
- **OpenTelemetry Collector** for OTLP ingest (metrics + traces).
- **TempoStack** for distributed trace storage and search.
- **Grafana** for dashboards that correlate metrics, benchmark results, and recent traces.

```
Llama Stack / vLLM pods
        │ (OTLP gRPC/HTTP)
        ▼
OpenTelemetry Collector ──► Prometheus endpoint (metrics)
        │
        └──────────────► Tempo distributor (traces)
                                │
                                ▼
                           Tempo Stack
                                │
                                ▼
                      Grafana dashboards (metrics + traces)
```

## Components

### Model Quality Assessment
- TrustyAI Operator (enabled in Stage 0 DataScienceCluster)
- TrustyAI Service (`trustyai-service` CR + PVC)
- TrustyAI operator config map enabling LM-Eval online/code execution (GitOps managed)
- LMEvalJobs: `arc_easy`, `hellaswag`, optional `gsm8k`, `truthfulqa_mc2`
- LMEval metrics exporter CronJob → Pushgateway
- Evaluation notebook for deeper analysis
- **Service Mesh routing** – LM-Eval pods keep Istio sidecars but call the canonical Knative services directly (`https://mistral-24b(-quantized).private-ai-demo.svc.cluster.local`). No revision suffix management is needed; KServe swaps revisions transparently.

### Observability Stack
- **Operators (phase 1)** – see `gitops/stage03-model-monitoring/operators/`
  - `grafana-operator.yaml`
  - `otel-operator.yaml`
  - `tempo-operator.yaml`
- **Infrastructure (phase 2)**
  - `otel-collector.yaml` – metrics pipeline → Prometheus endpoint (`:8889`), traces pipeline → Tempo (`tempo-distributor:4317`)
  - `tempo-stack.yaml` – single-tenant Tempo deployment (local storage backend)
  - `grafana-instance.yaml` – routed Grafana instance (namespace `private-ai-demo`)
- Datasources: `grafana-datasource.yaml` (OTEL metrics), `grafana-datasource-tempo.yaml`
- Dashboards:
  - `grafana-dashboard-enhanced.yaml` – **Llama Stack Operations** (guardrail error rate/throughput, GPU, vLLM latencies)
  - `grafana-dashboard-traces.yaml` – **Llama Stack Traces** (Tempo TraceQL explorer + span KPIs)
  - `grafana-dashboard-ai-metrics.yaml`, `grafana-dashboard-eval-results.yaml`, `grafana-dashboard-guidellm.yaml`
  - Monitoring CRDs: `podmonitor.yaml`, `podmonitor-dcgm.yaml`, `pushgateway.yaml`
- Metrics jobs: `trustyai/metrics/` CronJob pushing `lm_eval_*` to Pushgateway
- Guardrail telemetry: `/metrics` scrape is handled by OTEL Collector; panels read `client_request_*` metrics exposed by the Guardrails Orchestrator (PII regex + toxicity shields) via OTLP.
- Dashboard integration: `dashboard/odh-dashboard-config-patch.yaml` enables the **Model evaluations** navigation item by setting `disableLMEval: false` in the `OdhDashboardConfig` CR ([Red Hat guidance](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_cloud_service/1/html/managing_resources/customizing-the-dashboard#ref-dashboard-configuration-options_dashboard)).
- 🔎 **Guardrails note**: Safety enforcement (GuardrailsOrchestrator, detectors, and their secrets) lives in Stage 2 alongside ingestion/serving so responses can be filtered before hitting observability. Stage 3 only consumes the guardrails telemetry exposed via OTEL.

### GuideLLM Benchmark Automation
- `guidellm/` overlay deploys:
  - Daily & weekly CronJobs that pull scenarios and invoke the GuideLLM CLI.
  - On-demand Jobs for the quantised/full Mistral models.
  - A Workbench Deployment + Route for interactive debugging.
  - S3 credentials + buckets (`guidellm-results/daily`, `guidellm-results/weekly`) provisioned automatically by `deploy.sh`.
- Tekton pipeline definitions (`trustyai/tekton/`) are still included for reference when integrating into larger CI flows.

## Prerequisites

- Stage 1 & 2 must be operational (models serving traffic)
- Stage 0 bootstrap already enabled **User Workload Monitoring**
- Cluster-admin permissions to install operators
- MinIO credentials available in `.env` (used to provision Tempo object storage bucket + secret)

## Deployment & Validation

```bash
# Deploy Stage 3 resources via GitOps
./deploy.sh

# Inspect pod health
oc get pods -n private-ai-demo

# Grab Grafana URL
oc get route grafana -n private-ai-demo -o jsonpath='{.spec.host}'
```

`deploy.sh` now:
1. Ensures MinIO buckets exist for Tempo traces and GuideLLM results, writing the `tempo-storage` secret automatically.
2. Applies the operator subscriptions, waits for their CRDs, and then rolls out TrustyAI, observability (OTEL + Tempo + Grafana), GuideLLM, dashboard patches, and notebooks in that order.
3. Restarts the TrustyAI operator so the latest LM-Eval config takes effect.

Validation checklist (rerun as needed):
1. `oc get pods -n private-ai-demo | grep otel-collector` – collector should be `READY 1/1`.
2. `oc exec deployment/otel-collector-collector -n private-ai-demo -- curl -s http://localhost:8889/metrics | head` – Prometheus scrape works.
3. `oc get pods -n private-ai-demo | grep tempo` – distributor/query pods are running.
4. `oc get cronjob -n private-ai-demo | grep guidellm` – daily & weekly schedules exist.
5. `oc get lmevaljob -n private-ai-demo` – TrustyAI jobs installed.
6. `oc get grafanadashboard -n private-ai-demo llama-stack-dashboard-enhanced` – dashboards synced.

```bash
oc get lmevaljob -n private-ai-demo
oc get deployment otel-collector-collector -n private-ai-demo
oc get pods -n private-ai-demo -l app.kubernetes.io/name=tempo
oc get route grafana -n private-ai-demo -o jsonpath='{.spec.host}'
```

## Grafana Dashboards

- **Llama Stack Operations** (`grafana-dashboard-enhanced.yaml`) – request rate, tokens/sec, guardrail error rate/throughput, vLLM latency, GPU utilisation.
- **Llama Stack Traces** (`grafana-dashboard-traces.yaml`) – Tempo TraceQL explorer, service map, span latency/error panels.
- **AI/ML Performance** – GPU utilisation, TTFT, throughput.
- **Model Quality Assessment** – TrustyAI benchmark scores.
- **GuideLLM Results** – success/failure of daily/weekly benchmarks.

Access Grafana:

```bash
GRAFANA_URL=$(oc get route grafana -n private-ai-demo -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"
```

> ℹ️ Guardrail panels (error rate / throughput / latency) populate after at least one shielded request
> flows through the Playground (PII regex or toxicity shield).

## OpenTelemetry + Tempo

- OTLP gRPC (`:4317`) and HTTP (`:4318`) receivers enabled.
- Metrics pipeline exports to the collector’s Prometheus endpoint.
- Trace pipeline exports to `tempo-distributor.private-ai-demo.svc:4317` (insecure gRPC).
- Grafana Tempo datasource points at `tempo-query-frontend.private-ai-demo.svc:3100`.

## TrustyAI LMEval and Service Runtime

- Evaluates quantised and full precision Mistral models.
- Persists evaluation artifacts to the TrustyAI Service PVC (10Gi default).
- Benchmarks: four tasks × configurable sample count (default 100).
- Outputs:
  1. Model Registry annotations
  2. Prometheus metrics (`lm_eval_*` exporter, `trustyai_service_*`)
  3. Grafana dashboards
  4. Evaluation notebook

## Troubleshooting

| Issue | Checks |
|-------|--------|
| OTEL collector unhealthy | `oc logs deployment/otel-collector-collector -n private-ai-demo` |
| Tempo pods not ready | `oc get pods -n private-ai-demo | grep tempo` |
| Grafana panels blank | `oc get grafanadatasource -n private-ai-demo`; `oc exec -n private-ai-demo deployment/otel-collector-collector -- curl -s http://localhost:8889/metrics | head` |
| Traces missing | `oc logs -n private-ai-demo deployment/tempo-query-frontend` |
| LMEval jobs stalled | `oc get csv -n redhat-ods-operator | grep trustyai`; `oc describe lmevaljob <name> -n private-ai-demo` |

## GitOps Layout

```
stage3-model-monitoring/
├── operators/
│   ├── grafana-operator.yaml
│   ├── otel-operator.yaml
│   └── tempo-operator.yaml
├── observability/
│   ├── grafana-*.yaml
│   ├── otel-collector.yaml
│   └── tempo-stack.yaml
├── trustyai/
├── dashboard/
│   └── odh-dashboard-config-patch.yaml
└── notebooks/
```

## Metrics & Traces Reference

- `vllm_time_to_first_token_seconds`, `vllm_tokens_per_second`
- `lm_eval_accuracy`, `lm_eval_completion_time`
- Tempo Trace Explorer → correlate retrieval vs inference latency

## Next Steps

1. Monitor dashboards for performance and quality drift.
2. Use Tempo traces to diagnose RAG latency and errors.
3. Proceed to Stage 4 (MCP integration) once observability is validated.

## Documentation

- [TrustyAI](https://trustyai-explainability.github.io/)
- [Tempo Operator](https://grafana.com/docs/tempo/latest/operations/operator/)
- [OpenTelemetry](https://opentelemetry.io/docs/)
- [Grafana](https://grafana.com/docs/)
