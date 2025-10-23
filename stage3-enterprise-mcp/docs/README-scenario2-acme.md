# Stage 3: ACME LithoOps Agentic Orchestrator

**Production-grade Python agent with MCP servers for autonomous calibration checks**

## 🎯 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ACME Agent (Python Flask)                                  │
│                                                             │
│  Agent Skills (6 tools):                                    │
│  • prepare-calibration  → Query RAG for limits              │
│  • watch-telemetry      → Parse CSV, compute metrics        │
│  • compare-against-limits → Determine PASS/FAIL             │
│  • draft-report         → Generate calibration report       │
│  • notify-slack         → Send alerts via Slack MCP         │
│  • query-equipment      → Lookup via Database MCP           │
└──────────────┬──────────────────────────────────────────────┘
               │
      ┌────────┴────────┬───────────────┬────────────────┐
      │                 │               │                │
      ↓                 ↓               ↓                ↓
Stage 2 RAG     Slack MCP       Database MCP    Stage 1 vLLM
(Llama Stack)   (Flask)         (Flask)         (Mistral 24B)
```

## 📦 Components

### 1. MCP Servers (Model Context Protocol)

#### Slack MCP Server
- **Tools**: `send_slack_message`, `send_equipment_alert`, `send_maintenance_plan`
- **Purpose**: Team notifications with formatted equipment alerts
- **Demo Mode**: Logs alerts to console (no webhook configured)

#### Database MCP Server
- **Tools**: `query_equipment`, `query_service_history`, `query_parts_inventory`
- **Purpose**: Equipment database queries
- **Data**: Mock in-memory database (3 equipment records, parts inventory)

### 2. ACME Agent (Python)

**Skills**:
1. **prepare_calibration**: Query Stage 2 RAG for calibration limits
2. **watch_telemetry**: Parse CSV telemetry, compute overlay/dose/vibration metrics
3. **compare_against_limits**: Determine PASS/PASS_WITH_ACTION/FAIL verdict
4. **draft_report**: Generate calibration report (text format)
5. **notify_slack**: Send alert via Slack MCP
6. **query_equipment**: Lookup equipment details via Database MCP

**Orchestration**: Chains skills together for end-to-end calibration workflow

## 🎬 Demo Flows

### Flow 1: Calibration Check (Clean Data) → PASS

**Input**: `acme_telemetry_clean.csv`

**Telemetry**:
- Overlay: 3.0 nm (< 3.5 nm UCL) ✅
- Dose Uniformity: 0.4% (< 2.5% UCL) ✅
- Best Focus: 0.52 μm (within target ± tolerance) ✅
- Vibration: 0.4 mm/s (< 0.8 mm/s threshold) ✅

**Result**: 
- Verdict: **PASS**
- Actions: [] (none)
- Slack: Green 🟢 notification

**cURL Test**:
```bash
AGENT_URL="https://acme-agent-private-ai-demo.apps.cluster-n8cnx.n8cnx.sandbox2830.opentlc.com"

curl -X POST $AGENT_URL/ops/calibration/check \
  -H 'Content-Type: application/json' \
  -d '{
    "tool": "L-900-07",
    "product": "PX-7",
    "layer": "M1",
    "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_clean.csv",
    "slackNotify": true
  }'
```

**Expected Response**:
```json
{
  "verdict": "PASS",
  "actions": [],
  "measured": {
    "maxOverlay": 3.0,
    "doseUniformity": 0.41,
    "bestFocus": 0.52,
    "vibration": 0.4
  },
  "limits": {
    "overlayUCL": 3.5,
    "doseUniformityUCL": 2.5
  },
  "reportPath": "./documents/scenario2/reports/CR-...-L-900-07-PX-7-M1.txt",
  "slackMsgId": "2025-10-08T..."
}
```

---

### Flow 2: Anomaly Triage (Out-of-Spec) → FAIL

**Input**: `acme_telemetry_outofspec.csv`

**Telemetry**:
- Overlay: 4.74 nm (> 3.5 nm UCL) ❌
- Dose Uniformity: 0.6% (< 2.5% UCL) ✅
- Best Focus: 0.48 μm (outside tolerance) ❌
- Vibration: 1.0 mm/s (> 0.8 mm/s threshold) ❌
- Sustained violation: YES (overlay > 3.5nm for 3+ consecutive points)

**Result**:
- Verdict: **FAIL**
- Actions: [
    "Investigate overlay calibration",
    "Check DFO baseline",
    "Inspect pump vibration",
    "Check mechanical stability"
  ]
- Slack: Red 🔴 alert with detailed violations

**cURL Test**:
```bash
curl -X POST $AGENT_URL/ops/calibration/check \
  -H 'Content-Type: application/json' \
  -d '{
    "tool": "L-900-07",
    "product": "PX-7",
    "layer": "M1",
    "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_outofspec.csv",
    "slackNotify": true
  }'
```

**Expected Response**:
```json
{
  "verdict": "FAIL",
  "actions": [
    "Investigate overlay calibration",
    "Check DFO baseline",
    "Inspect pump vibration",
    "Check mechanical stability"
  ],
  "measured": {
    "maxOverlay": 4.74,
    "doseUniformity": 0.6,
    "bestFocus": 0.48,
    "vibration": 1.0,
    "sustainedOverlayViolation": true
  }
}
```

---

## 🚀 Deployment

### Automated Deployment

```bash
cd stage3-enterprise-mcp
./deploy.sh
```

This will:
1. Build and deploy Slack MCP
2. Build and deploy Database MCP
3. Create telemetry data ConfigMap
4. Build and deploy ACME Agent
5. Run health checks and verification

### Manual Deployment

```bash
# 1. Deploy MCP servers
oc apply -k ../gitops/components/mcp-servers/slack-mcp/
oc apply -k ../gitops/components/mcp-servers/database-mcp/

# 2. Create telemetry ConfigMap
oc create configmap acme-telemetry \
  --from-file=acme_telemetry_clean.csv=documents/scenario2/telemetry/acme_telemetry_clean.csv \
  --from-file=acme_telemetry_outofspec.csv=documents/scenario2/telemetry/acme_telemetry_outofspec.csv \
  -n private-ai-demo

# 3. Deploy ACME Agent
oc apply -k ../gitops/components/acme-agent/
```

---

## 📊 Observability

### Logging (with Correlation IDs)

All logs include correlation IDs for end-to-end tracing:

```
2025-10-08 14:22:41 - [31981906-b5ae-431c-9ca3-790269dbc584] - acme_agent - INFO - AgentOrchestrator: Starting calibration check
2025-10-08 14:22:41 - [31981906-b5ae-431c-9ca3-790269dbc584] - acme_agent - INFO - QueryEquipmentSkill: Looking up L-900-07
2025-10-08 14:22:41 - [31981906-b5ae-431c-9ca3-790269dbc584] - acme_agent - INFO - PrepareCalibrationSkill: Querying RAG for PX-7/M1 limits
2025-10-08 14:22:41 - [31981906-b5ae-431c-9ca3-790269dbc584] - acme_agent - INFO - WatchTelemetrySkill: overlay=3.00nm, doseU=0.41%, vibration=0.40mm/s
2025-10-08 14:22:41 - [31981906-b5ae-431c-9ca3-790269dbc584] - acme_agent - INFO - CompareAgainstLimitsSkill: Verdict=PASS (0 violations)
2025-10-08 14:22:41 - [31981906-b5ae-431c-9ca3-790269dbc584] - acme_agent - INFO - DraftReportSkill: Report saved to ./documents/scenario2/reports/CR-...
2025-10-08 14:22:41 - [31981906-b5ae-431c-9ca3-790269dbc584] - acme_agent - INFO - NotifySlackSkill: Slack notification sent successfully
2025-10-08 14:22:41 - [31981906-b5ae-431c-9ca3-790269dbc584] - acme_agent - INFO - AgentOrchestrator: Calibration check complete (verdict=PASS)
```

### Metrics (Captured in Logs)

- **RAG Latency**: Time to query Stage 2 RAG (mock in current implementation)
- **Telemetry Point Count**: Number of CSV records processed
- **MCP Call Results**: Success/failure of MCP tool calls
- **Verdict**: PASS/PASS_WITH_ACTION/FAIL
- **Report Path**: Location of generated calibration report

### View Logs

```bash
# ACME Agent logs
oc logs -f $(oc get pod -l app=acme-agent -n private-ai-demo -o name | head -1)

# Slack MCP logs (shows alert content)
oc logs -f $(oc get pod -l app=slack-mcp -n private-ai-demo -o name | head -1)

# Database MCP logs
oc logs -f $(oc get pod -l app=database-mcp -n private-ai-demo -o name | head -1)
```

### View Generated Reports

```bash
oc exec -n private-ai-demo $(oc get pod -l app=acme-agent -n private-ai-demo -o name | head -1) -- ls -lh /app/documents/scenario2/reports/

# View report content
oc exec -n private-ai-demo $(oc get pod -l app=acme-agent -n private-ai-demo -o name | head -1) -- cat /app/documents/scenario2/reports/CR-20251008-142241-L-900-07-PX-7-M1.txt
```

---

## 🛡️ Guardrails

### 1. Correlation ID Tracking
Every request gets a unique UUID for end-to-end tracing across all components.

### 2. Demo Mode (Slack MCP)
Slack MCP runs in demo mode (no webhook configured). All alerts are logged to console with full formatting, allowing verification without external dependencies.

### 3. Mock Data
- Equipment database: In-memory mock with 3 equipment records
- RAG limits: Static mock values (in production, would call Stage 2 RAG API)
- Telemetry: CSV files with realistic semiconductor fab data

### 4. Error Handling
All MCP calls include timeout (10s) and exception handling with detailed error messages.

---

## 🎯 Success Criteria

| Criteria | Status |
|----------|--------|
| Slack MCP deployed | ✅ Working |
| Database MCP deployed | ✅ Working |
| ACME Agent deployed | ✅ Working |
| Flow 1 (Clean) → PASS | ✅ Verified |
| Flow 2 (Out-of-spec) → FAIL | ✅ Verified |
| Correlation IDs logged | ✅ All requests |
| MCP connectivity tests | ✅ Both MCPs reachable |
| Reports generated | ✅ Text format |
| Slack alerts sent | ✅ Demo mode |

---

## 📁 File Structure

```
stage3-enterprise-mcp/
├── deploy.sh                          # Automated deployment script
├── README-scenario2-acme.md           # This file
├── mcp-servers/
│   ├── slack-mcp/
│   │   ├── slack_mcp_server.py        # Slack MCP implementation
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   └── database-mcp/
│       ├── database_mcp_server.py     # Database MCP implementation
│       ├── Dockerfile
│       └── requirements.txt
├── quarkus-agent/
│   ├── acme_agent.py                  # Python agent with all skills
│   ├── Dockerfile
│   └── requirements.txt
└── documents/scenario2/
    ├── telemetry/
    │   ├── acme_telemetry_clean.csv
    │   └── acme_telemetry_outofspec.csv
    └── reports/                       # Generated reports (in pod)
        └── CR-*.txt
```

---

## 🔧 Design Decisions

### Python Agent (vs Quarkus)

**Decision**: Implemented Python Flask agent instead of Quarkus + LangChain4j

**Rationale**:
- Time constraint: 2-hour implementation sprint
- Faster iteration: Python prototyping is faster than Java/Quarkus setup
- Same architecture: Agent skills, MCP integration, orchestration patterns maintained
- Production path: Can migrate to Quarkus + GraalVM native for <1s startup and <50MB memory

**Trade-offs**:
- ✅ Faster implementation (achieved end-to-end demo in 2 hours)
- ✅ Same MCP protocol and architecture
- ❌ Startup time: ~3-5s (vs <1s with GraalVM native)
- ❌ Memory: ~256MB (vs <50MB with GraalVM native)

### Mock RAG Integration

**Decision**: Static mock limits instead of calling Stage 2 RAG API

**Rationale**:
- Stage 2 RAG requires Llama Stack agent orchestration for tool calling
- Focus on end-to-end MCP workflow demonstration
- Easy to swap: Replace mock with HTTP client in `prepare_calibration` skill

**Production Implementation**:
```python
def prepare_calibration(product, layer, tool, correlation_id):
    # Call Stage 2 RAG API
    response = requests.post(
        f"{RAG_BASE_URL}/rag/limits",
        json={"product": product, "layer": layer},
        timeout=30
    )
    limits = response.json()
    
    # Query for calibration procedure
    answer_response = requests.post(
        f"{RAG_BASE_URL}/rag/answer",
        json={
            "query": f"Prepare daily DFO calibration for {product}/{layer} on {tool}",
            "filters": {"product": product, "layer": layer}
        }
    )
    # ...
```

### Text Reports (vs PDF)

**Decision**: Simple text reports instead of PDF generation

**Rationale**:
- Faster implementation
- Easier debugging (can `cat` files)
- Production: Swap with `reportlab` or `iText` for PDF

---

## 🚀 Next Steps

### Production Enhancements

1. **Quarkus Migration**: Migrate to Quarkus + LangChain4j + GraalVM native
2. **Real RAG Integration**: Call Stage 2 Llama Stack APIs for limits and procedures
3. **PDF Reports**: Use `reportlab` for production-quality PDF generation
4. **Slack Webhook**: Configure real Slack webhook for live notifications
5. **OpenShift MCP**: Add Kubernetes/OpenShift MCP for cluster actions (create maintenance jobs)
6. **Prometheus Metrics**: Add `prometheus_client` for custom metrics
7. **Database**: Replace mock with PostgreSQL or MongoDB

### Additional Features

1. **File Upload**: Accept telemetry CSV upload via multipart/form-data
2. **Historical Reports**: Store reports in S3/MinIO for long-term retention
3. **Dashboard UI**: Web UI for viewing reports and triggering calibration checks
4. **Scheduled Checks**: CronJob to run calibration checks on schedule
5. **Multi-Equipment**: Batch calibration checks for multiple tools

---

## 📚 References

- [Model Context Protocol](https://modelcontextprotocol.io)
- [Flask Documentation](https://flask.palletsprojects.com/)
- [Quarkus + LangChain4j](https://docs.quarkiverse.io/quarkus-langchain4j/)
- [Stage 2 RAG Implementation](../stage2-private-data-rag/README.md)

---

**Last Updated**: October 8, 2025  
**Status**: ✅ All acceptance tests passing


