## Stage 02 & 03 Review

### Stage 02 – Model Alignment
- **Llama Stack (Streamlit UI)**: Compatibility shim (`sitecustomize.py`) now bridges 0.2 UI ↔︎ 0.3 APIs, including path/payload rewrites, vector DB synthesis, and guardrail adapters. RAG and Chat pages share guardrail toggles and dedupe logic.
- **Guardrails**: TrustyAI orchestrator wired with regex + toxicity shields, OTEL telemetry, and dedicated Hugging Face detector Deployment/BuildConfig/Service. `guardrails-orchestrator` exports metrics via OTLP.
- **Vector IO / Milvus**: Collections for `red_hat_docs`, `acme_corporate`, `eu_ai_act` registered and surfaced in UI. Retrieval deduplication prevents duplicate revisions.
- **Docling & Pipelines**: Batch ingestion scripts plus KFP manifests remain the single source for re-populating Milvus.
- **Cleanup**: Removed the unused Next.js `containers/llama-stack-playground` image and runtime `tmp/` artifacts to avoid confusion now that Streamlit is the supported UI.

### Stage 03 – Model Monitoring
- **Observability**: Grafana dashboards (`llama-ops`, `llama-trace-view`) read from the OTEL collector/Tempo, with corrected guardrail + GPU queries. Console plug‑ins and NVIDIA DCGM resources remain available but optional.
- **GuideLLM Benchmarks**: CronJobs/Jobs/Workbench are updated but idle; Tekton pipeline manifests preserved for future automation.
- **TrustyAI / LM Eval**: Operator configs, Istio routing, and metrics cronjobs are staged for fairness/LMEval workflows, though not active by default.
- **Outstanding work**: Smoke-test the regex/toxicity shields in both Chat and RAG flows and document the demo sequence (already tracked in TODOs). No additional Stage 03 code removal required right now.

### Ready for Stage 04 – Model Integration
1. **Repo state**: Stage 02/03 manifests are consistent with the running cluster; unused assets removed. `git status` now reflects only intentional modifications.
2. **Operational checklist**:
   - ✅ Telemetry via OTEL collector and Grafana panels.
   - ✅ Guardrail shields selectable in UI.
   - ✅ RAG datasets/collections healthy.
   - ⏳ Pending guardrail smoke tests + presentation script.
3. **Next focus**: Begin wiring Stage 04 model-integration manifests once these final validation items are complete.

