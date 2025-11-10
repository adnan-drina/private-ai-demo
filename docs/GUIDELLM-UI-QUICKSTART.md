# GuideLLM UI - Quick Start Guide

## Overview

GuideLLM UI is a web-based platform for benchmarking and evaluating LLM inference performance. This guide helps you get started with the implementation.

## What is GuideLLM UI?

GuideLLM UI provides:
- **Visual Dashboard**: Interactive web interface for running benchmarks
- **Performance Metrics**: Latency, throughput, token generation speed
- **Historical Analysis**: Compare benchmarks over time
- **Integration**: Seamless connection with Grafana, Prometheus, and vLLM models

## Current State vs. Target State

### Current State
- ✅ GuideLLM CLI integrated in Tekton pipelines
- ✅ Jupyter notebook for interactive testing
- ✅ JSON output stored in workspace volumes
- ❌ No persistent web UI
- ❌ No centralized result storage
- ❌ No visual dashboards for non-technical users

### Target State (After Implementation)
- ✅ Web-based UI accessible via OpenShift route
- ✅ Persistent storage in MinIO (S3)
- ✅ Grafana integration for metrics visualization
- ✅ Self-service benchmarking for all users
- ✅ API for programmatic access

## Implementation Timeline

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| **Phase 1**: Container & Deployment | Week 1 | Docker image, K8s manifests |
| **Phase 2**: Backend API | Week 2 | FastAPI backend, MinIO integration |
| **Phase 3**: Frontend UI | Week 3 | React web application |
| **Phase 4**: Observability | Week 4 | Prometheus metrics, Grafana dashboard |
| **Phase 5**: GitOps | Week 5 | ArgoCD integration, deploy.sh updates |
| **Phase 6**: Testing & Docs | Week 6 | Test suite, user documentation |

**Total Estimated Time**: 6 weeks (30 working days)

## Quick Start Commands

### 1. Create Project Structure

```bash
cd /Users/adrina/Sandbox/private-ai-demo

# Create GuideLLM UI directories
mkdir -p stages/stage3-model-monitoring/guidellm-ui/{api,frontend,tests}
mkdir -p gitops/stage03-model-monitoring/guidellm-ui
mkdir -p docs/assets/guidellm-ui-screenshots
```

### 2. Build Container Image (Phase 1)

```bash
cd stages/stage3-model-monitoring/guidellm-ui

# Create Containerfile
cat > Containerfile <<'EOF'
FROM registry.access.redhat.com/ubi9/python-311:1-77

USER 0

# Install Node.js for UI build
RUN dnf install -y nodejs npm git && dnf clean all

# Install Python dependencies
RUN pip install --no-cache-dir \
    guidellm \
    fastapi \
    uvicorn[standard] \
    boto3 \
    pydantic \
    prometheus-client \
    python-multipart

# Clone GuideLLM UI (if using upstream UI)
WORKDIR /app
RUN git clone https://github.com/vllm-project/guidellm.git /tmp/guidellm && \
    cp -r /tmp/guidellm/ui /app/ui && \
    rm -rf /tmp/guidellm

# Build frontend
WORKDIR /app/ui
RUN npm install && npm run build

# Copy backend API
WORKDIR /app
COPY api/ /app/api/

# Create non-root user
RUN chown -R 1001:0 /app && chmod -R g=u /app

USER 1001

# Expose ports
EXPOSE 3000 8000

# Start both frontend and backend
CMD ["sh", "-c", "uvicorn api.main:app --host 0.0.0.0 --port 8000 & cd /app/ui && npm run serve -- --port 3000"]
EOF

# Build image
podman build -t guidellm-ui:v1.0.0 .
```

### 3. Deploy to OpenShift (Phase 5)

```bash
# Apply GitOps manifests
oc apply -k gitops/stage03-model-monitoring/guidellm-ui

# Check deployment status
oc get pods -n private-ai-demo -l app=guidellm-ui

# Get access URL
GUIDELLM_URL=$(oc get route guidellm-ui -n private-ai-demo -o jsonpath='{.spec.host}')
echo "GuideLLM UI: https://${GUIDELLM_URL}"
```

### 4. Run Your First Benchmark

```bash
# Via Web UI
open "https://${GUIDELLM_URL}"

# Via API
curl -X POST "https://${GUIDELLM_URL}/api/v1/benchmarks" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Quick Test",
    "model": "mistral-24b-quantized",
    "test_config": {
      "prompt_tokens": 256,
      "output_tokens": 128,
      "rate": 5,
      "max_seconds": 60
    }
  }'
```

## Key Files to Create

### Backend API (`stages/stage3-model-monitoring/guidellm-ui/api/main.py`)
```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import asyncio
import uuid

app = FastAPI(title="GuideLLM UI API", version="1.0.0")

class BenchmarkRequest(BaseModel):
    name: str
    model: str
    test_config: dict

@app.post("/api/v1/benchmarks")
async def create_benchmark(request: BenchmarkRequest):
    benchmark_id = str(uuid.uuid4())
    # TODO: Implement GuideLLM execution
    return {"id": benchmark_id, "status": "created"}

@app.get("/api/v1/benchmarks/{benchmark_id}")
async def get_benchmark(benchmark_id: str):
    # TODO: Retrieve from MinIO
    return {"id": benchmark_id, "status": "completed"}

@app.get("/api/v1/health")
async def health():
    return {"status": "healthy"}
```

### Kubernetes Deployment (`gitops/stage03-model-monitoring/guidellm-ui/deployment.yaml`)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guidellm-ui
  namespace: private-ai-demo
  labels:
    app: guidellm-ui
    app.kubernetes.io/name: guidellm-ui
    app.kubernetes.io/component: benchmarking
spec:
  replicas: 1
  selector:
    matchLabels:
      app: guidellm-ui
  template:
    metadata:
      labels:
        app: guidellm-ui
        sidecar.istio.io/inject: "true"
    spec:
      serviceAccountName: guidellm-ui
      containers:
      - name: guidellm-ui
        image: image-registry.openshift-image-registry.svc:5000/private-ai-demo/guidellm-ui:v1.0.0
        ports:
        - containerPort: 8000
          name: api
          protocol: TCP
        - containerPort: 3000
          name: ui
          protocol: TCP
        envFrom:
        - configMapRef:
            name: guidellm-ui-config
        - secretRef:
            name: guidellm-ui-secrets
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi
        livenessProbe:
          httpGet:
            path: /api/v1/health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/v1/health
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
```

### Service (`gitops/stage03-model-monitoring/guidellm-ui/service.yaml`)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: guidellm-ui
  namespace: private-ai-demo
  labels:
    app: guidellm-ui
spec:
  selector:
    app: guidellm-ui
  ports:
  - name: api
    port: 8000
    targetPort: 8000
  - name: ui
    port: 3000
    targetPort: 3000
  - name: metrics
    port: 9090
    targetPort: 9090
```

### Route (`gitops/stage03-model-monitoring/guidellm-ui/route.yaml`)
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: guidellm-ui
  namespace: private-ai-demo
  labels:
    app: guidellm-ui
spec:
  to:
    kind: Service
    name: guidellm-ui
  port:
    targetPort: ui
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

## Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│              GuideLLM UI Architecture                 │
└──────────────────────────────────────────────────────┘

User Browser
     │
     │ HTTPS
     ▼
┌─────────────────┐
│  OpenShift      │
│  Route          │
│  (TLS)          │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  GuideLLM UI Pod                    │
│  ┌──────────────┐  ┌─────────────┐ │
│  │  Frontend    │  │  Backend    │ │
│  │  (React)     │  │  (FastAPI)  │ │
│  │  Port 3000   │  │  Port 8000  │ │
│  └──────────────┘  └─────┬───────┘ │
│                           │         │
└───────────────────────────┼─────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
┌────────────────┐  ┌──────────────┐  ┌──────────────┐
│  vLLM Models   │  │  MinIO (S3)  │  │  OTEL        │
│  (Inference)   │  │  (Results)   │  │  Collector   │
└────────────────┘  └──────────────┘  └──────┬───────┘
                                              │
                                              ▼
                                      ┌──────────────┐
                                      │  Grafana     │
                                      │  (Dashboards)│
                                      └──────────────┘
```

## Integration Points

### 1. vLLM Models
- **Connection**: HTTP requests to InferenceService routes
- **Protocol**: OpenAI-compatible API (`/v1/completions`, `/v1/chat/completions`)
- **Discovery**: Query Knative Services via Kubernetes API

### 2. MinIO Storage
- **Connection**: S3 API (boto3 client)
- **Bucket**: `guidellm-results`
- **Data**: Benchmark JSON, HTML reports, metadata
- **Credentials**: Kubernetes Secret

### 3. OTEL Collector
- **Connection**: Prometheus metrics endpoint (`/metrics`)
- **Discovery**: ServiceMonitor CR with label `observability.rh-ai/demo=true`
- **Metrics**: Latency, throughput, success rate

### 4. Grafana
- **Integration**: Custom dashboard panels
- **Data Source**: Prometheus (OTEL Collector endpoint)
- **Queries**: PromQL for GuideLLM metrics

## Next Steps

1. **Review Implementation Plan**
   - Read full plan: `GUIDELLM-UI-IMPLEMENTATION-PLAN.md`
   - Approve scope and timeline

2. **Phase 1: Start Container Development**
   - Create directory structure
   - Write Containerfile
   - Develop FastAPI backend skeleton

3. **Phase 2: Backend Implementation**
   - Implement GuideLLM runner
   - Add MinIO integration
   - Create API endpoints

4. **Phase 3: Frontend Development**
   - Clone/customize GuideLLM UI
   - Implement API client
   - Build and test locally

5. **Phase 4: Deploy to OpenShift**
   - Create K8s manifests
   - Test deployment
   - Verify integrations

6. **Phase 5: Observability**
   - Add Prometheus metrics
   - Create Grafana dashboard
   - Test end-to-end flow

7. **Phase 6: Documentation**
   - Write user guide
   - Create screenshots
   - Record demo video

## Resources

- **Implementation Plan**: `GUIDELLM-UI-IMPLEMENTATION-PLAN.md`
- **GuideLLM Docs**: https://github.com/vllm-project/guidellm
- **Current GuideLLM Task**: `gitops/stage01-model-serving/serving/pipelines/active/01-tasks/task-run-guidellm-v2.yaml`
- **Stage 3 Observability**: `gitops/stage03-model-monitoring/observability/`

## FAQ

### Q: Why not just use the existing Tekton task?
**A**: The Tekton task is great for CI/CD but doesn't provide:
- Visual UI for non-developers
- Real-time result viewing
- Historical comparison
- Self-service access

### Q: Can we use the upstream GuideLLM UI directly?
**A**: Yes! The upstream UI can be used as a starting point. We'll need to:
- Containerize it for OpenShift
- Add backend API for persistence
- Integrate with MinIO and OTEL

### Q: What if we don't have resources for a 6-week project?
**A**: We can implement a **Minimal Viable Product (MVP)** in 2-3 weeks:
- Week 1: Container + basic API + MinIO integration
- Week 2: Deploy to OpenShift + Grafana dashboard
- Week 3: Basic UI (can be as simple as a form + results table)

### Q: How does this relate to TrustyAI?
**A**: Complementary tools:
- **TrustyAI**: Model quality evaluation (accuracy, bias, drift)
- **GuideLLM UI**: Performance evaluation (latency, throughput, resource usage)

Both feed into the same Grafana dashboards for holistic model monitoring.

---

**Ready to start?** Let's begin with Phase 1! 🚀

