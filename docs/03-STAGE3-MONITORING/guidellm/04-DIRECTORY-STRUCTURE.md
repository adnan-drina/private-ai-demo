# GuideLLM UI - Proposed Directory Structure

This document outlines the complete directory structure for the GuideLLM UI implementation.

## Complete Directory Tree

```
private-ai-demo/
│
├── stages/stage3-model-monitoring/
│   ├── guidellm-ui/                                    # NEW - GuideLLM UI source code
│   │   ├── Containerfile                               # Container image definition
│   │   ├── build.sh                                    # Build and push script
│   │   ├── README.md                                   # Development guide
│   │   │
│   │   ├── api/                                        # Backend API (FastAPI)
│   │   │   ├── __init__.py
│   │   │   ├── main.py                                 # FastAPI application entry point
│   │   │   ├── config.py                               # Configuration management
│   │   │   ├── models.py                               # Pydantic models
│   │   │   ├── routers/
│   │   │   │   ├── __init__.py
│   │   │   │   ├── benchmarks.py                       # Benchmark CRUD endpoints
│   │   │   │   ├── models.py                           # Model discovery endpoints
│   │   │   │   └── health.py                           # Health check endpoints
│   │   │   ├── services/
│   │   │   │   ├── __init__.py
│   │   │   │   ├── guidellm_runner.py                  # GuideLLM execution wrapper
│   │   │   │   ├── storage.py                          # MinIO S3 client
│   │   │   │   ├── metrics.py                          # Prometheus metrics exporter
│   │   │   │   └── discovery.py                        # K8s InferenceService discovery
│   │   │   └── utils/
│   │   │       ├── __init__.py
│   │   │       ├── logger.py                           # Logging configuration
│   │   │       └── k8s_client.py                       # Kubernetes API client
│   │   │
│   │   ├── frontend/                                   # Frontend UI (React)
│   │   │   ├── package.json
│   │   │   ├── tsconfig.json
│   │   │   ├── vite.config.ts                         # Vite build config
│   │   │   ├── public/
│   │   │   │   ├── favicon.ico
│   │   │   │   └── index.html
│   │   │   └── src/
│   │   │       ├── App.tsx                            # Main app component
│   │   │       ├── main.tsx                           # Entry point
│   │   │       ├── api/
│   │   │       │   └── client.ts                      # API client (axios/fetch)
│   │   │       ├── components/
│   │   │       │   ├── BenchmarkList.tsx              # List of benchmarks
│   │   │       │   ├── BenchmarkForm.tsx              # Create benchmark form
│   │   │       │   ├── BenchmarkResults.tsx           # Results display
│   │   │       │   ├── MetricsChart.tsx               # Chart components
│   │   │       │   └── ModelSelector.tsx              # Model dropdown
│   │   │       ├── pages/
│   │   │       │   ├── Dashboard.tsx                  # Main dashboard
│   │   │       │   ├── BenchmarkDetail.tsx            # Detail view
│   │   │       │   └── Compare.tsx                    # Comparison view
│   │   │       ├── hooks/
│   │   │       │   └── useBenchmarks.ts               # React Query hooks
│   │   │       └── types/
│   │   │           └── index.ts                       # TypeScript types
│   │   │
│   │   └── tests/                                      # Test suite
│   │       ├── __init__.py
│   │       ├── conftest.py                            # Pytest fixtures
│   │       ├── test_api.py                            # API unit tests
│   │       ├── test_guidellm_runner.py                # Runner tests
│   │       ├── test_storage.py                        # Storage tests
│   │       └── integration/
│   │           └── test_end_to_end.py                 # E2E tests
│   │
│   ├── deploy.sh                                       # UPDATED - Add GuideLLM UI deployment
│   └── README.md
│
├── gitops/stage03-model-monitoring/
│   ├── kustomization.yaml                              # UPDATED - Add guidellm-ui resource
│   │
│   ├── guidellm-ui/                                    # NEW - K8s manifests
│   │   ├── kustomization.yaml                          # Kustomize configuration
│   │   ├── namespace.yaml                              # Namespace (if separate)
│   │   ├── serviceaccount.yaml                         # Service account
│   │   ├── role.yaml                                   # RBAC role
│   │   ├── rolebinding.yaml                            # RBAC role binding
│   │   ├── configmap.yaml                              # Environment configuration
│   │   ├── minio-secret.yaml                           # MinIO credentials (sealed)
│   │   ├── deployment.yaml                             # Deployment definition
│   │   ├── service.yaml                                # Service definition
│   │   ├── route.yaml                                  # OpenShift route
│   │   ├── servicemonitor.yaml                         # Prometheus metrics scraping
│   │   ├── pvc.yaml                                    # Persistent volume claim (cache)
│   │   └── README.md                                   # Deployment documentation
│   │
│   └── observability/
│       ├── kustomization.yaml                          # UPDATED - Add GuideLLM dashboard
│       ├── grafana-dashboard-guidellm.yaml             # NEW - GuideLLM Grafana dashboard
│       └── ...
│
├── docs/
│   ├── GUIDELLM-UI.md                                  # NEW - User documentation
│   ├── GUIDELLM-UI-API.md                              # NEW - API reference
│   ├── GUIDELLM-UI-QUICKSTART.md                       # CREATED
│   └── assets/
│       └── guidellm-ui-screenshots/                    # NEW - UI screenshots
│           ├── dashboard.png
│           ├── benchmark-form.png
│           ├── results-chart.png
│           └── grafana-integration.png
│
├── GUIDELLM-UI-IMPLEMENTATION-PLAN.md                  # CREATED
└── GUIDELLM-UI-DIRECTORY-STRUCTURE.md                  # THIS FILE
```

## File Descriptions

### Source Code Files (`stages/stage3-model-monitoring/guidellm-ui/`)

#### Container and Build
- **`Containerfile`**: Multi-stage build for backend API + frontend UI
- **`build.sh`**: Script to build and push container image to OpenShift registry
- **`README.md`**: Development setup, local testing, contribution guide

#### Backend API (`api/`)
- **`main.py`**: FastAPI application with CORS, middleware, routers
- **`config.py`**: Environment variable loading, validation (pydantic-settings)
- **`models.py`**: Pydantic models for API request/response validation

##### Routers
- **`benchmarks.py`**: CRUD operations for benchmarks
  - `POST /api/v1/benchmarks` - Create benchmark
  - `GET /api/v1/benchmarks` - List benchmarks
  - `GET /api/v1/benchmarks/{id}` - Get benchmark detail
  - `GET /api/v1/benchmarks/{id}/results` - Get results JSON
  - `GET /api/v1/benchmarks/{id}/report` - Get HTML report
  - `DELETE /api/v1/benchmarks/{id}` - Delete benchmark
- **`models.py`**: Model discovery
  - `GET /api/v1/models` - List InferenceServices
- **`health.py`**: Health checks
  - `GET /api/v1/health` - Application health
  - `GET /api/v1/ready` - Readiness probe

##### Services
- **`guidellm_runner.py`**: Execute GuideLLM CLI, capture output, parse results
- **`storage.py`**: MinIO S3 operations (upload, download, list, delete)
- **`metrics.py`**: Prometheus metrics (Counter, Histogram, Gauge)
- **`discovery.py`**: Kubernetes client to discover InferenceServices

##### Utilities
- **`logger.py`**: Structured logging configuration (JSON format)
- **`k8s_client.py`**: Kubernetes API client wrapper

#### Frontend UI (`frontend/`)
- **`package.json`**: Dependencies (React, TypeScript, Vite, Recharts, React Query)
- **`tsconfig.json`**: TypeScript compiler configuration
- **`vite.config.ts`**: Vite bundler configuration

##### Source Code
- **`App.tsx`**: Main application with routing (React Router)
- **`main.tsx`**: Entry point, mounts React app
- **`api/client.ts`**: Axios client with interceptors, error handling
- **`components/`**: Reusable UI components
  - `BenchmarkList.tsx`: Table/grid of benchmarks with status
  - `BenchmarkForm.tsx`: Form to create new benchmark
  - `BenchmarkResults.tsx`: Charts and metrics display
  - `MetricsChart.tsx`: Recharts wrapper for latency/throughput
  - `ModelSelector.tsx`: Dropdown populated from API
- **`pages/`**: Full page components
  - `Dashboard.tsx`: Main landing page
  - `BenchmarkDetail.tsx`: Single benchmark view
  - `Compare.tsx`: Side-by-side comparison
- **`hooks/useBenchmarks.ts`**: React Query hooks for data fetching
- **`types/index.ts`**: TypeScript interfaces and types

#### Tests (`tests/`)
- **`conftest.py`**: Pytest fixtures (mock S3, mock K8s API)
- **`test_api.py`**: Unit tests for API endpoints (FastAPI TestClient)
- **`test_guidellm_runner.py`**: Unit tests for GuideLLM execution
- **`test_storage.py`**: Unit tests for MinIO operations
- **`integration/test_end_to_end.py`**: E2E tests (create benchmark → view results)

---

### GitOps Manifests (`gitops/stage03-model-monitoring/guidellm-ui/`)

#### Kubernetes Resources
- **`kustomization.yaml`**: Lists all resources, adds labels, namespace
- **`namespace.yaml`**: Optional if deploying to separate namespace
- **`serviceaccount.yaml`**: Service account for GuideLLM UI pods
- **`role.yaml`**: RBAC role (get InferenceServices, get Services)
- **`rolebinding.yaml`**: Bind role to service account
- **`configmap.yaml`**: Non-sensitive configuration (API ports, MinIO endpoint)
- **`minio-secret.yaml`**: MinIO credentials (use SealedSecret in production)
- **`deployment.yaml`**: Deployment spec with resource limits, probes, env vars
- **`service.yaml`**: ClusterIP service exposing API (8000) and UI (3000)
- **`route.yaml`**: OpenShift route with TLS edge termination
- **`servicemonitor.yaml`**: Prometheus Operator CR for metrics scraping
- **`pvc.yaml`**: Optional persistent volume for caching benchmark data

---

### Documentation (`docs/`)

- **`GUIDELLM-UI.md`**: Comprehensive user documentation
  - Getting Started
  - Running Benchmarks
  - Interpreting Results
  - Comparing Models
  - Troubleshooting
  
- **`GUIDELLM-UI-API.md`**: API reference
  - OpenAPI/Swagger spec
  - Example requests (curl, Python)
  - Authentication
  - Rate limits

- **`assets/guidellm-ui-screenshots/`**: Screenshots for documentation
  - `dashboard.png`: Main dashboard view
  - `benchmark-form.png`: Create benchmark form
  - `results-chart.png`: Results visualization
  - `grafana-integration.png`: Grafana dashboard

---

## Integration with Existing Structure

### Updated Files

1. **`stages/stage3-model-monitoring/deploy.sh`**
   ```bash
   # Add MinIO bucket creation
   echo "📦 Creating MinIO bucket for GuideLLM results..."
   mc mb "${MINIO_ALIAS}/guidellm-results" --ignore-existing
   
   # Add GuideLLM UI health check
   wait_for_url "http://guidellm-ui.private-ai-demo.svc.cluster.local:8000/api/v1/health" "GuideLLM UI"
   
   # Print access URL
   GUIDELLM_URL=$(oc get route guidellm-ui -n private-ai-demo -o jsonpath='{.spec.host}')
   echo "🎯 GuideLLM UI: https://${GUIDELLM_URL}"
   ```

2. **`gitops/stage03-model-monitoring/kustomization.yaml`**
   ```yaml
   resources:
     - operators
     - trustyai
     - observability
     - guidellm-ui        # NEW
     - dashboard
     - notebooks
   ```

3. **`gitops/stage03-model-monitoring/observability/kustomization.yaml`**
   ```yaml
   resources:
     # ... existing resources ...
     - grafana-dashboard-guidellm.yaml    # NEW
   ```

---

## File Size Estimates

| Directory | File Count | Approx Size |
|-----------|------------|-------------|
| `api/` | 15 files | 5 KB - 25 KB per file |
| `frontend/src/` | 20 files | 5 KB - 15 KB per file |
| `tests/` | 6 files | 10 KB - 30 KB per file |
| `gitops/guidellm-ui/` | 12 files | 2 KB - 10 KB per file |
| `docs/` | 3 files | 10 KB - 50 KB per file |
| **Total** | **~56 files** | **~1.5 MB** (excluding node_modules) |

---

## Dependencies

### Python (Backend)
```txt
# requirements.txt
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
guidellm>=0.3.0
boto3>=1.28.0
pydantic>=2.4.0
pydantic-settings>=2.0.0
prometheus-client>=0.18.0
python-multipart>=0.0.6
kubernetes>=28.1.0
```

### Node.js (Frontend)
```json
// package.json
{
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.16.0",
    "@tanstack/react-query": "^5.0.0",
    "axios": "^1.5.0",
    "recharts": "^2.8.0",
    "date-fns": "^2.30.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.1.0",
    "typescript": "^5.2.0",
    "vite": "^4.5.0"
  }
}
```

---

## Build Artifacts

### Container Image Layers
```
registry.example.com/private-ai-demo/guidellm-ui:v1.0.0
├── Layer 1: UBI9 Python 3.11 base (200 MB)
├── Layer 2: Node.js and npm (150 MB)
├── Layer 3: Python dependencies (300 MB)
├── Layer 4: Node.js dependencies (200 MB)
├── Layer 5: Frontend build artifacts (10 MB)
├── Layer 6: Backend API code (5 MB)
└── Total: ~865 MB (compressed: ~350 MB)
```

### MinIO Storage Structure
```
guidellm-results/
├── index.json                          # Index of all benchmarks (1 KB)
├── benchmarks/
│   ├── uuid-1/
│   │   ├── metadata.json               # Config + timestamp (2 KB)
│   │   ├── results.json                # GuideLLM output (50-200 KB)
│   │   ├── report.html                 # Visual report (100-500 KB)
│   │   └── metrics.prom                # Prometheus snapshot (5 KB)
│   ├── uuid-2/
│   └── ...
└── (Estimated: 1 MB per benchmark × 100 benchmarks = 100 MB)
```

---

## Next Steps

1. **Review Structure** ✅ (You are here)
2. **Create Directories**
   ```bash
   cd /Users/adrina/Sandbox/private-ai-demo
   mkdir -p stages/stage3-model-monitoring/guidellm-ui/{api/routers,api/services,api/utils,frontend/src/{api,components,pages,hooks,types},tests/integration}
   mkdir -p gitops/stage03-model-monitoring/guidellm-ui
   mkdir -p docs/assets/guidellm-ui-screenshots
   ```
3. **Start Implementation** (Follow Quick Start Guide)

---

**Ready to implement?** Let's proceed with Phase 1! 🚀

