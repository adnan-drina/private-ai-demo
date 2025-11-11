# GuideLLM - OpenShift Console Usage Guide

## ✅ Status: Both Benchmarks Working!

### Completed Runs
- **Quantized Model**: `mistral-quantized-20251110-155054.html` ✅
- **Full Precision Model**: `mistral-full-20251110-155053.html` ✅

---

## 🎯 How to Create Jobs from OpenShift Console

### Step 1: Open the Jobs Page

Navigate to:
```
Workloads → Jobs → private-ai-demo namespace
```

Or use this direct link (already open in your screenshot):
```
https://console-openshift-console.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/k8s/ns/private-ai-demo/batch~v1~Job
```

### Step 2: Find the Job Template

You'll see two job templates:
- `guidellm-benchmark-mistral-quantized` (Status: Complete, 1/1)
- `guidellm-benchmark-mistral-full` (Status: Complete, 1/1)

### Step 3: Create a New Job

1. **Click the ⋮ (kebab menu)** on the right side of the job row
2. **Select "Create Job"** from the dropdown menu
3. OpenShift will create a new job with a unique name (e.g., `guidellm-benchmark-mistral-quantized-xxxxx`)
4. The new job will start running immediately

### Step 4: Monitor the Job

1. Click on the newly created job name
2. Go to the **"Pods"** tab to see the pod status
3. Go to the **"Logs"** tab to see real-time benchmark output
4. Wait ~35-45 seconds for completion

### Step 5: Access the Results

The HTML report is generated inside the pod at:
```
/results/mistral-[quantized|full]-TIMESTAMP.html
```

To download it:
```bash
# Get the pod name
POD=$(oc get pods -n private-ai-demo -l app=guidellm --field-selector=status.phase=Succeeded --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

# Copy the HTML file (before pod is deleted)
oc cp private-ai-demo/$POD:/results/mistral-quantized-TIMESTAMP.html ./guidellm-report.html -c guidellm
```

**Note**: The pod and its files are kept for 24 hours (`ttlSecondsAfterFinished: 86400`), then automatically deleted.

---

## 🚀 Alternative: CLI Method

### Quantized Model Benchmark
```bash
# Create and monitor
oc create job guidellm-test-quantized-$(date +%s) \
  --from=job/guidellm-benchmark-mistral-quantized \
  -n private-ai-demo

# Watch logs
oc logs -f -l app=guidellm,model=mistral-24b-quantized -c guidellm -n private-ai-demo
```

### Full Precision Model Benchmark
```bash
# Create and monitor
oc create job guidellm-test-full-$(date +%s) \
  --from=job/guidellm-benchmark-mistral-full \
  -n private-ai-demo

# Watch logs
oc logs -f -l app=guidellm,model=mistral-24b -c guidellm -n private-ai-demo
```

---

## 📊 What the Benchmark Does

Each benchmark:
1. **Discovers the model URL** (via init container using Knative Service revision)
2. **Generates synthetic test data** (10 requests with 128 prompt tokens, 64 output tokens)
3. **Runs the benchmark** (synchronous mode, ~35-45 seconds)
4. **Generates HTML report** with embedded GuideLLM UI from https://blog.vllm.ai/guidellm/ui/latest
5. **Attempts S3 upload** (if MinIO credentials are configured)

### Benchmark Metrics Collected
- **Throughput**: Requests/second, Tokens/second (input & output)
- **Latency**: End-to-end request latency (mean, median, p99)
- **TTFT**: Time To First Token (mean, median, p99)
- **ITL**: Inter-Token Latency (mean, median, p99)
- **TPOT**: Time Per Output Token (mean, median, p99)

---

## 🎨 GuideLLM UI Features

The generated HTML reports include an **interactive UI** with:
- 📊 **Performance Charts**: Throughput, latency, TTFT visualizations
- 📈 **Comparison Views**: Side-by-side model comparisons
- 🔍 **Detailed Metrics**: Drill down into individual request statistics
- 💾 **Export Options**: Download data as JSON/CSV

**No web server needed** - just open the HTML file in your browser!

---

## 🔧 Troubleshooting

### Issue: "Create Job" option not visible

**Cause**: Job is still running or in error state

**Solution**:
1. Wait for job to complete
2. Or delete the job and recreate it:
   ```bash
   oc delete job guidellm-benchmark-mistral-quantized -n private-ai-demo
   oc apply -f gitops/stage03-model-monitoring/guidellm/job-guidellm-mistral-quantized.yaml
   ```

### Issue: Job fails with "Error" status

**Cause**: Usually data format or API connectivity issues

**Solution**:
1. Check pod logs:
   ```bash
   oc logs -l app=guidellm,model=mistral-24b-quantized -c guidellm -n private-ai-demo
   ```
2. Check init container logs:
   ```bash
   oc logs -l app=guidellm,model=mistral-24b-quantized -c get-inference-url -n private-ai-demo
   ```

### Issue: Can't find HTML report

**Cause**: Results are in ephemeral `emptyDir` volume (deleted when pod completes)

**Solution**:
1. Copy the file before the pod is deleted (24 hour window)
2. Or configure MinIO S3 upload (run `stages/stage3-model-monitoring/deploy.sh`)

---

## 📝 Scheduled Benchmarks

Automated benchmarks run via CronJobs:

### Daily Benchmarks
- **Schedule**: Every day at 2:00 AM EST
- **Duration**: ~30 minutes (1800 seconds)
- **Rate**: 10 concurrent requests
- **CronJob**: `guidellm-daily-benchmark`

### Weekly Benchmarks
- **Schedule**: Every Sunday at 00:00 EST  
- **Duration**: ~1 hour (3600 seconds)
- **Rate**: 20 concurrent requests
- **CronJob**: `guidellm-weekly-comprehensive`

Check CronJob status:
```bash
oc get cronjobs -n private-ai-demo -l app=guidellm
```

---

## 🎯 Next Steps

1. **✅ Refresh your OpenShift Console** - you should now see both jobs with "1/1" completions
2. **✅ Try "Create Job"** - click the ⋮ menu and create a new benchmark run
3. **📊 View results in Grafana** (when available):
   ```
   https://grafana-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com
   Login: admin / admin123
   ```
4. **📁 Set up MinIO S3 upload** (optional):
   ```bash
   cd stages/stage3-model-monitoring
   ./deploy.sh
   ```

---

**Last Updated**: 2025-11-10  
**Benchmark Status**: ✅ Both quantized and full precision models working

