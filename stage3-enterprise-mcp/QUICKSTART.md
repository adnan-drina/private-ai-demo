# ACME LithoOps Agent - Quick Start Guide

Enterprise-grade AI-powered calibration agent built with **Quarkus + LangChain4j + MCP + vLLM**.

## 🎯 What This Demo Does

The ACME LithoOps Agent automates semiconductor equipment calibration checks using:
- **LLM Analysis**: Mistral 24B (vLLM) analyzes telemetry data against calibration limits
- **MCP Servers**: Modular services for database queries and Slack notifications
- **Quarkus**: High-performance Java framework for cloud-native AI applications
- **PostgreSQL**: Production database with equipment, service history, and parts inventory

---

## 📋 Prerequisites

### Required Infrastructure (Stage 1 & 2)
This demo assumes you have already deployed:
1. **Stage 1**: vLLM serving Mistral 24B model
   - Endpoint: `http://mistral-24b-quantized-predictor.private-ai-demo.svc.cluster.local/v1`
2. **Stage 2**: (Optional) RAG service for document retrieval

### Required Tools
- OpenShift 4.x cluster
- `oc` CLI logged in with admin privileges
- Maven 3.8+
- Java 17+

### Required Namespaces
```bash
oc new-project private-ai-demo    # For vLLM, MCP servers, PostgreSQL
oc new-project acme-calibration-ops  # For ACME Agent
```

---

## 🚀 Quick Deploy (5 Minutes)

### 1. Configure Secrets (Optional)

**⚠️ IMPORTANT:** See **[../CONFIGURATION-CHECKLIST.md](../CONFIGURATION-CHECKLIST.md)** for complete configuration guide.

**Quick setup:**

```bash
cd stage3-enterprise-mcp

# Copy configuration template
cp env.template .env

# Edit with your secrets (optional)
vim .env
```

**Add Slack Webhook (Optional - for real alerts):**
- Get webhook from: https://api.slack.com/apps
- Add to `.env`: `SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL`
- Without webhook: Slack MCP runs in DEMO MODE (console logging only)

**PostgreSQL credentials** have sensible defaults (can customize in `.env`)

### 2. Run Automated Deployment

```bash
cd stage3-enterprise-mcp
./deploy.sh
```

**Note:** Deploy script automatically loads configuration from `.env` file.

This will:
1. ✅ Verify prerequisites
2. ✅ Deploy PostgreSQL with equipment data
3. ✅ Load database schema (4 equipment records)
4. ✅ Build and deploy Database MCP
5. ✅ Build and deploy Slack MCP
6. ✅ Configure RBAC for cross-namespace access
7. ✅ Build Quarkus agent application
8. ✅ Deploy ACME Agent with UI

**Expected time:** 3-5 minutes

### 3. Access the Application

```bash
# Get the URL
oc get route acme-agent -n acme-calibration-ops -o jsonpath='{.spec.host}'
```

Open the URL in your browser: `https://acme-agent-acme-calibration-ops.apps.YOUR-CLUSTER.com`

---

## 🧪 Test the Demo

### Test 1: Passing Calibration

1. Open the ACME Agent UI
2. Select:
   - **Equipment:** `LITHO-001 (ASML NXE:3400C - EUV Scanner)`
   - **Telemetry:** `✅ Clean Data (Expected: PASS)`
3. Click **"Check Calibration"**
4. Wait 30-60 seconds for LLM analysis
5. ✅ **Expected Result:** "PASS" verdict with normal measurements

**Slack Alert:** Success notification sent to `#acme-litho`

### Test 2: Failed Calibration

1. Select:
   - **Equipment:** `LITHO-001`
   - **Telemetry:** `❌ Out-of-Spec Data (Expected: FAIL)`
2. Click **"Check Calibration"**
3. Wait 30-60 seconds
4. ❌ **Expected Result:** "FAIL" verdict with:
   - Peak overlay: 8.1 nm (exceeds ±3.5 nm limit)
   - Sustained violations from 11:03-11:09
   - Emergency calibration recommendations

**Slack Alert:** Critical alert sent to `#acme-alerts` with full recommendations

---

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  acme-calibration-ops (Frontend Namespace)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  ACME Agent (Quarkus + LangChain4j)                   │  │
│  │  • Red Hat branded UI                                 │  │
│  │  • REST API (/api/v1/ops/calibration/check)          │  │
│  │  • Manual tool orchestration (vLLM compatibility)     │  │
│  └───────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          │ Calls MCP & vLLM                  │
└──────────────────────────┼───────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  private-ai-demo (Backend Services Namespace)               │
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │  Database MCP    │  │   Slack MCP      │                │
│  │  • Equipment     │  │  • Alerts        │                │
│  │  • Service       │  │  • Notifications │                │
│  │  • Parts         │  │  • Reports       │                │
│  └────────┬─────────┘  └──────────────────┘                │
│           │                                                  │
│           ↓                                                  │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │  PostgreSQL DB   │  │   vLLM Service   │                │
│  │  • acme_equipment│  │  • Mistral 24B   │                │
│  │  • Real data     │  │  • Quantized     │                │
│  └──────────────────┘  └──────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **ACME Agent** | Quarkus + LangChain4j | Orchestrates calibration analysis |
| **Database MCP** | Python Flask + psycopg2 | Equipment data queries |
| **Slack MCP** | Python Flask + requests | Notifications and alerts |
| **PostgreSQL** | PostgreSQL 15 | Persistent equipment database |
| **vLLM** | Mistral 24B (Quantized) | LLM reasoning and analysis |

---

## 🗄️ Database Schema

The PostgreSQL database contains:

### Equipment Table
- `LITHO-001`: ASML TWINSCAN NXE:3400C (EUV Scanner)
- `L-900-07`: TEL Lithius 1300 (Resist Coater)
- `L-900-08`: TEL Lithius 1300 (Resist Coater)
- `ABC123`: Test Equipment

### Service History Table
- Calibration records
- Maintenance history
- Technician notes

### Parts Inventory Table
- Laser modules, mirrors, sensors
- Stock levels and lead times

**To query directly:**
```bash
POD=$(oc get pod -l app=postgresql -n private-ai-demo -o jsonpath='{.items[0].metadata.name}')
oc exec -it $POD -n private-ai-demo -- \
  bash -c "PGPASSWORD=acme_secure_2025 psql -U acmeadmin -d acme_equipment"
```

```sql
-- List all equipment
SELECT * FROM equipment;

-- Check service history for LITHO-001
SELECT * FROM service_history WHERE equipment_id = 'LITHO-001';

-- Query parts inventory
SELECT * FROM parts_inventory;
```

---

## 🛠️ Manual Deployment (Step-by-Step)

If you prefer manual control, here's the detailed process:

### 1. Deploy PostgreSQL

```bash
oc apply -f gitops/database/postgresql-deployment.yaml
oc wait --for=condition=available --timeout=60s deployment/postgresql -n private-ai-demo
```

### 2. Load Database Schema

```bash
POD=$(oc get pod -l app=postgresql -n private-ai-demo -o jsonpath='{.items[0].metadata.name}')
cat gitops/database/init-schema.sql | oc exec -i -n private-ai-demo $POD -- \
  bash -c "PGPASSWORD=acme_secure_2025 psql -U acmeadmin -d acme_equipment"
```

### 3. Deploy Database MCP

```bash
# Create BuildConfig
oc new-build --name=database-mcp --binary=true --strategy=docker -n private-ai-demo

# Build and deploy
cd mcp-servers/database-mcp
oc start-build database-mcp --from-dir=. -n private-ai-demo --wait
cd ../..

oc apply -f gitops/mcp-servers/database-mcp/deployment.yaml
oc apply -f gitops/mcp-servers/database-mcp/service.yaml
```

### 4. Deploy Slack MCP

```bash
# Create Slack webhook secret (optional)
oc create secret generic slack-webhook \
  --from-literal=webhook-url="https://hooks.slack.com/services/YOUR/WEBHOOK/URL" \
  -n private-ai-demo

# Create BuildConfig
oc new-build --name=slack-mcp --binary=true --strategy=docker -n private-ai-demo

# Build and deploy
cd mcp-servers/slack-mcp
oc start-build slack-mcp --from-dir=. -n private-ai-demo --wait
cd ../..

oc apply -f gitops/mcp-servers/slack-mcp/deployment.yaml
oc apply -f gitops/mcp-servers/slack-mcp/service.yaml
```

### 5. Deploy ACME Agent

```bash
# Apply RBAC
oc apply -f acme-lithoops-agent/deploy/serviceaccount.yaml
oc apply -f acme-lithoops-agent/deploy/role.yaml -n private-ai-demo
oc apply -f acme-lithoops-agent/deploy/rolebinding.yaml

# Create BuildConfig
oc new-build --name=acme-agent --binary=true --strategy=docker -n acme-calibration-ops

# Build Quarkus application
cd acme-lithoops-agent
mvn clean package -DskipTests

# Build and deploy
oc start-build acme-agent --from-dir=. -n acme-calibration-ops --wait
cd ..

oc apply -f acme-lithoops-agent/deploy/deployment.yaml
oc apply -f acme-lithoops-agent/deploy/service.yaml
oc apply -f acme-lithoops-agent/deploy/route.yaml
```

---

## 📜 View Logs

### ACME Agent
```bash
oc logs -f deployment/acme-agent -n acme-calibration-ops
```

### Database MCP
```bash
oc logs -f deployment/database-mcp -n private-ai-demo
```

### Slack MCP
```bash
oc logs -f deployment/slack-mcp -n private-ai-demo
```

### PostgreSQL
```bash
oc logs -f deployment/postgresql -n private-ai-demo
```

---

## 🔧 Troubleshooting

### Issue: ACME Agent can't reach vLLM

**Symptom:** `Connection refused` or timeouts

**Solution:**
```bash
# Check vLLM service is running
oc get inferenceservice mistral-24b-quantized -n private-ai-demo

# Verify network policy allows traffic
oc get networkpolicy -n private-ai-demo

# Test connectivity from ACME Agent pod
POD=$(oc get pod -l app=acme-agent -n acme-calibration-ops -o jsonpath='{.items[0].metadata.name}')
oc exec -it $POD -n acme-calibration-ops -- \
  curl -v http://mistral-24b-quantized-predictor.private-ai-demo.svc.cluster.local:80/v1/models
```

### Issue: Database MCP returns "Equipment not found"

**Symptom:** `404` errors from Database MCP

**Solution:**
```bash
# Verify database has data
POD=$(oc get pod -l app=postgresql -n private-ai-demo -o jsonpath='{.items[0].metadata.name}')
oc exec -it $POD -n private-ai-demo -- \
  bash -c "PGPASSWORD=acme_secure_2025 psql -U acmeadmin -d acme_equipment -c 'SELECT id FROM equipment;'"

# Expected: LITHO-001, L-900-07, L-900-08, ABC123
```

### Issue: No Slack messages received

**Symptom:** Alerts not appearing in Slack

**Solution:**
```bash
# Check if webhook secret exists
oc get secret slack-webhook -n private-ai-demo

# Verify Slack MCP logs
oc logs deployment/slack-mcp -n private-ai-demo | grep -E "webhook|alert|Slack"

# Test webhook manually
curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test from ACME Agent"}'
```

### Issue: 504 Gateway Timeout

**Symptom:** UI shows timeout error after 30 seconds

**Solution:** LLM may be slow to respond. Timeouts are already set to 180s. Check:
```bash
# Verify vLLM is responding
oc get pods -l serving.kserve.io/inferenceservice=mistral-24b-quantized -n private-ai-demo

# Check agent timeout configuration
oc get deployment acme-agent -n acme-calibration-ops -o yaml | grep timeout
```

---

## 🧹 Cleanup

To remove the entire demo:

```bash
# Delete ACME Agent
oc delete all,sa,role,rolebinding,route -l app=acme-agent -n acme-calibration-ops

# Delete MCP Servers and Database
oc delete all,secret -l component=mcp-server -n private-ai-demo
oc delete deployment postgresql -n private-ai-demo
oc delete secret postgresql-credentials -n private-ai-demo

# Delete BuildConfigs
oc delete bc acme-agent -n acme-calibration-ops
oc delete bc database-mcp slack-mcp -n private-ai-demo

# (Optional) Delete namespaces
oc delete project acme-calibration-ops
# Note: Keep private-ai-demo if you're using it for other demos
```

---

## 📚 Additional Documentation

- **[ACME-LITHOOPS-ORCHESTRATOR.md](docs/ACME-LITHOOPS-ORCHESTRATOR.md)** - Detailed architecture specification
- **[SERVICE-MESH-ARCHITECTURE.md](SERVICE-MESH-ARCHITECTURE.md)** - Service mesh and networking decisions
- **[FINAL-STATUS.md](FINAL-STATUS.md)** - Current implementation status
- **[RED-HAT-MCP-ALIGNMENT.md](RED-HAT-MCP-ALIGNMENT.md)** - MCP server design principles

---

## 🎓 What You'll Learn

1. **Enterprise AI Patterns**
   - Tool orchestration in production LLM applications
   - Handling vLLM's limited tool-calling protocol
   - Manual vs. automatic tool execution

2. **Quarkus + LangChain4j**
   - Building AI agents with Quarkus
   - Integrating LangChain4j with enterprise services
   - REST clients for MCP communication

3. **MCP (Model Context Protocol)**
   - Building modular AI tool servers
   - Generic `/execute` endpoint pattern
   - Supporting both camelCase and snake_case

4. **OpenShift Networking**
   - Cross-namespace service communication
   - NetworkPolicies for service mesh
   - Service mesh (Istio) architecture decisions

5. **Production Observability**
   - Correlation IDs for end-to-end tracing
   - Structured logging with emojis for clarity
   - Health checks and readiness probes

---

## 🙋 Support

For issues or questions:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review pod logs for error messages
3. Verify all prerequisites are met
4. Check OpenShift events: `oc get events -n private-ai-demo --sort-by='.lastTimestamp'`

---

**Built with ❤️ using Red Hat OpenShift, Quarkus, and vLLM**

