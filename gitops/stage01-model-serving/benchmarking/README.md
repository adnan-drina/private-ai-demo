# GuideLLM Benchmarking Component

Automated performance benchmarking for vLLM models using GuideLLM with Model Registry integration.

## Overview

This component provides cloud-native benchmarking for Mistral models deployed with vLLM/KServe:
- **Quantized Model** (1 GPU on g6.4xlarge): `mistral-24b-quantized`
- **Full Precision Model** (4 GPUs on g6.12xlarge): `mistral-24b`

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Job: guidellm-benchmark-quantized/full           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Init Container: fetch-tokenizer                           │
│  └─ Downloads tokenizer from HuggingFace                   │
│                                                             │
│  Container 1: run-guidellm                                 │
│  └─ Executes benchmark (4 concurrency levels)              │
│  └─ Saves results to /results/*.json (dedicated PVC)       │
│                                                             │
│  Container 2: publish-to-registry (sidecar)                │
│  └─ Waits for benchmark completion (file size stability)   │
│  └─ Parses JSON results                                    │
│  └─ Publishes metrics to Model Registry as Properties      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. `configmap-publish-script.yaml`
Python script for publishing benchmark results to OpenShift AI Model Registry.

**Key Features:**
- Waits for benchmark completion using file size stability check
- Parses GuideLLM JSON output
- Extracts key metrics (throughput, TTFT, ITL, latency)
- Publishes as customProperties (key-value pairs) to Model Registry
- Uses ServiceAccount token for authentication

### 2. `job-guidellm-quantized.yaml`
Benchmark job for the quantized model (1 GPU).

**Configuration:**
- Model: `mistral-24b-quantized`
- Endpoint: `https://mistral-24b-quantized-private-ai-demo.${CLUSTER_DOMAIN}/v1`
- Tokenizer: `RedHatAI/Mistral-Small-24B-Instruct-2501-quantized.w4a16`
- Concurrency levels: 1, 5, 10, 25
- Timeout per level: 120 seconds
- Total duration: ~8-10 minutes

### 3. `job-guidellm-full.yaml`
Benchmark job for the full precision model (4 GPUs).

**Configuration:**
- Model: `mistral-24b`
- Endpoint: `https://mistral-24b-private-ai-demo.${CLUSTER_DOMAIN}/v1`
- Tokenizer: `mistralai/Mistral-Small-24B-Instruct-2501`
- Concurrency levels: 1, 5, 10, 25
- Timeout per level: 120 seconds
- Total duration: ~8-10 minutes

## Benchmark Metrics Published

Benchmark results are appended to the model version **description** field in a formatted summary.

> **Note**: We use the description field instead of customProperties because Model Registry requires custom properties to have pre-defined metadata types. The description field is always available and doesn't require admin setup.

### Metrics Included

| Property | Description | Example |
|----------|-------------|---------|
| `benchmark_date` | ISO date of benchmark | `2025-10-22` |
| `benchmark_tool` | Tool used | `GuideLLM` |
| `benchmark_concurrency` | Concurrency level tested | `5` |
| `benchmark_throughput` | Tokens per second | `183.10` |
| `benchmark_ttft_p50` | Time to first token (p50) in ms | `102.59` |
| `benchmark_ttft_p90` | Time to first token (p90) in ms | `103.03` |
| `benchmark_ttft_p99` | Time to first token (p99) in ms | `103.23` |
| `benchmark_itl_p50` | Inter-token latency (p50) in ms | `54.38` |
| `benchmark_itl_p90` | Inter-token latency (p90) in ms | `54.45` |
| `benchmark_itl_p99` | Inter-token latency (p99) in ms | `54.46` |
| `benchmark_cost_per_1k` | Cost per 1K tokens (USD) | `0.002791` |
| `benchmark_instance` | Instance type | `g6.12xlarge` |
| `benchmark_gpu_count` | Number of GPUs | `4` |

## Deployment

### Via Kustomize (Recommended)

```bash
# Deploy with Stage 1 overlay
oc apply -k gitops/overlays/stage1/

# Or deploy benchmarking component directly
oc apply -k gitops/components/benchmarking/
```

### Manual Deployment

```bash
# Apply ConfigMap
oc apply -f configmap-publish-script.yaml

# Run benchmarks
oc apply -f job-guidellm-quantized.yaml
oc apply -f job-guidellm-full.yaml
```

## Monitoring

```bash
# Check job status
oc get jobs -n private-ai-demo -l app=guidellm-benchmark

# Check pod status
oc get pods -n private-ai-demo -l app=guidellm-benchmark

# View benchmark logs
oc logs -n private-ai-demo <pod-name> -c run-guidellm

# View publishing logs
oc logs -n private-ai-demo <pod-name> -c publish-to-registry
```

## Design Decisions

### Storage: Dedicated PVCs per Job
- **Parallel execution**: Each job has its own PVC, no conflicts
- **Persistent storage**: Results survive pod deletion (not ephemeral)
- **Direct access**: Workbench mounts PVCs to read results
- **Published to registry**: Results also sent to Model Registry for visibility
- **Simpler**: No persistent storage management

### Why file size stability check?
- Both containers (benchmark + publish) start simultaneously
- Publishing must wait for benchmark completion
- Simple file existence check is insufficient (file created immediately but empty)
- File size stability (2 consecutive checks with same size) ensures completion

### Why description field over customProperties?
- **No pre-definition required**: customProperties need metadata types defined by admin
- **Always available**: description is a standard field on all model versions  
- **Human-readable**: Formatted text visible in Model Registry UI
- **No dependencies**: Works out-of-the-box without admin setup
- **Still comparable**: Users can see metrics side-by-side in the UI

> **Alternative**: For production environments with admin access, customProperties could be pre-defined to enable structured, queryable benchmark data.

## Troubleshooting

### Job stuck in Init
Check tokenizer download:
```bash
oc logs -n private-ai-demo <pod-name> -c fetch-tokenizer
```

### Benchmark fails
Check model endpoint and vLLM service:
```bash
oc get inferenceservice -n private-ai-demo
oc logs -n private-ai-demo <pod-name> -c run-guidellm
```

### Publishing fails
Check Model Registry connection and permissions:
```bash
oc logs -n private-ai-demo <pod-name> -c publish-to-registry
oc get sa ai-workload-sa -n private-ai-demo
```

## Future Enhancements

- [ ] Automated periodic benchmarking (CronJob)
- [ ] Comparison reports across model versions
- [ ] Integration with Grafana dashboards
- [ ] Cost optimization recommendations
- [ ] A/B testing support

