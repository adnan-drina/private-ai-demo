# RHOAI 3.0 Upgrade Analysis & Migration Plan

**Document Created**: November 16, 2025  
**Current Version**: RHOAI 2.25 (stable-2.25 channel)  
**Target Version**: RHOAI 3.0  
**Project**: private-ai-demo  
**Status**: ⚠️ **CRITICAL: Direct upgrade NOT supported** - Requires fresh installation

---

## 📋 **Executive Summary**

| Aspect | Status | Impact |
|--------|--------|--------|
| **Upgrade Path** | ❌ **NOT SUPPORTED** | Requires fresh installation |
| **RHOAI 2.25 Support** | ✅ **EUS Release** | Extended support continues |
| **Migration Complexity** | 🔴 **HIGH** | 5 stages, custom operators, integrations |
| **Risk Level** | 🔴 **HIGH** | Breaking changes, data migration required |
| **Recommended Action** | ⏸️ **WAIT** | Await stable 3.x release (post-3.0) |

### 🚨 **Critical Finding**

According to [Red Hat's official documentation](https://access.redhat.com/articles/7133758), **upgrades from RHOAI 2.x to 3.0 are not supported** due to:

> "significant technological and component changes introduced in the 3.0 release... Red Hat is focusing on ensuring a smooth migration path from stable 2.x releases, such as 2.25, to the first stable 3.x release."

**Translation**: RHOAI 3.0 is a **fast release** for early adopters. Production environments should wait for the **first stable 3.x release** (e.g., 3.1 or 3.5).

---

## 📊 **Current Environment Analysis**

### **RHOAI 2.25 Stack**

```yaml
Operator: rhods-operator
Channel: stable-2.25
Source: redhat-operators
Install Plan: Automatic
```

### **DataScienceCluster Components**

| Component | Status | Stage | Notes |
|-----------|--------|-------|-------|
| **Dashboard** | ✅ Managed | 0 | Core UI |
| **Data Science Pipelines** | ✅ Managed | 2 | KFP v2 |
| **KServe** | ✅ Managed | 1 | vLLM serving |
| **Model Registry** | ✅ Managed | 1 | MLflow backend |
| **Model Mesh Serving** | ✅ Managed | 1 | Legacy serving |
| **TrustyAI** | ✅ Managed | 2,3 | Guardrails + eval |
| **Training Operator** | ✅ Managed | - | Kubeflow training |
| **Workbenches** | ✅ Managed | - | Jupyter notebooks |
| **Llama Stack Operator** | ✅ Managed | 2 | RAG + agents |
| **CodeFlare** | ❌ Removed | - | Not used |
| **Ray** | ❌ Removed | - | Not used |
| **Feast Operator** | ⚪ Default | - | Feature Store (inactive) |
| **Kueue** | ⚪ Default | - | Job queuing (default config) |

### **Additional Operators (External)**

| Operator | Version | Purpose | Stage |
|----------|---------|---------|-------|
| **Node Feature Discovery** | stable | GPU detection | 0 |
| **NVIDIA GPU Operator** | v24.9 | GPU drivers | 0 |
| **OpenShift Pipelines** | latest | Tekton CI/CD | 1 |
| **OpenShift Serverless** | stable | Knative for KServe | 1 |
| **OpenShift Service Mesh** | stable | Istio for KServe | 1 |
| **Authorino** | stable | API auth | 1 |
| **Grafana Operator** | v5 | Observability | 3 |
| **OpenTelemetry Operator** | stable | Traces/metrics | 3 |
| **Tempo Operator** | stable | Distributed tracing | 3 |
| **Docling Operator** | v1alpha1 | PDF processing | 2 |

### **Custom Integrations**

1. **LlamaStack Distribution (v1alpha1)**
   - Custom image: `llama-stack-custom:latest` (with TrustyAI provider)
   - Version: v0.3.0rc3 (Red Hat image)
   - APIs: Inference, Agents, Safety, Telemetry, Tool Runtime, Vector I/O

2. **TrustyAI Guardrails**
   - Custom shields: `regex_guardrail`, `toxicity_guardrail`
   - Provider: `trustyai_fms` (custom module)
   - ⚠️ Currently disabled due to v0.3.0rc3 bugs

3. **Docling Operator**
   - CR: `DoclingServe` (docling.github.io/v1alpha1)
   - Memory: 16Gi (upgraded for large PDFs)
   - API: `/v1/convert/file/async`

4. **Milvus Vector Database**
   - Deployment: standalone (direct YAML)
   - Storage: PVC (10Gi)
   - Integration: LlamaStack vector_io provider

5. **Custom Playground UI**
   - Streamlit applications: Chat, RAG, Tools
   - ConfigMaps: `llama-stack-playground-*`
   - Features: Guardrails toggle, collection selector

---

## 🆕 **RHOAI 3.0 New Features** ([source](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/release_notes/release_notes))

### **🎯 Directly Relevant to Our Project**

1. **Generative AI Playground (GA)**
   - **Description**: Interactive UI for testing models, prompts, and RAG workflows
   - **Impact**: 🟢 **BENEFICIAL** - Complements/replaces our custom Playground
   - **Migration**: Evaluate if RHOAI 3.0 Playground can replace `playground-chat.py`, `playground-rag.py`, `playground-tools.py`

2. **TrustyAI–Llama Stack Integration (Enhanced)**
   - **Description**: Built-in detection and evaluation workflows
   - **Impact**: 🟡 **COMPATIBILITY** - May resolve our v0.3.0rc3 `trustyai_fms` provider bugs
   - **Migration**: Test if native integration works better than our custom provider

3. **Air-Gapped Llama Stack Deployments**
   - **Description**: Support for disconnected environments
   - **Impact**: 🔵 **OPTIONAL** - Not currently needed (connected env)

4. **Distributed Inference with llm-d (Tech Preview)**
   - **Description**: Multi-model serving, intelligent scheduling, disaggregated serving
   - **Impact**: 🟢 **OPPORTUNITY** - Could replace vLLM for better GPU utilization
   - **Migration**: Evaluate llm-d vs. vLLM for `mistral-24b-quantized` and `mistral-24b-full`

5. **Feature Store UI & RBAC**
   - **Description**: Web UI for Feature Store objects, improved governance
   - **Impact**: 🟡 **FUTURE** - Not used in current project, but Stage 4 candidate

6. **AI Available Assets Page**
   - **Description**: UI for viewing deployed AI resources
   - **Impact**: 🟢 **BENEFICIAL** - Improves visibility of Stage 1-4 resources

---

### **🔧 Infrastructure & Platform**

7. **IBM Spyre AI Accelerator Support (Tech Preview)**
   - **Impact**: 🔵 **OPTIONAL** - AWS GPU (NVIDIA L4) in use, not IBM Spyre

8. **Model Catalog Enhancements**
   - **Impact**: 🟢 **BENEFICIAL** - Easier model discovery and deployment

9. **Enhanced Model Serving**
   - **Impact**: 🟢 **BENEFICIAL** - Potential performance improvements for KServe/vLLM

---

## 🚨 **Breaking Changes & Risks**

### **1. Operator API Changes**

| Component | RHOAI 2.25 API | RHOAI 3.0 API | Impact |
|-----------|----------------|---------------|--------|
| **LlamaStackDistribution** | `llamastack.io/v1alpha1` | 🔴 **UNKNOWN** | CRD schema may change |
| **DoclingServe** | `docling.github.io/v1alpha1` | 🔴 **UNKNOWN** | 3rd-party operator, may lag |
| **GuardrailsOrchestrator** | `trustyai.opendatahub.io/v1alpha1` | 🟡 **LIKELY COMPATIBLE** | TrustyAI integration improved |
| **DataScienceCluster** | `datasciencecluster.opendatahub.io/v1` | 🟡 **LIKELY COMPATIBLE** | Minor schema changes expected |

**Risk**: Custom CRs (`LlamaStackDistribution`, `DoclingServe`, `GuardrailsOrchestrator`) may require YAML updates.

---

### **2. LlamaStack API Compatibility**

**Current Issue** (already present in 2.25):
- LlamaStack v0.3.0rc3 (Red Hat image) has broken `/v1/vector-io/insert` API
- Collections not auto-registered from ConfigMap
- `trustyai_fms` provider fails to load

**RHOAI 3.0 Expectations**:
- 🟢 **Likely Fixed**: Native TrustyAI integration may resolve provider bugs
- 🔴 **Unknown**: Vector I/O API compatibility (may still be broken or changed)
- 🟡 **Testing Required**: Full RAG pipeline validation needed

**Migration Action**: Re-test RAG pipeline with RHOAI 3.0's LlamaStack image.

---

### **3. Custom Container Images**

| Image | Source | Migration Risk |
|-------|--------|----------------|
| `llama-stack-custom:latest` | Custom build (TrustyAI provider) | 🔴 **HIGH** - May be incompatible with 3.0 |
| `vllm/vllm-openai:v0.6.4.post1` | Public | 🟢 **LOW** - Standard vLLM image |
| `docling-serve` | Docling Project | 🟡 **MEDIUM** - 3rd-party operator |
| `minio/minio:RELEASE.2024-10-13T13-34-11Z` | Public | 🟢 **LOW** - Standard MinIO |
| `milvusdb/milvus:v2.4.15` | Public | 🟢 **LOW** - Standard Milvus |

**Action**: Rebuild `llama-stack-custom` image against RHOAI 3.0 base image.

---

### **4. Data Migration Requirements**

| Data Store | Size | Migration Method | Risk |
|------------|------|------------------|------|
| **Milvus Vector DB** | ~2GB (embeddings) | 🔴 **MANUAL** - Export/import required | HIGH |
| **MinIO (model weights)** | ~50GB | 🟢 **COPY** - Direct bucket copy | LOW |
| **Model Registry (MLflow)** | ~5GB | 🟡 **BACKUP/RESTORE** - DB dump | MEDIUM |
| **LlamaStack PVC** | ~10GB | 🔴 **REBUILD** - Collections not portable | HIGH |
| **KFP Pipelines (Argo)** | ~1GB | 🟡 **EXPORT** - Pipeline YAMLs | MEDIUM |

**Critical**: Milvus collections and LlamaStack SQLite databases are **not portable** between clusters. RAG data must be re-ingested.

---

### **5. GitOps Manifest Changes**

**Estimated Files Requiring Updates**: 50-70 files across 5 stages

| Stage | Components | Manifest Changes | Testing Effort |
|-------|------------|------------------|----------------|
| **Stage 0** | Operators, DSC | 🟡 **MEDIUM** (5-10 files) | 2-4 hours |
| **Stage 1** | Model Serving | 🟢 **LOW** (2-5 files) | 1-2 hours |
| **Stage 2** | LlamaStack, RAG | 🔴 **HIGH** (15-20 files) | 8-12 hours |
| **Stage 3** | Monitoring | 🟢 **LOW** (3-5 files) | 1-2 hours |
| **Stage 4** | MCP, Agentic | 🟡 **MEDIUM** (5-10 files) | 4-6 hours |

**Total Estimated Effort**: **16-26 hours** (manifest updates + testing)

---

## 📋 **Migration Strategy Options**

### **Option A: Wait for Stable 3.x (RECOMMENDED)**

**Timeline**: Q1-Q2 2026 (estimated)  
**Effort**: Same as Option B, but lower risk  
**Risk**: 🟢 **LOW**

**Rationale**:
1. RHOAI 2.25 is an **EUS release** with extended support
2. RHOAI 3.0 is a **fast release** for early adopters (not production-ready)
3. Red Hat explicitly recommends waiting for **first stable 3.x** ([source](https://access.redhat.com/articles/7133758))
4. Avoids being a guinea pig for 3.0 bugs

**Actions** (Now):
1. ✅ Continue development on RHOAI 2.25
2. ✅ Complete Stage 4 (MCP, Agentic AI)
3. ✅ Report LlamaStack v0.3.0rc3 bugs to Red Hat
4. ✅ Monitor RHOAI 3.x release notes

**Actions** (When Stable 3.x Released):
1. Execute Option B (Fresh Installation) with stable version

---

### **Option B: Fresh Installation on RHOAI 3.0 (HIGH RISK)**

**Timeline**: 3-4 weeks  
**Effort**: 60-80 hours  
**Risk**: 🔴 **HIGH** (production impact)

**Prerequisites**:
1. 🔴 **Separate OpenShift Cluster** - NEVER test on production
2. 🟡 **RHOAI 3.0 Documentation** - Read full release notes
3. 🟡 **Backup Strategy** - Full backup of RHOAI 2.25 cluster

**Migration Phases**:

#### **Phase 1: Environment Preparation** (1 week)

1. **Provision Fresh Cluster**
   - OpenShift 4.17+ (RHOAI 3.0 requirement)
   - AWS GPU nodes (g6.4xlarge, g6.12xlarge)
   - Same topology as production

2. **Install RHOAI 3.0 Operators**
   ```bash
   # Update subscription channel
   channel: stable-3.0  # or fast-3.0
   ```

3. **Deploy Stage 0: AI Platform**
   - Update `subscription-rhods-operator.yaml` → `stable-3.0`
   - Apply `DataScienceCluster` (test for schema changes)
   - Deploy MinIO, GPU MachineSets

**Validation Criteria**:
- ✅ DSC `default-dsc` is Ready
- ✅ GPU nodes provisioned and NFD labels applied
- ✅ MinIO accessible and buckets created

---

#### **Phase 2: Core Services Migration** (1 week)

1. **Stage 1: Model Serving**
   - Deploy vLLM InferenceServices (or test llm-d)
   - Migrate model weights from old MinIO
   - Test model inference endpoints
   - Re-register models in Model Registry

2. **Validation**:
   - ✅ `mistral-24b-quantized` responding on `/v1/chat/completions`
   - ✅ `mistral-24b-full` responding (if deployed)
   - ✅ Model Registry shows registered models

---

#### **Phase 3: LlamaStack & RAG** (1.5 weeks)

**⚠️ HIGHEST RISK PHASE**

1. **Deploy Stage 2: Model Alignment**
   - Test if `LlamaStackDistribution` CRD exists in 3.0
   - Deploy Milvus (fresh instance)
   - Deploy Docling Operator (check 3.0 compatibility)
   - Deploy TrustyAI Guardrails (test native integration)

2. **Rebuild Custom Image**
   ```bash
   # Base: RHOAI 3.0 LlamaStack image
   # Add: TrustyAI provider (if still needed)
   # Test: Vector I/O API (check if /v1/vector-io/insert is fixed)
   ```

3. **Re-Ingest RAG Data**
   ```bash
   # Launch batch pipeline for all 3 scenarios:
   # - scenario1-red-hat (2 PDFs, ~8MB)
   # - scenario2-acme-corporate
   # - scenario3-eu-ai-act
   ```

4. **Test Playground**
   - Evaluate RHOAI 3.0 native Playground vs. custom Streamlit UI
   - If native Playground is sufficient, deprecate custom UI
   - Test guardrails integration

**Validation Criteria**:
- ✅ LlamaStack pod running and healthy
- ✅ All 3 RAG collections registered and queryable
- ✅ Playground shows correct collection names (not UUIDs)
- ✅ Guardrails work (regex, toxicity)
- ✅ RAG retrieval returns relevant chunks

---

#### **Phase 4: Observability & Agentic AI** (0.5 weeks)

1. **Stage 3: Model Monitoring**
   - Deploy Grafana, OpenTelemetry, Tempo
   - Configure dashboards
   - Test GuideLLM benchmarking

2. **Stage 4: Model Integration**
   - Deploy MCP servers (`openshift-mcp`, `slack-mcp`)
   - Test agentic workflows
   - Validate tool execution

**Validation Criteria**:
- ✅ Grafana dashboards showing GPU metrics
- ✅ GuideLLM reports generated
- ✅ MCP tools registered in LlamaStack
- ✅ Agent can execute tools (e.g., list pods, send Slack message)

---

#### **Phase 5: Production Cutover** (2-3 days)

1. **Final Validation**
   - Run full integration test suite
   - Performance benchmarking (compare vs. RHOAI 2.25)
   - User acceptance testing

2. **Cutover**
   - Update DNS/routes to point to new cluster
   - Deprecate old RHOAI 2.25 cluster (keep as backup for 1 week)

---

### **Option C: Parallel Deployment (SAFEST, MOST EXPENSIVE)**

**Timeline**: 4-6 weeks  
**Effort**: 80-100 hours  
**Risk**: 🟡 **MEDIUM** (no production impact)

**Strategy**:
1. Deploy RHOAI 3.0 on **separate cluster** (like Option B)
2. **Keep RHOAI 2.25 running** for production workloads
3. Gradually migrate stages one-by-one
4. A/B test: compare performance, stability
5. Cutover only when RHOAI 3.0 is **proven stable**

**Advantages**:
- ✅ Zero downtime
- ✅ Gradual risk mitigation
- ✅ Easy rollback

**Disadvantages**:
- 💰 **Cost**: 2x infrastructure (2 clusters)
- 🕒 **Complexity**: Managing 2 environments

---

## 🛠️ **Technical Migration Checklist**

### **Stage 0: AI Platform**

- [ ] Update `subscription-rhods-operator.yaml` → `channel: stable-3.0`
- [ ] Test `DataScienceCluster` for schema changes
- [ ] Validate GPU MachineSets (dynamic generation should work)
- [ ] Test MinIO deployment (no changes expected)
- [ ] Verify operators: NFD, GPU, Pipelines, Serverless, Service Mesh

### **Stage 1: Model Serving**

- [ ] Test KServe compatibility (vLLM InferenceServices)
- [ ] Evaluate llm-d (distributed inference) vs. vLLM
- [ ] Migrate model weights to new MinIO
- [ ] Re-register models in Model Registry
- [ ] Test inference endpoints

### **Stage 2: Model Alignment**

- [ ] Check if `LlamaStackDistribution` CRD schema changed
- [ ] Rebuild `llama-stack-custom` image for RHOAI 3.0
- [ ] Test if `/v1/vector-io/insert` API is fixed
- [ ] Deploy Milvus (fresh instance)
- [ ] Test Docling Operator compatibility
- [ ] Deploy TrustyAI Guardrails (test native integration)
- [ ] Re-ingest all RAG data (3 scenarios)
- [ ] Test custom Playground vs. RHOAI 3.0 native Playground
- [ ] Validate guardrails (regex, toxicity)

### **Stage 3: Model Monitoring**

- [ ] Deploy Grafana, OpenTelemetry, Tempo operators
- [ ] Test dashboards (GPU, LLM metrics)
- [ ] Validate GuideLLM benchmarking
- [ ] Test TrustyAI eval integration

### **Stage 4: Model Integration**

- [ ] Deploy MCP servers (`openshift-mcp`, `slack-mcp`)
- [ ] Test tool registration in LlamaStack
- [ ] Validate agentic workflows (ReAct agent)
- [ ] Test end-to-end demo (RAG + tools)

### **GitOps & CI/CD**

- [ ] Update ArgoCD applications (branch: `rhoai-3.0-migration`)
- [ ] Test sync/refresh behavior
- [ ] Validate App-of-Apps pattern
- [ ] Test Tekton pipelines (model import, GuideLLM)

---

## 📊 **Effort Estimation**

| Phase | Duration | Effort (hours) | Risk |
|-------|----------|----------------|------|
| **Planning & Prep** | 3 days | 20 | 🟢 LOW |
| **Stage 0 Migration** | 2 days | 12 | 🟡 MEDIUM |
| **Stage 1 Migration** | 3 days | 20 | 🟡 MEDIUM |
| **Stage 2 Migration** | 5 days | 40 | 🔴 HIGH |
| **Stage 3 Migration** | 2 days | 12 | 🟢 LOW |
| **Stage 4 Migration** | 3 days | 20 | 🟡 MEDIUM |
| **Integration Testing** | 3 days | 20 | 🟡 MEDIUM |
| **Performance Testing** | 2 days | 12 | 🟡 MEDIUM |
| **Cutover & Validation** | 2 days | 12 | 🔴 HIGH |
| **Contingency (20%)** | 5 days | 34 | - |
| **TOTAL** | **30 days** | **202 hours** | 🔴 **HIGH** |

**Team**: 1-2 engineers (AI/ML + DevOps)  
**Cost Estimate** (AWS): $5,000-$8,000 (2 clusters for 30 days)

---

## ⚠️ **Risk Register**

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **LlamaStack API incompatibility** | 🔴 HIGH | 🔴 CRITICAL | Test on dev cluster first, have rollback plan |
| **Data migration failures** | 🟡 MEDIUM | 🔴 CRITICAL | Backup RHOAI 2.25, test restore procedures |
| **Custom image build failures** | 🟡 MEDIUM | 🔴 HIGH | Pre-build and test images before migration |
| **Docling Operator incompatibility** | 🟢 LOW | 🟡 MEDIUM | 3rd-party operator, may need to wait for update |
| **Performance regression** | 🟡 MEDIUM | 🟡 MEDIUM | Benchmark RHOAI 2.25 vs. 3.0, have rollback plan |
| **RHOAI 3.0 bugs (fast release)** | 🔴 HIGH | 🔴 HIGH | Wait for stable 3.x, report bugs to Red Hat |
| **GPU quota exhaustion** | 🟢 LOW | 🟡 MEDIUM | Pre-provision GPU nodes, test MachineSets |
| **TrustyAI Guardrails incompatibility** | 🟡 MEDIUM | 🟡 MEDIUM | Test native integration, have fallback (disable) |

---

## 🎯 **Recommended Action Plan**

### **SHORT TERM (Next 1-3 Months)**

1. ✅ **Continue on RHOAI 2.25** - Focus on completing Stage 4
2. ✅ **Report LlamaStack Bugs** - File Jira tickets for v0.3.0rc3 issues
3. ✅ **Document Current State** - Complete implementation docs
4. ✅ **Monitor RHOAI 3.x Releases** - Watch for stable 3.1/3.5 announcements
5. ✅ **Prepare Migration Artifacts** - Pre-build container images, export data

### **MEDIUM TERM (3-6 Months)** - When Stable 3.x Released

1. 🔄 **Provision Test Cluster** - Separate from production
2. 🔄 **Execute Phase 1-2** (Option B) - Install RHOAI 3.x, test core services
3. 🔄 **Validate Stage 2** - Critical: Test LlamaStack, RAG, Guardrails
4. 🔄 **Performance Benchmark** - Compare vs. RHOAI 2.25
5. 🔄 **Go/No-Go Decision** - Based on stability and performance

### **LONG TERM (6-12 Months)** - Production Cutover

1. 🔄 **Execute Option C** (Parallel Deployment) - If budget allows
2. 🔄 **Gradual Migration** - Stage by stage
3. 🔄 **User Acceptance Testing** - Validate all workflows
4. 🔄 **Production Cutover** - Switch DNS, deprecate old cluster

---

## 📚 **References**

1. [RHOAI 3.0 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/release_notes/release_notes)
2. [RHOAI Upgrade Policy](https://access.redhat.com/articles/7133758)
3. [RHOAI Self-Managed Life Cycle](https://access.redhat.com/support/policy/updates/rhoai-sm/lifecycle)
4. [RHOAI 3.0 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0)
5. [RHOAI 2.25 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25)

---

## 📞 **Support & Escalation**

**Red Hat Support**:
- **Jira/Case**: File support cases for migration questions
- **TAM (Technical Account Manager)**: Engage for migration planning assistance
- **Partner Engineering**: Request early access to stable 3.x builds

**Internal Stakeholders**:
- **Product Owner**: Approve migration timeline and budget
- **Infrastructure Team**: Provision test cluster, GPU quotas
- **Data Science Team**: Validate model performance post-migration
- **Security Team**: Review security posture of RHOAI 3.0

---

## ✅ **Decision Matrix**

| Scenario | Recommended Option | Timeline |
|----------|-------------------|----------|
| **Production Stability Critical** | **Option A (Wait)** | Q1-Q2 2026 |
| **Early Adopter / R&D** | **Option B (Fresh Install)** | 4-6 weeks |
| **Zero Downtime Required** | **Option C (Parallel)** | 6-8 weeks |
| **Budget Constrained** | **Option A (Wait)** | Q1-Q2 2026 |

---

**Document Version**: 1.0  
**Last Updated**: November 16, 2025  
**Next Review**: January 2026 (when stable 3.x timeline announced)  
**Status**: 🟢 **APPROVED FOR REVIEW**

