# GuideLLM Integration - User Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Getting Started](#getting-started)
4. [Running Benchmarks](#running-benchmarks)
5. [Viewing Results](#viewing-results)
6. [Scheduled Benchmarks](#scheduled-benchmarks)
7. [Grafana Integration](#grafana-integration)
8. [Troubleshooting](#troubleshooting)
9. [Advanced Usage](#advanced-usage)
10. [References](#references)

---

## Overview

**GuideLLM** is a tool for evaluating and enhancing LLM deployments for real-world inference needs. This integration provides automated benchmarking, performance metrics, and interactive HTML reports for your vLLM models.

### Key Features

- ✅ **Automated Benchmarking**: Daily and weekly scheduled benchmarks
- ✅ **On-Demand Testing**: Manual benchmark jobs
- ✅ **Interactive Reports**: HTML reports with charts (using official hosted UI)
- ✅ **Metrics Export**: Prometheus metrics for Grafana dashboards
- ✅ **Persistent Storage**: Results stored in MinIO S3 and PVC
- ✅ **Zero Custom Code**: Uses official `ghcr.io/vllm-project/guidellm` container image

### What GuideLLM Measures

| Metric | Description |
|--------|-------------|
| **Latency (P50/P95/P99)** | Request duration percentiles |
| **Time to First Token (TTFT)** | How quickly the model starts generating |
| **Throughput** | Requests per second, Tokens per second |
| **Success Rate** | Percentage of successful requests |
| **Resource Utilization** | GPU/CPU usage during benchmarks |

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│              GuideLLM Integration Architecture            │
└──────────────────────────────────────────────────────────┘

User / CronJob
     │
     ▼
┌─────────────────────────────────────────────┐
│  Kubernetes Job                              │
│  Image: ghcr.io/vllm-project/guidellm:latest │
│  - Runs benchmark against vLLM models        │
│  - Generates HTML report (hosted UI)         │
│  - Outputs JSON metrics                      │
└─────────────────┬───────────────────────────┘
                  │
      ┌───────────┼──────────────┐
      │           │              │
      ▼           ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────────┐
│  PVC     │  │  MinIO   │  │ Pushgateway  │
│ (20Gi)   │  │  (S3)    │  │ (Metrics)    │
└────┬─────┘  └──────────┘  └──────┬───────┘
     │                              │
     ▼                              ▼
┌─────────────────┐        ┌──────────────┐
│  nginx Server   │        │  Grafana     │
│  - Serves HTML  │        │  - Dashboard │
│  - Index Page   │        │  - Metrics   │
└─────────────────┘        └──────────────┘
```

---

## Getting Started

### Prerequisites

- OpenShift/Kubernetes cluster with Private AI Demo deployed
- vLLM models deployed and running (Stage 1)
- MinIO S3 storage configured
- Prometheus and Grafana deployed (Stage 3)

### Deployment

GuideLLM is automatically deployed when you run the Stage 3 deployment script:

```bash
cd /Users/adrina/Sandbox/private-ai-demo/stages/stage3-model-monitoring
./deploy.sh
```

This will:
1. Create MinIO bucket (`guidellm-results`)
2. Deploy GuideLLM Job templates
3. Create CronJobs for daily/weekly benchmarks
4. Deploy nginx server for HTML reports
5. Configure metrics export to Prometheus

### Verify Deployment

```bash
# Check if PVC is created
oc get pvc guidellm-results -n private-ai-demo

# Check nginx deployment
oc get pods -n private-ai-demo -l app=guidellm-reports

# Check CronJobs
oc get cronjobs -n private-ai-demo -l app=guidellm

# Get reports URL
REPORTS_URL=$(oc get route guidellm-reports -n private-ai-demo -o jsonpath='{.spec.host}')
echo "GuideLLM Reports: https://${REPORTS_URL}"
```

---

## Running Benchmarks

### Option 1: Manual Benchmark (Quick Test)

Run a quick 5-minute benchmark to test a specific model:

```bash
# Benchmark quantized model
oc create job guidellm-test-$(date +%s) \
  --from=job/guidellm-benchmark-mistral-quantized \
  -n private-ai-demo

# Watch job progress
oc logs -f -l app=guidellm,model=mistral-24b-quantized -n private-ai-demo
```

### Option 2: Manual Benchmark (Custom Parameters)

Create a custom benchmark job:

```bash
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: guidellm-custom-$(date +%s)
  namespace: private-ai-demo
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: guidellm
        image: ghcr.io/vllm-project/guidellm:latest
        command:
        - guidellm
        - benchmark
        - --target
        - "http://mistral-24b-quantized-predictor.private-ai-demo.svc.cluster.local"
        - --model
        - "mistralai/Mistral-Large-Instruct-2411"
        - --rate-type
        - constant
        - --rate
        - "15"
        - --max-seconds
        - "600"
        - --data
        - "prompt_tokens=512,output_tokens=256,samples=100"
        - --output-path
        - /results/custom-benchmark-$(date +%Y%m%d-%H%M%S).html
        env:
        - name: GUIDELLM__ENV
          value: "production"
        volumeMounts:
        - name: results
          mountPath: /results
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
      volumes:
      - name: results
        persistentVolumeClaim:
          claimName: guidellm-results
EOF
```

### Benchmark Parameters Explained

| Parameter | Description | Example Values |
|-----------|-------------|----------------|
| `--target` | Model endpoint URL | `http://model-predictor.namespace.svc.cluster.local` |
| `--model` | Model name (for tokenization) | `mistralai/Mistral-Large-Instruct-2411` |
| `--rate-type` | Load pattern | `sweep`, `constant`, `poisson`, `synchronous`, `throughput` |
| `--rate` | Requests per second or sweep count | `10` (for constant), `20` (for sweep) |
| `--max-seconds` | Maximum benchmark duration | `300` (5 min), `1800` (30 min) |
| `--data` | Synthetic data configuration | `prompt_tokens=256,output_tokens=128,samples=100` |
| `--output-path` | Output file path | `/results/my-benchmark.html` |

### Rate Types

1. **`sweep`** (Recommended for capacity planning)
   - Automatically finds min/max rates
   - Runs multiple benchmarks at different rates
   - Best for understanding model capacity
   - Example: `--rate-type sweep --rate 10`

2. **`constant`** (For load testing)
   - Sends requests at a constant rate
   - Good for testing specific QPS targets
   - Example: `--rate-type constant --rate 15`

3. **`poisson`** (For realistic traffic)
   - Requests follow Poisson distribution
   - Mimics real-world traffic patterns
   - Example: `--rate-type poisson --rate 10`

4. **`synchronous`** (For latency baseline)
   - One request at a time
   - Measures best-case latency
   - Example: `--rate-type synchronous` (no --rate needed)

5. **`throughput`** (For max capacity)
   - All requests in parallel
   - Measures maximum throughput
   - Example: `--rate-type throughput`

---

## Viewing Results

### Web UI

1. Get the reports URL:
   ```bash
   REPORTS_URL=$(oc get route guidellm-reports -n private-ai-demo -o jsonpath='{.spec.host}')
   echo "https://${REPORTS_URL}"
   ```

2. Open in your browser

3. The index page will show all available benchmark reports:
   - Daily benchmarks (in blue)
   - Weekly benchmarks (in purple)
   - Manual benchmarks (in orange)

4. Click on any report to view the interactive HTML with charts

### Direct File Access

Access report files directly from the PVC:

```bash
# List all reports
oc exec -it deployment/guidellm-reports -n private-ai-demo -- ls -lh /usr/share/nginx/html/

# Download a specific report
oc cp private-ai-demo/guidellm-reports-xxxxx:/usr/share/nginx/html/mistral-quantized-20241110.html ./report.html
```

### MinIO S3

Access reports from MinIO bucket:

```bash
# Configure mc alias (from your local machine)
mc alias set minio http://minio.private-ai-demo.apps.your-cluster.com \
  $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# List all reports
mc ls minio/guidellm-results/

# Download a report
mc cp minio/guidellm-results/mistral-quantized-20241110.html ./
```

---

## Scheduled Benchmarks

### Daily Benchmarks

Runs every day at 2 AM (configurable):

```yaml
schedule: "0 2 * * *"  # Cron format
timeZone: "America/New_York"
```

**Configuration:**
- Duration: 30 minutes per model
- Prompts: 256 tokens
- Outputs: 128 tokens
- Samples: 100 requests
- Rate type: sweep (10 steps)

**Edit schedule:**
```bash
oc edit cronjob guidellm-daily-benchmark -n private-ai-demo
```

### Weekly Benchmarks

Runs every Sunday at midnight (configurable):

```yaml
schedule: "0 0 * * 0"  # Sundays at midnight
```

**Configuration:**
- Duration: 1 hour per model
- Prompts: 512 tokens
- Outputs: 256 tokens
- Samples: 500 requests
- Rate type: sweep (20 steps)

**Edit schedule:**
```bash
oc edit cronjob guidellm-weekly-comprehensive -n private-ai-demo
```

### Disable/Enable CronJobs

```bash
# Disable daily benchmarks
oc patch cronjob guidellm-daily-benchmark -n private-ai-demo \
  -p '{"spec":{"suspend":true}}'

# Enable daily benchmarks
oc patch cronjob guidellm-daily-benchmark -n private-ai-demo \
  -p '{"spec":{"suspend":false}}'
```

### Trigger CronJob Manually

```bash
# Run daily benchmark now
oc create job guidellm-daily-now-$(date +%s) \
  --from=cronjob/guidellm-daily-benchmark \
  -n private-ai-demo
```

---

## Grafana Integration

### Available Metrics

GuideLLM exports the following Prometheus metrics:

```promql
# Latency metrics
guidellm_request_latency_p50_seconds{model="mistral-24b-quantized",benchmark_type="daily"}
guidellm_request_latency_p95_seconds{model="mistral-24b-quantized",benchmark_type="daily"}
guidellm_request_latency_p99_seconds{model="mistral-24b-quantized",benchmark_type="daily"}

# TTFT (Time to First Token)
guidellm_ttft_p50_seconds{model="mistral-24b-quantized",benchmark_type="daily"}
guidellm_ttft_p95_seconds{model="mistral-24b-quantized",benchmark_type="daily"}

# Throughput
guidellm_throughput_requests_per_second{model="mistral-24b-quantized",benchmark_type="daily"}
guidellm_throughput_tokens_per_second{model="mistral-24b-quantized",benchmark_type="daily"}

# Success rate
guidellm_request_success_rate{model="mistral-24b-quantized",benchmark_type="daily"}

# Total requests
guidellm_total_requests{model="mistral-24b-quantized",benchmark_type="daily"}
```

### Query Examples

**Average P95 latency over time:**
```promql
guidellm_request_latency_p95_seconds
```

**Compare throughput between models:**
```promql
guidellm_throughput_requests_per_second{benchmark_type="daily"}
```

**Success rate (should be 1.0):**
```promql
guidellm_request_success_rate
```

**Latency SLO tracking (P95 < 2 seconds):**
```promql
guidellm_request_latency_p95_seconds < 2
```

### Creating a Dashboard

1. Open Grafana
2. Create New Dashboard
3. Add Panel with query:
   ```promql
   guidellm_request_latency_p95_seconds
   ```
4. Set visualization type to "Time series"
5. Add threshold lines for SLOs

---

## Troubleshooting

### Job Fails to Start

**Symptom:** Job stays in Pending state

**Check:**
```bash
# View job status
oc describe job guidellm-test-xxxxx -n private-ai-demo

# Check pod events
oc get events -n private-ai-demo --sort-by='.lastTimestamp' | grep guidellm
```

**Common Causes:**
- PVC not bound: `oc get pvc guidellm-results -n private-ai-demo`
- Insufficient resources: Check CPU/memory availability
- Image pull failure: `oc describe pod <pod-name>`

### No Reports Appearing in Web UI

**Check nginx pod:**
```bash
# Check if nginx is running
oc get pods -n private-ai-demo -l app=guidellm-reports

# Check nginx logs
oc logs -f deployment/guidellm-reports -n private-ai-demo

# Check PVC contents
oc exec -it deployment/guidellm-reports -n private-ai-demo -- ls -la /usr/share/nginx/html/
```

**Check MinIO:**
```bash
# Verify bucket exists
mc ls minio/guidellm-results/
```

### Benchmark Hangs or Times Out

**Check model connectivity:**
```bash
# Test model endpoint from within cluster
oc run test-curl --rm -i --restart=Never --image=curlimages/curl -- \
  curl -v http://mistral-24b-quantized-predictor.private-ai-demo.svc.cluster.local/v1/models
```

**Check model status:**
```bash
# Verify InferenceService is READY
oc get isvc mistral-24b-quantized -n private-ai-demo

# Check predictor pods
oc get pods -n private-ai-demo -l serving.kserve.io/inferenceservice=mistral-24b-quantized
```

### Metrics Not in Grafana

**Check Pushgateway:**
```bash
# Port-forward to Pushgateway
oc port-forward svc/prometheus-pushgateway 9091:9091 -n private-ai-demo

# Query metrics (from another terminal)
curl http://localhost:9091/metrics | grep guidellm
```

**Check metrics exporter:**
```bash
# Find metrics exporter sidecar in completed jobs
oc logs job/guidellm-test-xxxxx -c metrics-exporter -n private-ai-demo
```

### HTML Report Not Loading

**Check hosted UI availability:**
- Reports use the official hosted UI at `https://blog.vllm.ai/guidellm/ui/latest`
- Ensure your cluster can reach external URLs (or run in connected environment)

---

## Advanced Usage

### Custom Benchmark Configurations

Create a ConfigMap with custom configs:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-guidellm-configs
  namespace: private-ai-demo
data:
  stress-test.env: |
    GUIDELLM_RATE_TYPE=throughput
    GUIDELLM_MAX_SECONDS=1800
    GUIDELLM_DATA=prompt_tokens=1024,output_tokens=512,samples=200
```

### Batch Benchmarking Multiple Models

```bash
#!/bin/bash
MODELS=("mistral-24b-quantized" "mistral-24b")

for MODEL in "${MODELS[@]}"; do
  echo "Benchmarking ${MODEL}..."
  oc create job guidellm-${MODEL}-$(date +%s) \
    --from=job/guidellm-benchmark-${MODEL} \
    -n private-ai-demo
  sleep 60  # Wait 1 minute between jobs
done
```

### Export Results to CSV

```bash
# Extract metrics from JSON (if available)
oc exec -it deployment/guidellm-reports -n private-ai-demo -- \
  jq -r '.benchmarks[] | [.metrics.request_latency_p95, .metrics.request_throughput] | @csv' \
  /usr/share/nginx/html/mistral-quantized-20241110.json
```

### Cleanup Old Reports

```bash
# Delete reports older than 30 days
oc exec -it deployment/guidellm-reports -n private-ai-demo -- \
  find /usr/share/nginx/html/ -name "*.html" -mtime +30 -delete
```

---

## References

### Official Documentation
- [GuideLLM GitHub](https://github.com/vllm-project/guidellm)
- [GuideLLM User Guide](https://github.com/vllm-project/guidellm/blob/main/docs/user_guide.md)
- [Red Hat Developer Article](https://developers.redhat.com/articles/2025/06/20/guidellm-evaluate-llm-deployments-real-world-inference)
- [Disconnected Implementation](https://github.com/rh-aiservices-bu/disconnected-rhaiis-guidellm)

### Container Image
- **Official Image**: `ghcr.io/vllm-project/guidellm:latest`
- **Hosted UI**: `https://blog.vllm.ai/guidellm/ui/latest`

### Internal Project Docs
- [Implementation Plan](../GUIDELLM-UI-REVISED-PLAN.md)
- [GitOps Manifests](../gitops/stage03-model-monitoring/guidellm/)
- [Deployment README](../gitops/stage03-model-monitoring/guidellm/README.md)

---

**Last Updated**: November 10, 2025  
**Version**: 1.0  
**Maintainer**: Private AI Demo Team

