# GuideLLM Integration - Revised Implementation Plan
## Using Official Container Images

## Executive Summary

This **revised plan** leverages the **official GuideLLM container images** (`ghcr.io/vllm-project/guidellm:latest`) and the **hosted UI** (`https://blog.vllm.ai/guidellm/ui/latest`) to minimize custom code while achieving full functionality.

**Key Changes from Original Plan:**
- ✅ **No custom Containerfile needed** - Use official `ghcr.io/vllm-project/guidellm:latest`
- ✅ **No custom React development** - Use hosted UI build for HTML reports
- ✅ **Minimal backend code** - Only job scheduling and result aggregation
- ✅ **Follow Red Hat patterns** - Based on [`disconnected-rhaiis-guidellm`](https://github.com/rh-aiservices-bu/disconnected-rhaiis-guidellm)

**Timeline Reduction:** 6 weeks → **2-3 weeks**

---

## Architecture

### Simplified Architecture

```
┌──────────────────────────────────────────────────────────┐
│              Private AI Demo - GuideLLM Integration      │
└──────────────────────────────────────────────────────────┘

User Triggers Benchmark
     │
     ▼
┌─────────────────────────────────────────┐
│  Kubernetes CronJob / Manual Job        │
│  Image: ghcr.io/vllm-project/guidellm   │
│  ┌────────────────────────────────────┐ │
│  │ GuideLLM CLI                       │ │
│  │ - benchmark command                │ │
│  │ - --output-path=benchmarks.html    │ │
│  │ - Uses hosted UI build             │ │
│  └─────────────┬──────────────────────┘ │
└────────────────┼────────────────────────┘
                 │
     ┌───────────┼───────────┐
     │           │           │
     ▼           ▼           ▼
┌─────────┐  ┌──────────┐  ┌──────────────┐
│ vLLM    │  │  MinIO   │  │ OTEL         │
│ Models  │  │  (S3)    │  │ Collector    │
│         │  │  Store:  │  │ (Metrics)    │
│         │  │  - HTML  │  └──────┬───────┘
│         │  │  - JSON  │         │
└─────────┘  └──────────┘         │
                                  ▼
                            ┌──────────────┐
                            │  Grafana     │
                            │  - Dashboard │
                            │  - Links to  │
                            │    Reports   │
                            └──────────────┘
```

### Key Components

1. **GuideLLM Official Container** (`ghcr.io/vllm-project/guidellm:latest`)
   - Pre-built, maintained by vLLM project
   - Includes CLI and all dependencies
   - Supports all benchmark modes

2. **Hosted UI Build** (`https://blog.vllm.ai/guidellm/ui/latest`)
   - Official hosted frontend
   - Generates interactive HTML reports
   - No custom React development needed

3. **Kubernetes Jobs/CronJobs**
   - Run benchmarks on-demand or scheduled
   - Store results in MinIO S3
   - Export metrics to OTEL Collector

4. **Simple Web Server** (Optional - nginx)
   - Serve HTML reports from MinIO
   - Minimal custom code (static file serving)

---

## Implementation Plan

### Phase 1: Core Integration (Week 1)

#### 1.1 Kubernetes Job Configuration

**Objective**: Deploy GuideLLM as Kubernetes Jobs to run benchmarks.

**Tasks:**
- [ ] Create Kubernetes Job manifest for on-demand benchmarks
- [ ] Create CronJob manifest for scheduled benchmarks
- [ ] Configure PVC for result storage
- [ ] Test benchmark against vLLM InferenceServices

**Files to Create:**
```
gitops/stage03-model-monitoring/guidellm/
├── kustomization.yaml
├── job-guidellm-benchmark.yaml          # Manual job template
├── cronjob-guidellm-daily.yaml          # Scheduled daily benchmark
├── pvc-guidellm-results.yaml            # PVC for storing results
├── configmap-guidellm-config.yaml       # Benchmark configurations
└── README.md
```

**Example Job Manifest:**
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: guidellm-benchmark-mistral-quantized
  namespace: private-ai-demo
  labels:
    app: guidellm
    model: mistral-24b-quantized
spec:
  backoffLimit: 1
  template:
    metadata:
      labels:
        app: guidellm
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
        - sweep
        - --rate
        - "10"
        - --max-seconds
        - "300"
        - --data
        - "prompt_tokens=256,output_tokens=128,samples=100"
        - --output-path
        - /results/mistral-quantized-$(date +%Y%m%d-%H%M%S).html
        env:
        - name: GUIDELLM__ENV
          value: "production"  # Uses hosted UI build
        volumeMounts:
        - name: results
          mountPath: /results
        - name: s3-config
          mountPath: /root/.aws
          readOnly: true
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
      - name: s3-config
        secret:
          secretName: guidellm-s3-credentials
```

**Estimated Time**: 2 days

---

#### 1.2 MinIO Integration

**Objective**: Configure MinIO S3 bucket for storing benchmark results.

**Tasks:**
- [ ] Create MinIO bucket: `guidellm-results`
- [ ] Create Secret with MinIO credentials
- [ ] Configure GuideLLM Job to upload results to S3
- [ ] Test S3 upload from GuideLLM container

**MinIO Secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: guidellm-s3-credentials
  namespace: private-ai-demo
type: Opaque
stringData:
  credentials: |
    [default]
    aws_access_key_id = ${MINIO_ACCESS_KEY}
    aws_secret_access_key = ${MINIO_SECRET_KEY}
  config: |
    [default]
    region = us-east-1
    output = json
    s3 =
        endpoint_url = http://minio.private-ai-demo.svc.cluster.local:9000
        signature_version = s3v4
```

**Post-Processing Script** (to upload to S3):
```yaml
# Add as an initContainer or sidecar
- name: upload-to-s3
  image: quay.io/minio/mc:latest
  command:
  - /bin/sh
  - -c
  - |
    mc alias set minio http://minio.private-ai-demo.svc.cluster.local:9000 \
      $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
    mc cp /results/*.html minio/guidellm-results/
    mc cp /results/*.json minio/guidellm-results/
  volumeMounts:
  - name: results
    mountPath: /results
```

**Estimated Time**: 1 day

---

### Phase 2: Web UI for Reports (Week 2)

#### 2.1 Static Web Server for HTML Reports

**Objective**: Deploy a simple nginx server to serve HTML reports from MinIO.

**Tasks:**
- [ ] Create nginx Deployment with S3 backend
- [ ] Configure OpenShift Route for external access
- [ ] Add index page listing all benchmark reports
- [ ] Test report viewing in browser

**Why nginx?**
- GuideLLM already generates HTML reports
- We just need to serve them (no custom React needed)
- nginx can proxy S3 or serve mounted volumes

**nginx ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: guidellm-nginx-config
  namespace: private-ai-demo
data:
  nginx.conf: |
    server {
      listen 8080;
      server_name _;
      
      location / {
        root /usr/share/nginx/html;
        autoindex on;  # Enable directory listing
        autoindex_exact_size off;
        autoindex_format html;
      }
      
      # Proxy to MinIO for reports
      location /reports/ {
        proxy_pass http://minio.private-ai-demo.svc.cluster.local:9000/guidellm-results/;
        proxy_set_header Host $host;
      }
    }
```

**Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guidellm-reports
  namespace: private-ai-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: guidellm-reports
  template:
    metadata:
      labels:
        app: guidellm-reports
    spec:
      containers:
      - name: nginx
        image: registry.access.redhat.com/ubi9/nginx-122:latest
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: results
          mountPath: /usr/share/nginx/html
      volumes:
      - name: nginx-config
        configMap:
          name: guidellm-nginx-config
      - name: results
        persistentVolumeClaim:
          claimName: guidellm-results
```

**Estimated Time**: 2 days

---

#### 2.2 Optional: Simple Index Page

**Objective**: Create a basic HTML index page to list all benchmark reports.

**Tasks:**
- [ ] Create static HTML index page
- [ ] Add JavaScript to list reports from MinIO (S3 API)
- [ ] Style with PatternFly CSS for Red Hat consistency

**Simple Index Page** (`index.html`):
```html
<!DOCTYPE html>
<html>
<head>
  <title>GuideLLM Benchmark Reports</title>
  <link rel="stylesheet" href="https://unpkg.com/@patternfly/patternfly/patternfly.css">
</head>
<body>
  <div class="pf-v5-c-page">
    <header class="pf-v5-c-page__header">
      <div class="pf-v5-c-page__header-brand">
        <h1>GuideLLM Benchmark Reports</h1>
      </div>
    </header>
    <main class="pf-v5-c-page__main">
      <section class="pf-v5-c-page__main-section">
        <h2>Available Reports</h2>
        <ul id="report-list" class="pf-v5-c-list">
          <!-- Populated by JavaScript -->
        </ul>
      </section>
    </main>
  </div>
  
  <script>
    // Fetch report list from MinIO (via nginx proxy)
    fetch('/reports/')
      .then(res => res.text())
      .then(html => {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const links = doc.querySelectorAll('a[href$=".html"]');
        const list = document.getElementById('report-list');
        
        links.forEach(link => {
          const li = document.createElement('li');
          const a = document.createElement('a');
          a.href = '/reports/' + link.getAttribute('href');
          a.textContent = link.textContent;
          a.className = 'pf-v5-c-button pf-m-link';
          li.appendChild(a);
          list.appendChild(li);
        });
      });
  </script>
</body>
</html>
```

**Estimated Time**: 1 day

---

### Phase 3: Observability Integration (Week 3)

#### 3.1 Export Metrics to OTEL Collector

**Objective**: Parse GuideLLM JSON output and expose metrics to Prometheus.

**Approach**: Add a sidecar container to parse JSON and push to Prometheus Pushgateway.

**Sidecar Container:**
```yaml
- name: metrics-exporter
  image: registry.access.redhat.com/ubi9/python-311:latest
  command:
  - python3
  - /scripts/export_metrics.py
  volumeMounts:
  - name: results
    mountPath: /results
  - name: scripts
    mountPath: /scripts
  env:
  - name: PUSHGATEWAY_URL
    value: "http://prometheus-pushgateway.private-ai-demo.svc.cluster.local:9091"
```

**Metrics Export Script** (`export_metrics.py`):
```python
#!/usr/bin/env python3
import json
import glob
import time
import requests
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

PUSHGATEWAY_URL = os.getenv('PUSHGATEWAY_URL', 'http://localhost:9091')

registry = CollectorRegistry()
latency_p50 = Gauge('guidellm_latency_p50_seconds', 'P50 latency', ['model'], registry=registry)
latency_p95 = Gauge('guidellm_latency_p95_seconds', 'P95 latency', ['model'], registry=registry)
throughput = Gauge('guidellm_throughput_rps', 'Requests per second', ['model'], registry=registry)
success_rate = Gauge('guidellm_success_rate', 'Request success rate', ['model'], registry=registry)

# Watch for new JSON files
while True:
    for json_file in glob.glob('/results/*.json'):
        with open(json_file, 'r') as f:
            data = json.load(f)
        
        model = data.get('model', 'unknown')
        benchmarks = data.get('benchmarks', [])
        
        for bench in benchmarks:
            metrics = bench.get('metrics', {})
            latency_p50.labels(model=model).set(metrics.get('request_latency_p50', 0))
            latency_p95.labels(model=model).set(metrics.get('request_latency_p95', 0))
            throughput.labels(model=model).set(metrics.get('request_throughput', 0))
            success_rate.labels(model=model).set(metrics.get('success_rate', 1.0))
        
        # Push to Prometheus Pushgateway
        push_to_gateway(PUSHGATEWAY_URL, job='guidellm', registry=registry)
        
        # Mark as processed
        os.rename(json_file, json_file + '.processed')
    
    time.sleep(60)
```

**Estimated Time**: 2 days

---

#### 3.2 Create Grafana Dashboard

**Objective**: Build Grafana dashboard to visualize GuideLLM metrics and link to HTML reports.

**Tasks:**
- [ ] Create GrafanaDashboard CR
- [ ] Add panels for latency, throughput, success rate
- [ ] Add table panel with links to HTML reports (stored in MinIO)
- [ ] Test dashboard in Grafana UI

**Dashboard Highlights:**
- **Overview Panel**: Total benchmarks, average latency, throughput
- **Latency Trend**: Time series chart showing P50, P95, P99
- **Model Comparison**: Bar chart comparing models
- **Reports Table**: Links to HTML reports in MinIO

**Estimated Time**: 2 days

---

## Updated Directory Structure

```
private-ai-demo/
│
├── gitops/stage03-model-monitoring/
│   ├── kustomization.yaml                           # UPDATED - Add guidellm
│   │
│   └── guidellm/                                    # NEW DIRECTORY
│       ├── kustomization.yaml
│       ├── job-guidellm-benchmark.yaml              # Job template
│       ├── cronjob-guidellm-daily.yaml              # CronJob for scheduled runs
│       ├── cronjob-guidellm-weekly.yaml             # Weekly comprehensive benchmark
│       ├── pvc-guidellm-results.yaml                # PVC for results
│       ├── configmap-guidellm-config.yaml           # Benchmark parameters
│       ├── secret-s3-credentials.yaml               # MinIO credentials
│       ├── deployment-nginx-reports.yaml            # nginx for serving reports
│       ├── configmap-nginx-config.yaml              # nginx configuration
│       ├── configmap-index-html.yaml                # Index page for reports
│       ├── configmap-metrics-exporter.yaml          # Python script for metrics
│       ├── service-guidellm-reports.yaml            # Service for nginx
│       ├── route-guidellm-reports.yaml              # OpenShift route
│       └── README.md
│
├── stages/stage3-model-monitoring/
│   ├── deploy.sh                                    # UPDATED - Add GuideLLM bucket
│   └── scripts/
│       ├── run-benchmark-manual.sh                  # NEW - Helper to run manual benchmark
│       └── export-metrics.py                        # NEW - Metrics export script
│
├── docs/
│   ├── GUIDELLM-INTEGRATION.md                      # NEW - User guide
│   └── assets/guidellm-screenshots/                 # NEW - Screenshots
│
└── GUIDELLM-UI-REVISED-PLAN.md                      # THIS FILE
```

---

## Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| GuideLLM Job | 1 CPU | 2 CPU | 2Gi | 4Gi | - |
| nginx Reports | 100m | 500m | 128Mi | 512Mi | - |
| Metrics Exporter | 100m | 500m | 256Mi | 512Mi | - |
| PVC (Results) | - | - | - | - | 20Gi |
| MinIO Bucket | - | - | - | - | 50Gi |

---

## Deployment Steps

### Step 1: Prepare MinIO

```bash
# Source environment
source .env

# Create MinIO bucket
mc alias set minio http://minio.private-ai-demo.svc.cluster.local:9000 \
  $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

mc mb minio/guidellm-results --ignore-existing

# Set bucket policy (public read for HTML reports)
mc anonymous set download minio/guidellm-results
```

### Step 2: Deploy GuideLLM Resources

```bash
# Apply GitOps manifests
oc apply -k gitops/stage03-model-monitoring/guidellm

# Verify PVC created
oc get pvc guidellm-results -n private-ai-demo

# Verify nginx deployment
oc get pods -n private-ai-demo -l app=guidellm-reports
```

### Step 3: Run First Benchmark

```bash
# Run manual job
oc create job guidellm-test-$(date +%s) \
  --from=cronjob/guidellm-daily-benchmark \
  -n private-ai-demo

# Watch job progress
oc logs -f job/guidellm-test-XXXXX -n private-ai-demo

# Check results
mc ls minio/guidellm-results/
```

### Step 4: Access Reports

```bash
# Get reports URL
REPORTS_URL=$(oc get route guidellm-reports -n private-ai-demo -o jsonpath='{.spec.host}')
echo "GuideLLM Reports: https://${REPORTS_URL}"

# Open in browser
open "https://${REPORTS_URL}"
```

---

## Configuration Examples

### Benchmark Configurations (ConfigMap)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: guidellm-benchmark-configs
  namespace: private-ai-demo
data:
  # Quick test (5 minutes)
  quick-test.env: |
    GUIDELLM_RATE_TYPE=sweep
    GUIDELLM_RATE=5
    GUIDELLM_MAX_SECONDS=300
    GUIDELLM_DATA=prompt_tokens=128,output_tokens=64,samples=50
  
  # Standard benchmark (15 minutes)
  standard.env: |
    GUIDELLM_RATE_TYPE=sweep
    GUIDELLM_RATE=10
    GUIDELLM_MAX_SECONDS=900
    GUIDELLM_DATA=prompt_tokens=256,output_tokens=128,samples=100
  
  # Comprehensive (1 hour)
  comprehensive.env: |
    GUIDELLM_RATE_TYPE=sweep
    GUIDELLM_RATE=20
    GUIDELLM_MAX_SECONDS=3600
    GUIDELLM_DATA=prompt_tokens=512,output_tokens=256,samples=500
```

---

## Success Criteria

### Week 1
- ✅ GuideLLM Job successfully runs against vLLM models
- ✅ HTML reports generated with hosted UI
- ✅ Results stored in MinIO S3

### Week 2
- ✅ nginx server serves HTML reports
- ✅ OpenShift Route accessible externally
- ✅ Index page lists all benchmark reports

### Week 3
- ✅ Metrics exported to Prometheus
- ✅ Grafana dashboard displays GuideLLM metrics
- ✅ CronJobs running scheduled benchmarks
- ✅ Documentation complete

---

## References

- **Official GuideLLM**: https://github.com/vllm-project/guidellm
- **Red Hat GuideLLM Guide**: https://developers.redhat.com/articles/2025/06/20/guidellm-evaluate-llm-deployments-real-world-inference
- **Red Hat Disconnected Implementation**: https://github.com/rh-aiservices-bu/disconnected-rhaiis-guidellm
- **Container Image**: `ghcr.io/vllm-project/guidellm:latest`
- **Hosted UI**: `https://blog.vllm.ai/guidellm/ui/latest`

---

## Summary of Changes from Original Plan

| Aspect | Original Plan | Revised Plan |
|--------|---------------|--------------|
| **Container Image** | Custom Containerfile | Official `ghcr.io/vllm-project/guidellm` |
| **Frontend UI** | Custom React app (Week 3) | Use hosted UI build (no custom code) |
| **Backend API** | Full FastAPI app | Minimal scripts (metrics export) |
| **Web Server** | Full app with state management | Simple nginx static file serving |
| **Timeline** | 6 weeks | **2-3 weeks** |
| **Custom Code** | ~2000 lines Python + TypeScript | ~200 lines (scripts only) |
| **Maintenance** | High (custom React + API) | Low (leverage official images) |

---

**Status**: Ready for Implementation  
**Estimated Timeline**: 2-3 weeks  
**Custom Code Required**: Minimal (~200 lines)  
**Risk Level**: Low (leverages official components)

---

**Next Action**: Review and approve this simplified approach, then proceed with Week 1 implementation!

