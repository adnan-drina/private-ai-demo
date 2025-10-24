# Stage 1 Demo Notebooks

## 01-vllm-benchmark-demo.ipynb

### Purpose
Demonstrates the business value of vLLM inference server and Red Hat's quantized models through performance benchmarking and cost analysis.

### What It Shows

**1. vLLM Performance Value**
- High-throughput inference serving
- Low-latency responses
- Efficient GPU utilization
- Production-ready performance

**2. Quantization Economics**
- Cost comparison: 1 GPU vs 4 GPUs
- Performance comparison: Quantized vs Full Precision
- Quality assessment: Minimal quality loss
- Business recommendations

### Audience
- **Primary:** Business stakeholders, decision makers
- **Secondary:** Technical architects evaluating OpenShift AI

### Key Metrics Demonstrated
- **Throughput:** Tokens per second
- **Latency:** Response time
- **Cost:** Infrastructure cost per 1K tokens
- **Quality:** Output comparison

### Prerequisites
- Stage 1 deployed (`./deploy.sh`)
- Both models running:
  - `mistral-24b-quantized` (1 GPU on g6.4xlarge)
  - `mistral-24b-full` (4 GPUs on g6.12xlarge)
- Access to JupyterLab workbench

### How to Use

1. **Deploy Stage 1:**
   ```bash
   cd stage1-sovereign-ai
   ./deploy.sh
   ```

2. **Access JupyterLab:**
   - Open OpenShift AI dashboard
   - Launch JupyterLab workbench
   - Navigate to `01-vllm-benchmark-demo.ipynb`

3. **Run the notebook:**
   - Execute cells sequentially
   - Review performance charts
   - Read business insights

### Expected Results

**Performance:**
- Quantized model: Faster response times (fewer GPUs = less coordination overhead)
- Full precision model: Slightly lower latency, similar throughput
- Both models: Production-ready performance

**Cost:**
- Quantized: ~$1.84/hour (g6.4xlarge)
- Full: ~$5.52/hour (g6.12xlarge)
- **Savings: ~67% with quantized model**

**Quality:**
- Both models produce high-quality outputs
- Minimal quality difference for business applications
- Quantization is suitable for most use cases

### Business Takeaways

1. **Start with quantized models** for cost optimization
2. **Scale to full precision** only when maximum quality is critical
3. **vLLM provides production-grade performance** for both
4. **Red Hat validates models** for enterprise reliability
5. **Infrastructure sovereignty** - all models on your hardware

### Demo Flow (5-10 minutes)

1. **Introduction** (1 min) - Explain vLLM and quantization value
2. **Run benchmarks** (2 min) - Execute test against both models
3. **Compare results** (2 min) - Show performance charts
4. **Cost analysis** (2 min) - Explain economics
5. **Quality check** (2 min) - Compare outputs
6. **Business insights** (2 min) - Discuss recommendations

### Troubleshooting

**Issue:** Model endpoints not found
- **Solution:** Ensure both InferenceServices are running: `oc get isvc -n private-ai-demo`

**Issue:** Timeout errors
- **Solution:** Models may still be loading. Wait 2-3 minutes and retry.

**Issue:** Different results than expected
- **Solution:** Performance varies by cluster load. Focus on relative comparison.

### Related Documentation
- `/stage1-sovereign-ai/README.md` - Stage 1 overview
- `/gitops/base/vllm/` - vLLM deployment configuration
- `/docs/` - Additional documentation

