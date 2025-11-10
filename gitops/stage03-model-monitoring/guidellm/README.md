# GuideLLM Integration

This directory contains Kubernetes manifests for integrating **GuideLLM** benchmarking into the Private AI Demo project.

## Overview

GuideLLM is a tool for evaluating and enhancing LLM deployments for real-world inference needs. This integration provides:

- **Automated Benchmarking**: Daily and weekly scheduled benchmarks
- **Manual Benchmarks**: On-demand benchmark jobs for testing
- **Web UI**: HTML reports served via nginx with interactive charts
- **Metrics Export**: Prometheus metrics for Grafana dashboards
- **Persistent Storage**: Results stored in MinIO S3 and PVC

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│              GuideLLM Integration Architecture            │
└──────────────────────────────────────────────────────────┘

User / CronJob
     │
     ▼
┌─────────────────────────────────────────┐
│  GuideLLM Job (Kubernetes)               │
│  Image: ghcr.io/vllm-project/guidellm    │
│  - Runs benchmark against vLLM models    │
│  - Generates HTML report (hosted UI)     │
│  - Outputs JSON metrics                  │
└────────────────┬────────────────────────┘
                 │
     ┌───────────┼──────────────┐
     │           │              │
     ▼           ▼              ▼
┌─────────┐  ┌──────────┐  ┌──────────────┐
│  PVC    │  │  MinIO   │  │ Pushgateway  │
│ (Local) │  │  (S3)    │  │ (Metrics)    │
└────┬────┘  └──────────┘  └──────┬───────┘
     │                             │
     ▼                             ▼
┌─────────────────┐       ┌──────────────┐
│  nginx Server   │       │  Grafana     │
│  - Serves HTML  │       │  - Dashboard │
│  - Index Page   │       │  - Metrics   │
└─────────────────┘       └──────────────┘
```

## Components

### 1. Storage
- **`pvc-guidellm-results.yaml`**: Persistent volume for storing benchmark reports (20Gi)

### 2. Configuration
- **`configmap-guidellm-config.yaml`**: Benchmark configuration presets (quick-test, standard, comprehensive)
- **`configmap-nginx-config.yaml`**: nginx server configuration
- **`configmap-index-html.yaml`**: Index page for listing benchmark reports
- **`configmap-metrics-exporter.yaml`**: Python script for exporting metrics to Prometheus
- **`secret-s3-credentials.yaml`**: MinIO S3 credentials

### 3. Jobs
- **`job-guidellm-mistral-quantized.yaml`**: Manual benchmark job for quantized model
- **`job-guidellm-mistral-full.yaml`**: Manual benchmark job for full precision model

### 4. CronJobs
- **`cronjob-guidellm-daily.yaml`**: Daily automated benchmarks (2 AM)
- **`cronjob-guidellm-weekly.yaml`**: Weekly comprehensive benchmarks (Sundays midnight)

### 5. Web Server
- **`deployment-nginx-reports.yaml`**: nginx deployment for serving HTML reports
- **`service-guidellm-reports.yaml`**: Service exposing nginx
- **`route-guidellm-reports.yaml`**: OpenShift route for external access

## Usage

### Deploy GuideLLM Resources

```bash
# Apply all GuideLLM manifests
oc apply -k gitops/stage03-model-monitoring/guidellm

# Verify deployment
oc get pods -n private-ai-demo -l app=guidellm-reports
oc get cronjobs -n private-ai-demo -l app=guidellm
```

### Run Manual Benchmark

```bash
# Run benchmark for quantized model
oc create job guidellm-test-$(date +%s) \
  --from=job/guidellm-benchmark-mistral-quantized \
  -n private-ai-demo

# Watch job progress
oc logs -f job/guidellm-test-XXXXX -n private-ai-demo

# Check results
oc get pvc guidellm-results -n private-ai-demo
```

### Access Reports

```bash
# Get reports URL
REPORTS_URL=$(oc get route guidellm-reports -n private-ai-demo -o jsonpath='{.spec.host}')
echo "GuideLLM Reports: https://${REPORTS_URL}"

# Open in browser
open "https://${REPORTS_URL}"
```

### View Metrics in Grafana

Metrics are automatically pushed to Prometheus Pushgateway and can be queried in Grafana:

```promql
# Average P95 latency by model
guidellm_request_latency_p95_seconds{model="mistral-24b-quantized"}

# Throughput comparison
guidellm_throughput_requests_per_second

# Success rate
guidellm_request_success_rate
```

## Configuration

### Benchmark Parameters

Edit `configmap-guidellm-config.yaml` to customize benchmark configurations:

- **`quick-test`**: 5-minute quick test (128/64 tokens, 50 samples)
- **`standard`**: 15-minute standard benchmark (256/128 tokens, 100 samples)
- **`comprehensive`**: 1-hour comprehensive test (512/256 tokens, 500 samples)

### Schedule Changes

Edit CronJob schedules in:
- **Daily**: `cronjob-guidellm-daily.yaml` (default: 2 AM daily)
- **Weekly**: `cronjob-guidellm-weekly.yaml` (default: Sundays midnight)

### Resource Limits

Adjust CPU/memory limits in Job and Deployment manifests:

```yaml
resources:
  requests:
    cpu: "1"
    memory: "2Gi"
  limits:
    cpu: "2"
    memory: "4Gi"
```

## Troubleshooting

### Job Fails to Start

```bash
# Check job status
oc describe job guidellm-test-XXXXX -n private-ai-demo

# Check pod logs
oc logs -f -l app=guidellm -n private-ai-demo
```

### No Reports Appearing

```bash
# Check PVC contents
oc exec -it deployment/guidellm-reports -n private-ai-demo -- ls -la /usr/share/nginx/html

# Check MinIO bucket
mc ls minio/guidellm-results/
```

### Metrics Not in Grafana

```bash
# Check Pushgateway
oc port-forward svc/prometheus-pushgateway 9091:9091 -n private-ai-demo
curl http://localhost:9091/metrics | grep guidellm
```

## References

- **GuideLLM GitHub**: https://github.com/vllm-project/guidellm
- **Container Image**: `ghcr.io/vllm-project/guidellm:latest`
- **Hosted UI**: `https://blog.vllm.ai/guidellm/ui/latest`
- **Red Hat Guide**: https://developers.redhat.com/articles/2025/06/20/guidellm-evaluate-llm-deployments-real-world-inference

## Support

For issues or questions:
1. Check GuideLLM documentation
2. Review job logs and pod events
3. Verify vLLM models are READY
4. Check network connectivity to model services

