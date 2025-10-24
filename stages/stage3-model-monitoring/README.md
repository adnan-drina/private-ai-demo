# Stage 3: Model Monitoring with TrustyAI + OpenTelemetry + Llama Stack

## Overview

Stage 3 establishes comprehensive model monitoring, quality assessment, and observability. This stage integrates TrustyAI for model evaluation, Grafana for visualization, and OpenTelemetry for distributed tracing.

## Components

### Model Quality Assessment
- **TrustyAI Operator** - Model evaluation framework
- **LMEvalJobs** - Automated quality benchmarks
  - `arc_easy` - Reasoning capability
  - `hellaswag` - Commonsense reasoning
  - `gsm8k` - Mathematical reasoning
  - `truthfulqa_mc2` - Truthfulness assessment

### Observability Stack
- **Grafana** - Metrics visualization dashboards
  - AI/ML Performance - Model Comparison
  - Model Quality Assessment - Evaluation Results
- **Prometheus** - Metrics collection and storage
- **ServiceMonitors** - vLLM and Llama Stack metrics
- **PodMonitors** - Container-level metrics
- **OpenTelemetry Collector** - Distributed tracing

### Analysis Tools
- **Evaluation Notebook** - Interactive results analysis

## Prerequisites

- **Stage 1 & 2** deployed and validated
- Models serving and processing queries
- TrustyAI operator enabled in DataScienceCluster

## Deployment

```bash
# Deploy all Stage 3 components
./deploy.sh

# Validate deployment
./validate.sh
```

## Verification

Monitor deployment:

```bash
# Check TrustyAI LMEvalJobs
oc get lmevaljob -n private-ai-demo

# Monitor evaluation progress
oc get pods -n private-ai-demo -l app=lm-eval

# Check Grafana
oc get deployment grafana-deployment -n grafana-system
oc get route grafana-route -n grafana-system

# Access Grafana dashboard
GRAFANA_URL=$(oc get route grafana-route -n grafana-system -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"
```

## Model Evaluation

### TrustyAI LMEvalJobs

Evaluations run automatically for both models:
- **Mistral 24B Quantized** - Evaluate W4A16 quantized model
- **Mistral 24B Full** - Evaluate FP16 full precision model

Each evaluation includes:
- 4 standard benchmark tasks
- 100 samples per task (configurable)
- Results published to Model Registry
- Metrics exposed to Prometheus

### Evaluation Metrics

| Task | Measures | Higher is Better |
|------|----------|------------------|
| arc_easy | Reasoning | Yes |
| hellaswag | Common sense | Yes |
| gsm8k | Math | Yes |
| truthfulqa_mc2 | Truthfulness | Yes |

### Results Location

Evaluation results are stored in multiple locations:
1. **Model Registry** - As model version properties
2. **Prometheus** - As time-series metrics
3. **Grafana** - Visualized in dashboards
4. **Notebook** - For detailed analysis

## Grafana Dashboards

### AI/ML Performance - Model Comparison

Tracks runtime performance metrics:
- **GPU Utilization** - Compute usage per model
- **GPU Memory** - Memory consumption
- **TTFT** (Time To First Token) - P50, P90, P99 latencies
- **Throughput** - Tokens per second
- **Request Rate** - Queries per second

### Model Quality Assessment

Displays evaluation results:
- **Accuracy Scores** - Per benchmark task
- **Model Comparison** - Quantized vs Full precision
- **Delta Analysis** - Quality trade-offs
- **Trend Analysis** - Quality over time

Access dashboards:
```bash
# Get Grafana URL
oc get route grafana-route -n grafana-system -o jsonpath='{.spec.host}'

# Login with OpenShift credentials
# Navigate to: Dashboards → AI/ML Performance
```

## OpenTelemetry Integration

Llama Stack exports traces to OpenTelemetry Collector:
- Request tracing (e2e latency)
- Component timing (embedding, retrieval, inference)
- Error tracking
- Resource utilization

## Quality vs Performance Trade-offs

Compare quantized vs full precision models:

```bash
# Access evaluation notebook
# Navigate to: OpenShift AI → Workbenches → rag-testing
# Open: 02-eval-results.ipynb
```

Expected results:
- **Quantized**: ~1-3% accuracy drop, 5x cost savings
- **Full**: Highest accuracy, 5x higher cost

## Troubleshooting

### LMEvalJobs Not Starting
- Check TrustyAI operator: `oc get csv -n redhat-ods-operator | grep trustyai`
- Verify DSC config: `oc get datasciencecluster -o yaml | grep trustyai`
- Check job status: `oc describe lmevaljob <name> -n private-ai-demo`

### Evaluations Running Too Long
- Reduce sample count in LMEvalJob spec
- Use fewer benchmark tasks
- Check model availability: `oc get inferenceservice -n private-ai-demo`

### Grafana Dashboards Empty
- Verify ServiceMonitors: `oc get servicemonitor -n private-ai-demo`
- Check Prometheus targets: Navigate to Prometheus → Status → Targets
- Verify metrics endpoint: `curl <vllm-pod>:8000/metrics`

### Missing Evaluation Results
- Check LMEvalJob completion: `oc get lmevaljob -n private-ai-demo`
- Verify Prometheus scraping: `oc logs -n grafana-system <prometheus-pod>`
- Check Model Registry: Results should appear as model version properties

## GitOps Structure

```
gitops-new/stage03-model-monitoring/
├── trustyai/          # LMEvalJob CRs for both models
├── observability/     # Grafana, ServiceMonitors, PodMonitors
└── notebooks/         # Evaluation results notebook
```

## Metrics Reference

### vLLM Metrics
- `vllm:num_requests_running` - Active requests
- `vllm:gpu_cache_usage_perc` - KV cache utilization
- `vllm:time_to_first_token_seconds` - TTFT latency
- `vllm:time_per_output_token_seconds` - Generation speed

### TrustyAI Metrics
- `lm_eval_accuracy` - Task accuracy score
- `lm_eval_completion_time` - Evaluation duration
- `lm_eval_samples_evaluated` - Sample count

## Next Steps

Once Stage 3 is validated:
1. Review evaluation results in Grafana
2. Analyze quality/performance trade-offs
3. Proceed to **Stage 4: Model Integration with MCP**

## Documentation

- [TrustyAI Documentation](https://trustyai-explainability.github.io/)
- [Red Hat Monitoring Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.24/html/monitoring_data_science_models/)
- [Grafana Dashboards](https://grafana.com/docs/)
- [OpenTelemetry](https://opentelemetry.io/docs/)
