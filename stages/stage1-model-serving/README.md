# Stage 1: Model Serving with vLLM

## Overview

Stage 1 demonstrates efficient, scalable model serving using vLLM on GPU-accelerated infrastructure. This stage deploys two Mistral models (quantized and full precision), runs comprehensive benchmarks, and integrates with the Model Registry.

## Components

### Model Inference
- **vLLM ServingRuntime** - Shared runtime for efficient inference
- **Mistral 24B Quantized** - 1 GPU (g6.4xlarge), W4A16 quantization
- **Mistral 24B Full** - 4 GPUs (g6.12xlarge), FP16 precision
- **Model Download Jobs** - Automated download from HuggingFace

### Storage & Artifacts
- **MinIO** - S3-compatible storage for models and results
- **PVCs** - Persistent storage for downloaded models

### Benchmarking & Evaluation
- **GuideLLM Benchmark Jobs** - Performance testing with multiple concurrency levels
- **Model Registry Integration** - Automated result publishing
- **Benchmark Results Notebook** - Interactive analysis and comparison

## Prerequisites

- **Stage 0** deployed and validated
- **HuggingFace Token** - For model downloads (set in `.env`)
- GPU nodes ready (1x g6.4xlarge, 1x g6.12xlarge)

## Deployment

```bash
# Create .env file with your HuggingFace token
cp env.template .env
# Edit .env and add your HF_TOKEN

# Deploy all Stage 1 components
./deploy.sh

# Validate deployment
./validate.sh
```

## Verification

Monitor deployment progress:

```bash
# Check InferenceServices
oc get inferenceservice -n private-ai-demo

# Monitor model downloads
oc get jobs -n private-ai-demo -l app=model-loader
oc logs -f job/download-mistral-24b-quantized -n private-ai-demo

# Check benchmark jobs
oc get jobs -n private-ai-demo -l app=guidellm-benchmark

# Access benchmark notebook
# Navigate to OpenShift AI dashboard → Workbenches → rag-testing
# Open: 01-benchmark.ipynb
```

## Model Endpoints

After deployment, models are accessible at:

```bash
# Get routes
oc get routes -n private-ai-demo | grep mistral

# Test inference
curl -k https://mistral-24b-quantized-private-ai-demo.apps.<cluster>/v1/models
```

## Benchmark Results

Benchmark jobs test each model with multiple concurrency levels:
- 1 concurrent request (baseline)
- 5 concurrent requests
- 10 concurrent requests
- 25 concurrent requests

Results include:
- **Response Time** - End-to-end latency
- **TTFT** (Time To First Token) - P50, P90, P99
- **Throughput** - Tokens per second
- **GPU Utilization** - Memory and compute

Results are:
1. Stored in MinIO
2. Published to Model Registry as properties
3. Visualized in the benchmark notebook

## Operational Runbook: Rate Limits

To ensure stable latency and avoid upstream disconnects during load testing and production-like traffic, enforce the following per-instance request rate limits when driving traffic through GuideLLM or other clients:

- Quantized (1×L4, W4A16): 5 requests/second
- Full precision (4×L4, BF16): 10 requests/second

Guidance:

- These limits map to the GuideLLM `rate` setting. In our Tekton task `run-guidellm-v2`, use the `rates` parameter to control the step load (e.g., `"1 5"` for quantized, `"1 5 10"` for full).
- Keep the 20‑request warmup to prime prefix cache before measurement.
- Keep fixed-duration runs with dynamic samples (`samples = rate × duration`) to generate steady load.
- Monitor vLLM logs for `Running`/`Waiting` and KV cache usage. If `Waiting > 0` persists, reduce `rate` one step or shorten `output_tokens` for that run only.

These limits were validated on AWS g6.4xlarge (quantized) and g6.12xlarge (full) with vLLM chunked prefill and prefix caching enabled.

## Key Metrics Comparison

| Metric | Quantized (1 GPU) | Full (4 GPUs) |
|--------|-------------------|---------------|
| Model Size | ~13 GB | ~48 GB |
| GPU Memory | ~24 GB | ~80 GB |
| Precision | W4A16 | FP16 |
| Cost/Hour | ~$1.00 | ~$5.00 |

## Troubleshooting

### Models Not Loading
- Check GPU node availability: `oc get nodes -l nvidia.com/gpu.present=true`
- Check pod placement: `oc get pods -n private-ai-demo -o wide`
- Check vLLM logs: `oc logs -n private-ai-demo <predictor-pod>`

### Downloads Failing
- Verify HF_TOKEN in secret: `oc get secret huggingface-secret -n private-ai-demo -o yaml`
- Check download job logs: `oc logs job/download-mistral-24b-quantized -n private-ai-demo`

### Benchmarks Not Running
- Check PVC status: `oc get pvc -n private-ai-demo`
- Verify models are ready: `oc get inferenceservice -n private-ai-demo`
- Check job status: `oc describe job <benchmark-job> -n private-ai-demo`

## GitOps Structure

```
gitops-new/stage01-model-serving/
├── base-namespace/      # Namespace configuration
├── base-secrets/        # HuggingFace token secret
├── vllm/               # ServingRuntime + InferenceServices
├── model-loader/       # Download jobs
├── minio/              # Object storage
├── benchmarking/       # GuideLLM jobs + registry integration
└── workbench/          # Jupyter notebook
```

## Next Steps

Once Stage 1 is validated:
1. Review benchmark results in the notebook
2. Check Model Registry for registered models
3. Proceed to **Stage 2: Model Alignment with RAG + Llama Stack**

## Documentation

- [vLLM Documentation](https://docs.vllm.ai/)
- [KServe InferenceService](https://kserve.github.io/website/latest/modelserving/v1beta1/llm/vllm/)
- [GuideLLM Benchmarking](https://github.com/vllm-project/guidellm)
- [Red Hat Model Serving Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.24/html/serving_models/)
