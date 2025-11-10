# GuideLLM UI Implementation Plan

## Executive Summary

This document outlines a comprehensive plan to integrate the **GuideLLM UI** into the Private AI Demo project's Stage 3 (Model Monitoring). GuideLLM is a Python-based platform for evaluating and optimizing LLM deployments through real-world inference workload simulation. The UI provides interactive visualization of benchmark results, performance metrics, and cost analysis.

**Key Benefits:**
- **Visual Performance Analysis**: Interactive charts and dashboards for latency, throughput, and resource utilization
- **Real-World Benchmarking**: Simulate diverse traffic patterns and load scenarios
- **Persistent Results**: Store and compare benchmarks over time
- **Integration with Existing Stack**: Seamless connection to vLLM InferenceServices, Grafana dashboards, and OTEL metrics
- **Developer Experience**: Self-service benchmarking for data scientists and ML engineers

---

## Current State Analysis

### Existing GuideLLM Implementation

The project already uses GuideLLM in two contexts:

1. **Tekton Pipeline Task** (`task-run-guidellm-v2.yaml`)
   - Automated benchmarking as part of model testing pipelines
   - Outputs JSON results to workspace volumes
   - Used for CI/CD validation of model performance

2. **Interactive Notebook** (`configmap-notebook-guidellm.yaml`)
   - Manual benchmarking through Jupyter notebooks
   - Educational and exploratory testing
   - Results viewed inline in notebook cells

### Current Architecture (Stage 3)

```
┌─────────────────┐
│  vLLM Models    │ (InferenceServices)
│  - Mistral 24B  │
│  - Mistral 24B  │
│    Quantized    │
└────────┬────────┘
         │
         ├──────────────────────────────────────┐
         │                                       │
         ▼                                       ▼
┌─────────────────┐                    ┌──────────────────┐
│ OTEL Collector  │ ◄──────────────────│  TrustyAI        │
│ - Metrics       │                    │  - LMEvalJobs    │
│ - Traces        │                    │  - Quality Eval  │
└────────┬────────┘                    └──────────────────┘
         │
         ├─────────────┬──────────────┐
         ▼             ▼              ▼
┌──────────────┐  ┌─────────┐  ┌───────────┐
│ Prometheus   │  │  Tempo  │  │  Grafana  │
│ (metrics)    │  │(traces) │  │(dashboards)│
└──────────────┘  └─────────┘  └───────────┘
```

### Gap Analysis

**What's Missing:**
- ✗ Persistent web-based UI for GuideLLM benchmarks
- ✗ Centralized storage for benchmark results
- ✗ Historical comparison and trend analysis
- ✗ Self-service access for non-technical users
- ✗ Integration with Grafana for unified observability

---

## Proposed Architecture

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Private AI Demo - Stage 3                     │
│                     Model Monitoring & Observability             │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  vLLM Models     │
│  (InferenceService)
└────────┬─────────┘
         │
         ├────────────────────────────────────────────────┐
         │                                                 │
         ▼                                                 ▼
┌─────────────────┐                             ┌──────────────────┐
│  GuideLLM UI    │ ◄───── Benchmark Results ───│  OTEL Collector  │
│  - Web Dashboard│                             │  - Metrics       │
│  - REST API     │                             │  - Traces        │
│  - Job Scheduler│                             └────────┬─────────┘
└────────┬────────┘                                      │
         │                                               │
         │ Store Results                                 │
         ▼                                               │
┌─────────────────┐                                     │
│  MinIO/S3       │                                     │
│  - Benchmark DB │                                     │
│  - Artifacts    │                                     │
└─────────────────┘                                     │
                                                         │
         ┌───────────────────────────────────────────────┤
         │                        │                      │
         ▼                        ▼                      ▼
┌──────────────┐         ┌──────────────┐      ┌──────────────┐
│  Grafana     │ ◄───────│ Prometheus   │      │    Tempo     │
│  - Dashboards│         │ (metrics)    │      │  (traces)    │
│  - GuideLLM  │         └──────────────┘      └──────────────┘
│    Panels    │
└──────────────┘
```

### Key Components

1. **GuideLLM UI Service**
   - Containerized web application
   - React/TypeScript frontend
   - FastAPI backend (Python)
   - Persistent storage for results (MinIO S3)
   - OpenShift Route for external access

2. **Integration Points**
   - **vLLM Models**: Direct HTTP connections to InferenceService routes
   - **OTEL Collector**: Export benchmark metrics in Prometheus format
   - **Grafana**: Custom dashboard panels showing GuideLLM results
   - **MinIO**: Object storage for benchmark artifacts and historical data

3. **Data Flow**
   - User initiates benchmark via UI
   - GuideLLM backend runs benchmark against vLLM endpoint
   - Results stored in MinIO (JSON artifacts)
   - Metrics exported to OTEL Collector (Prometheus endpoint)
   - Grafana visualizes metrics and links to detailed UI reports

---

## Implementation Plan

### Phase 1: Container Image and Deployment (Week 1)

#### 1.1 Create GuideLLM UI Container Image

**Objective**: Build a production-ready container image with GuideLLM CLI and web UI.

**Tasks:**
- [ ] Create `Containerfile` for GuideLLM UI
  - Base: `registry.access.redhat.com/ubi9/python-311`
  - Install GuideLLM: `pip install guidellm`
  - Install Node.js for UI build
  - Clone GuideLLM UI source (from vllm-project/guidellm repo)
  - Build frontend: `cd ui && npm install && npm run build`
  - Expose ports: `3000` (UI), `8000` (API)
- [ ] Create backend API wrapper (FastAPI)
  - REST endpoints for benchmark CRUD operations
  - Job queue for async benchmark execution
  - S3 client for result persistence
- [ ] Build and push image to internal registry
  ```bash
  podman build -t guidellm-ui:latest -f Containerfile .
  podman tag guidellm-ui:latest default-route-openshift-image-registry.apps.<cluster>/private-ai-demo/guidellm-ui:v1.0.0
  podman push default-route-openshift-image-registry.apps.<cluster>/private-ai-demo/guidellm-ui:v1.0.0
  ```

**Deliverables:**
- `stages/stage3-model-monitoring/guidellm-ui/Containerfile`
- `stages/stage3-model-monitoring/guidellm-ui/api/main.py` (FastAPI backend)
- `stages/stage3-model-monitoring/guidellm-ui/build.sh` (build script)

**Estimated Time**: 3 days

---

#### 1.2 Create Kubernetes Manifests

**Objective**: Define GitOps manifests for GuideLLM UI deployment.

**Tasks:**
- [ ] Create namespace-scoped deployment manifests
  - Deployment: `gitops/stage03-model-monitoring/guidellm-ui/deployment.yaml`
  - Service: `gitops/stage03-model-monitoring/guidellm-ui/service.yaml`
  - Route: `gitops/stage03-model-monitoring/guidellm-ui/route.yaml`
  - ConfigMap: `gitops/stage03-model-monitoring/guidellm-ui/configmap.yaml` (UI config)
  - Secret: `gitops/stage03-model-monitoring/guidellm-ui/secret.yaml` (MinIO credentials)
  - ServiceAccount: `gitops/stage03-model-monitoring/guidellm-ui/serviceaccount.yaml`
- [ ] Configure resource requests/limits
  ```yaml
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
  ```
- [ ] Add Istio sidecar injection label (for service mesh integration)
  ```yaml
  metadata:
    labels:
      sidecar.istio.io/inject: "true"
  ```
- [ ] Create PVC for local cache (optional)
  ```yaml
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: guidellm-cache
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 10Gi
  ```

**Deliverables:**
- `gitops/stage03-model-monitoring/guidellm-ui/` directory with all K8s manifests
- `gitops/stage03-model-monitoring/guidellm-ui/kustomization.yaml`

**Estimated Time**: 2 days

---

### Phase 2: Backend API and Storage Integration (Week 2)

#### 2.1 Implement FastAPI Backend

**Objective**: Create a REST API for managing GuideLLM benchmarks.

**API Endpoints:**
```
POST   /api/v1/benchmarks              # Create new benchmark job
GET    /api/v1/benchmarks              # List all benchmarks
GET    /api/v1/benchmarks/{id}         # Get benchmark details
GET    /api/v1/benchmarks/{id}/results # Get benchmark results (JSON)
GET    /api/v1/benchmarks/{id}/report  # Get HTML report
DELETE /api/v1/benchmarks/{id}         # Delete benchmark
GET    /api/v1/models                  # List available InferenceServices
GET    /api/v1/health                  # Health check
```

**Key Features:**
- Async job execution with Celery/RQ or asyncio
- Result caching and streaming
- Authentication (OpenShift OAuth proxy)
- CORS for Grafana integration

**Tasks:**
- [ ] Implement FastAPI application (`api/main.py`)
- [ ] Create Pydantic models for request/response validation
- [ ] Implement GuideLLM wrapper (`api/guidellm_runner.py`)
- [ ] Add S3 client for MinIO integration (`api/storage.py`)
- [ ] Create job queue for async execution
- [ ] Add logging and error handling
- [ ] Write unit tests

**Deliverables:**
- `stages/stage3-model-monitoring/guidellm-ui/api/` (Python application)
- OpenAPI schema generated automatically by FastAPI

**Estimated Time**: 4 days

---

#### 2.2 MinIO Integration for Result Storage

**Objective**: Store benchmark results in MinIO for long-term persistence and historical analysis.

**Storage Structure:**
```
minio://guidellm-results/
├── benchmarks/
│   ├── {benchmark-id}/
│   │   ├── metadata.json       # Benchmark configuration and metadata
│   │   ├── results.json        # Raw GuideLLM output
│   │   ├── report.html         # HTML report
│   │   └── metrics.prom        # Prometheus metrics snapshot
│   └── ...
└── index.json                  # Index of all benchmarks
```

**Tasks:**
- [ ] Create MinIO bucket: `guidellm-results`
- [ ] Implement S3 client wrapper using `boto3`
  ```python
  import boto3
  from botocore.client import Config
  
  s3_client = boto3.client(
      's3',
      endpoint_url=os.getenv('MINIO_ENDPOINT'),
      aws_access_key_id=os.getenv('MINIO_ACCESS_KEY'),
      aws_secret_access_key=os.getenv('MINIO_SECRET_KEY'),
      config=Config(signature_version='s3v4')
  )
  ```
- [ ] Implement upload/download functions
- [ ] Add result indexing for fast queries
- [ ] Create cleanup policy (retention: 90 days)

**Deliverables:**
- MinIO bucket created via `deploy.sh`
- S3 secret manifest: `gitops/stage03-model-monitoring/guidellm-ui/minio-secret.yaml`

**Estimated Time**: 2 days

---

### Phase 3: Frontend UI Development (Week 3)

#### 3.1 Build Web UI

**Objective**: Create a user-friendly web interface for GuideLLM benchmarks.

**Key Pages:**
1. **Dashboard** (`/`)
   - List of all benchmarks (table view)
   - Quick actions: New Benchmark, View Results
   - Status indicators (Running, Completed, Failed)

2. **New Benchmark** (`/benchmarks/new`)
   - Form for benchmark configuration:
     - Model selection (dropdown of InferenceServices)
     - Test parameters (prompt tokens, output tokens, duration)
     - Load profile (constant rate, sweep, poisson)
     - Advanced settings (concurrency, timeout)
   - Submit button to start benchmark

3. **Benchmark Results** (`/benchmarks/{id}`)
   - Interactive charts (Chart.js or Plotly):
     - Latency distribution (p50, p95, p99)
     - Throughput over time
     - Request success/failure rates
     - Token generation speed
   - Key metrics summary cards
   - Raw JSON export button
   - Share link

4. **Model Comparison** (`/compare`)
   - Side-by-side comparison of multiple benchmarks
   - Overlaid charts for visual comparison
   - Delta calculations (% improvement)

**Technology Stack:**
- **Framework**: React with TypeScript (already used in GuideLLM upstream)
- **Styling**: Tailwind CSS or Material-UI (PatternFly for Red Hat consistency)
- **Charts**: Recharts or Chart.js
- **State Management**: React Query for API calls

**Tasks:**
- [ ] Set up React app (use existing GuideLLM UI code as base)
- [ ] Customize branding for Private AI Demo
- [ ] Implement API client hooks
- [ ] Create responsive layout
- [ ] Add loading states and error handling
- [ ] Implement real-time benchmark status updates (WebSocket or polling)
- [ ] Add export functionality (CSV, JSON, PDF report)

**Deliverables:**
- `stages/stage3-model-monitoring/guidellm-ui/frontend/` (React app)
- Production build artifacts

**Estimated Time**: 5 days

---

### Phase 4: Observability Integration (Week 4)

#### 4.1 Export Metrics to OTEL Collector

**Objective**: Expose GuideLLM benchmark metrics in Prometheus format for ingestion by OTEL Collector.

**Metrics to Export:**
```
# Latency metrics
guidellm_request_duration_seconds{model="mistral-24b", quantile="0.5"}
guidellm_request_duration_seconds{model="mistral-24b", quantile="0.95"}
guidellm_request_duration_seconds{model="mistral-24b", quantile="0.99"}
guidellm_time_to_first_token_seconds{model="mistral-24b", quantile="0.95"}

# Throughput metrics
guidellm_requests_per_second{model="mistral-24b"}
guidellm_tokens_per_second{model="mistral-24b"}

# Success rate
guidellm_request_success_rate{model="mistral-24b"}
guidellm_request_errors_total{model="mistral-24b", error_type="timeout"}

# Resource utilization (from vLLM metrics)
guidellm_model_gpu_utilization{model="mistral-24b"}
guidellm_model_memory_usage_bytes{model="mistral-24b"}
```

**Tasks:**
- [ ] Add Prometheus client to FastAPI backend
  ```python
  from prometheus_client import Counter, Histogram, Gauge, generate_latest
  
  @app.get("/metrics")
  async def metrics():
      return Response(generate_latest(), media_type="text/plain")
  ```
- [ ] Create ServiceMonitor CR for GuideLLM UI
  ```yaml
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    name: guidellm-ui
    namespace: private-ai-demo
    labels:
      observability.rh-ai/demo: "true"  # Required for Target Allocator discovery
  spec:
    selector:
      matchLabels:
        app: guidellm-ui
    endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
  ```
- [ ] Update OTEL Collector's Target Allocator to discover ServiceMonitor
- [ ] Verify metrics appear in Prometheus/Grafana

**Deliverables:**
- `gitops/stage03-model-monitoring/guidellm-ui/servicemonitor.yaml`
- Prometheus metrics endpoint in GuideLLM UI

**Estimated Time**: 2 days

---

#### 4.2 Create Grafana Dashboard

**Objective**: Build a comprehensive Grafana dashboard for GuideLLM metrics visualization.

**Dashboard Panels:**
1. **Overview**
   - Total benchmarks run (today/week/month)
   - Active benchmarks
   - Average model latency (all models)
   - Total requests served

2. **Model Performance**
   - Latency heatmap (by model and time)
   - Throughput comparison (bar chart)
   - Token generation speed (time series)

3. **Reliability**
   - Request success rate (gauge)
   - Error rate (time series)
   - 95th percentile latency SLO tracker

4. **Resource Efficiency**
   - GPU utilization during benchmarks
   - Cost per 1K tokens (calculated metric)
   - Optimal concurrency level recommendations

5. **Historical Trends**
   - Model performance over time
   - Regression detection (alerts)

**Tasks:**
- [ ] Create GrafanaDashboard CR
  ```yaml
  apiVersion: grafana.integreatly.org/v1beta1
  kind: GrafanaDashboard
  metadata:
    name: guidellm-benchmarks
    namespace: private-ai-demo
  spec:
    instanceSelector:
      matchLabels:
        dashboards: grafana
    json: |
      {
        "title": "GuideLLM Benchmarks",
        "panels": [...]
      }
  ```
- [ ] Design dashboard layout in Grafana UI
- [ ] Export dashboard JSON
- [ ] Commit to GitOps: `gitops/stage03-model-monitoring/observability/grafana-dashboard-guidellm.yaml`
- [ ] Add dashboard link to GuideLLM UI (iframe or direct link)

**Deliverables:**
- `gitops/stage03-model-monitoring/observability/grafana-dashboard-guidellm.yaml`
- Screenshot of dashboard for documentation

**Estimated Time**: 3 days

---

### Phase 5: CI/CD and GitOps Integration (Week 5)

#### 5.1 Update Stage 3 Kustomize Structure

**Objective**: Integrate GuideLLM UI into Stage 3 GitOps deployment.

**Directory Structure:**
```
gitops/stage03-model-monitoring/
├── kustomization.yaml
├── observability/
│   ├── grafana-dashboard-guidellm.yaml  # NEW
│   └── ...
├── guidellm-ui/                          # NEW DIRECTORY
│   ├── kustomization.yaml
│   ├── namespace.yaml (optional, reuse private-ai-demo)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── route.yaml
│   ├── configmap.yaml
│   ├── minio-secret.yaml
│   ├── serviceaccount.yaml
│   └── servicemonitor.yaml
└── ...
```

**Tasks:**
- [ ] Add `guidellm-ui` to Stage 3 root kustomization.yaml
  ```yaml
  resources:
    - operators
    - trustyai
    - observability
    - guidellm-ui  # NEW
    - dashboard
    - notebooks
  ```
- [ ] Create `guidellm-ui/kustomization.yaml`
  ```yaml
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  
  namespace: private-ai-demo
  
  resources:
    - deployment.yaml
    - service.yaml
    - route.yaml
    - configmap.yaml
    - minio-secret.yaml
    - serviceaccount.yaml
    - servicemonitor.yaml
  
  labels:
    - includeSelectors: false
      pairs:
        app.kubernetes.io/part-of: guidellm-ui
        app.kubernetes.io/component: benchmarking
  ```
- [ ] Test deployment with ArgoCD
  ```bash
  oc apply -k gitops/stage03-model-monitoring/guidellm-ui
  ```

**Deliverables:**
- Updated Stage 3 kustomization structure
- All GuideLLM UI manifests in GitOps

**Estimated Time**: 2 days

---

#### 5.2 Update deploy.sh Script

**Objective**: Automate GuideLLM UI deployment as part of Stage 3 setup.

**Tasks:**
- [ ] Add MinIO bucket creation for `guidellm-results`
  ```bash
  echo "📦 Creating MinIO bucket for GuideLLM results..."
  mc mb "${MINIO_ALIAS}/guidellm-results" --ignore-existing
  ```
- [ ] Add GuideLLM UI image build/push step (optional, if building internally)
- [ ] Add health check for GuideLLM UI service
  ```bash
  wait_for_url "http://guidellm-ui.private-ai-demo.svc.cluster.local:8000/api/v1/health" "GuideLLM UI"
  ```
- [ ] Print access URL at end of deployment
  ```bash
  GUIDELLM_URL=$(oc get route guidellm-ui -n private-ai-demo -o jsonpath='{.spec.host}')
  echo "🎯 GuideLLM UI: https://${GUIDELLM_URL}"
  ```

**Deliverables:**
- Updated `stages/stage3-model-monitoring/deploy.sh`

**Estimated Time**: 1 day

---

### Phase 6: Documentation and Testing (Week 6)

#### 6.1 Create User Documentation

**Objective**: Provide comprehensive documentation for using GuideLLM UI.

**Documentation Sections:**
1. **Overview** (`docs/GUIDELLM-UI.md`)
   - What is GuideLLM UI?
   - When to use it?
   - Architecture diagram

2. **Getting Started**
   - Accessing the UI (URL, authentication)
   - Running your first benchmark
   - Understanding results

3. **User Guide**
   - Benchmark configuration options
   - Interpreting metrics and charts
   - Comparing models
   - Exporting results

4. **Integration Guide**
   - API documentation (OpenAPI spec)
   - Prometheus metrics reference
   - Grafana dashboard usage
   - Programmatic access (curl examples)

5. **Troubleshooting**
   - Common errors and solutions
   - Debugging tips
   - FAQ

**Tasks:**
- [ ] Write documentation in Markdown
- [ ] Create screenshots and diagrams
- [ ] Add examples and use cases
- [ ] Update main README with GuideLLM UI section

**Deliverables:**
- `docs/GUIDELLM-UI.md`
- `docs/assets/guidellm-ui-screenshots/`
- Updated `README.md`

**Estimated Time**: 3 days

---

#### 6.2 Testing and Validation

**Objective**: Ensure GuideLLM UI works correctly and integrates seamlessly with the stack.

**Test Scenarios:**
1. **Functional Tests**
   - [ ] Create benchmark via UI
   - [ ] View benchmark results
   - [ ] Export results (JSON, HTML)
   - [ ] Compare multiple benchmarks
   - [ ] API endpoint validation

2. **Integration Tests**
   - [ ] vLLM InferenceService connectivity
   - [ ] MinIO storage persistence
   - [ ] Metrics appear in Prometheus
   - [ ] Grafana dashboard displays data
   - [ ] OTEL Collector receives metrics

3. **Performance Tests**
   - [ ] UI response time < 1s
   - [ ] API response time < 200ms
   - [ ] Concurrent benchmark execution (up to 5 simultaneous)
   - [ ] Large result set handling (100+ benchmarks)

4. **Security Tests**
   - [ ] Authentication required
   - [ ] RBAC enforcement
   - [ ] Secret encryption
   - [ ] HTTPS only (no HTTP)

5. **Reliability Tests**
   - [ ] Graceful failure handling
   - [ ] Pod restart recovery
   - [ ] Network partition resilience

**Tasks:**
- [ ] Write automated tests (pytest for backend, Jest for frontend)
- [ ] Perform manual testing
- [ ] Load testing with K6 or Locust
- [ ] Security scan with Trivy
- [ ] Document test results

**Deliverables:**
- Test suite: `stages/stage3-model-monitoring/guidellm-ui/tests/`
- Test report: `docs/GUIDELLM-UI-TEST-REPORT.md`

**Estimated Time**: 4 days

---

## Deployment Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         OpenShift Cluster                        │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Namespace: private-ai-demo                                 │ │
│  │                                                              │ │
│  │  ┌──────────────────┐      ┌──────────────────┐           │ │
│  │  │  GuideLLM UI     │      │  vLLM Models     │           │ │
│  │  │  - Frontend      │──────▶  - Mistral 24B   │           │ │
│  │  │  - Backend API   │ HTTP  │  - Quantized    │           │ │
│  │  │  - Job Runner    │      └──────────────────┘           │ │
│  │  └────────┬─────────┘                                      │ │
│  │           │                                                 │ │
│  │           │ Metrics                                         │ │
│  │           ▼                                                 │ │
│  │  ┌──────────────────┐      ┌──────────────────┐           │ │
│  │  │  OTEL Collector  │─────▶│  Prometheus      │           │ │
│  │  │  - Target        │      │  (User Workload) │           │ │
│  │  │    Allocator     │      └──────────────────┘           │ │
│  │  └──────────────────┘               │                      │ │
│  │                                      │                      │ │
│  │                                      ▼                      │ │
│  │  ┌──────────────────┐      ┌──────────────────┐           │ │
│  │  │  MinIO (S3)      │      │  Grafana         │           │ │
│  │  │  - Benchmark     │      │  - Dashboards    │           │ │
│  │  │    Results       │      │  - GuideLLM UI   │           │ │
│  │  └──────────────────┘      └──────────────────┘           │ │
│  │                                                              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Routes (External Access)                                   │ │
│  │  - https://guidellm-ui-private-ai-demo.apps.<cluster>      │ │
│  │  - https://grafana-private-ai-demo.apps.<cluster>          │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| GuideLLM UI | 500m | 2000m | 1Gi | 4Gi | 10Gi (cache PVC) |
| MinIO Bucket | - | - | - | - | 50Gi (results) |

---

## Configuration Details

### Environment Variables (ConfigMap)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: guidellm-ui-config
  namespace: private-ai-demo
data:
  # API Configuration
  API_HOST: "0.0.0.0"
  API_PORT: "8000"
  API_WORKERS: "4"
  
  # MinIO Configuration
  MINIO_ENDPOINT: "http://minio.private-ai-demo.svc.cluster.local:9000"
  MINIO_BUCKET: "guidellm-results"
  MINIO_USE_SSL: "false"
  
  # GuideLLM Configuration
  GUIDELLM_DEFAULT_RATE: "10"
  GUIDELLM_DEFAULT_DURATION: "300"
  GUIDELLM_MAX_CONCURRENT_JOBS: "5"
  
  # Model Discovery
  NAMESPACE: "private-ai-demo"
  ISVC_LABEL_SELECTOR: "serving.kserve.io/inferenceservice"
  
  # Observability
  OTEL_COLLECTOR_ENDPOINT: "http://otel-collector-collector:4318"
  PROMETHEUS_PUSHGATEWAY: "http://prometheus-pushgateway:9091"
```

### Secret Configuration

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: guidellm-ui-secrets
  namespace: private-ai-demo
type: Opaque
stringData:
  MINIO_ACCESS_KEY: "${MINIO_ACCESS_KEY}"
  MINIO_SECRET_KEY: "${MINIO_SECRET_KEY}"
  # Optional: API key for authentication
  GUIDELLM_API_KEY: "changeme-generate-random"
```

---

## Security Considerations

1. **Authentication**
   - Use OpenShift OAuth Proxy for SSO integration
   - Service-to-service communication via service accounts
   - MinIO access via Kubernetes secrets

2. **Network Policies**
   - Restrict GuideLLM UI to access only:
     - vLLM InferenceService routes (HTTP)
     - MinIO service (S3 API)
     - OTEL Collector (metrics)
   - No direct internet access required

3. **RBAC**
   - GuideLLM UI ServiceAccount needs:
     - `GET` on KServe InferenceServices (discovery)
     - `GET` on Knative Services (URL resolution)
   - No cluster-admin or elevated privileges required

4. **Data Privacy**
   - Benchmark prompts may contain sensitive data
   - Store results in encrypted MinIO bucket
   - Add TTL policy for automatic cleanup (90 days)

---

## Success Criteria

### Phase 1-2 (Weeks 1-2)
- ✅ GuideLLM UI container image built and pushed
- ✅ Kubernetes manifests created and validated
- ✅ Backend API functional with health checks
- ✅ MinIO integration working (upload/download)

### Phase 3-4 (Weeks 3-4)
- ✅ Web UI accessible via OpenShift route
- ✅ Benchmarks can be created and viewed
- ✅ Metrics exported to Prometheus
- ✅ Grafana dashboard showing GuideLLM metrics

### Phase 5-6 (Weeks 5-6)
- ✅ GitOps deployment working with ArgoCD
- ✅ All tests passing (functional, integration, performance)
- ✅ Documentation complete
- ✅ Demo ready for stakeholders

---

## Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| GuideLLM UI upstream changes break compatibility | High | Medium | Pin specific version, fork if needed |
| Performance issues with concurrent benchmarks | Medium | High | Implement job queue with concurrency limits |
| MinIO storage exhaustion | Medium | Medium | Add TTL policy, alerting on storage usage |
| Complex UI build process | Low | Low | Use pre-built Docker image from upstream if available |
| Integration with Grafana requires custom plugins | Medium | Low | Use iframe embedding or direct links as fallback |

---

## Future Enhancements (Post-MVP)

1. **Advanced Features**
   - Scheduled benchmarks (cron-like)
   - A/B testing automation (compare two models automatically)
   - Cost calculator (tokens × GPU hours × price)
   - SLO tracking and alerting

2. **Extended Integrations**
   - Slack/Teams notifications on benchmark completion
   - Webhook support for CI/CD triggers
   - Export to Jupyter notebooks for analysis

3. **Multi-Tenancy**
   - User-scoped benchmarks
   - Team-level result sharing
   - Resource quotas per user

4. **AI-Powered Insights**
   - Automatic performance regression detection
   - Optimization recommendations (e.g., "increase concurrency for 20% throughput gain")
   - Anomaly detection in latency patterns

---

## References

- [GuideLLM Official Documentation](https://github.com/vllm-project/guidellm)
- [GuideLLM UI Source Code](https://github.com/vllm-project/guidellm/tree/main/ui)
- [Red Hat AI Observability Quickstart](https://github.com/rh-ai-quickstart/lls-observability)
- [OpenTelemetry Collector Documentation](https://opentelemetry.io/docs/collector/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)

---

## Appendix A: Example API Request

### Create Benchmark

```bash
curl -X POST https://guidellm-ui-private-ai-demo.apps.<cluster>/api/v1/benchmarks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Mistral 24B Performance Test",
    "model": "mistral-24b",
    "target_url": "https://mistral-24b-private-ai-demo.apps.<cluster>/v1",
    "test_config": {
      "prompt_tokens": 512,
      "output_tokens": 256,
      "rate_type": "constant",
      "rate": 10,
      "max_seconds": 300
    }
  }'
```

### Get Results

```bash
curl -X GET https://guidellm-ui-private-ai-demo.apps.<cluster>/api/v1/benchmarks/{id}/results \
  | jq '.benchmarks[0].request_throughput'
```

---

## Appendix B: Grafana Dashboard Query Examples

### Average Latency

```promql
rate(guidellm_request_duration_seconds_sum{model="mistral-24b"}[5m]) /
rate(guidellm_request_duration_seconds_count{model="mistral-24b"}[5m])
```

### 95th Percentile Latency

```promql
histogram_quantile(0.95, rate(guidellm_request_duration_seconds_bucket{model="mistral-24b"}[5m]))
```

### Throughput

```promql
guidellm_requests_per_second{model="mistral-24b"}
```

---

**Document Version**: 1.0  
**Last Updated**: 2025-11-10  
**Author**: AI Assistant  
**Status**: Proposal - Pending Approval

