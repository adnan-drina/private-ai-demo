# Stage 3: ACME LithoOps Agentic Orchestrator

> **Enterprise AI Agent for Semiconductor Equipment Calibration**  
> Built with Quarkus, LangChain4j, MCP, and vLLM

---

## 🎯 Overview

The ACME LithoOps Agent demonstrates enterprise-grade AI orchestration for semiconductor manufacturing. It automates equipment calibration analysis by:

1. **Querying equipment data** from PostgreSQL via Database MCP
2. **Retrieving calibration limits** from ACME documentation  
3. **Analyzing telemetry readings** using Mistral 24B LLM (vLLM)
4. **Sending critical alerts** to Slack via Slack MCP

**Key Features:**
- ✅ **Production-Ready**: Real database, real Slack integration, no mocks
- ✅ **Quarkus Native**: High-performance Java framework
- ✅ **MCP Protocol**: Modular, reusable AI tool servers
- ✅ **vLLM Compatible**: Manual tool orchestration (works without native tool calling)
- ✅ **Red Hat Branded**: Professional UI following Red Hat design standards
- ✅ **Full Observability**: Correlation IDs, structured logging, health checks

---

## 🚀 Quick Start

### Prerequisites
- OpenShift 4.x with vLLM (Stage 1) deployed
- `oc` CLI, Maven 3.8+, Java 17+
- Namespaces: `private-ai-demo`, `acme-calibration-ops`

### Deploy in 5 Minutes

```bash
# Optional: Configure Slack webhook
export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

# Deploy everything
cd stage3-enterprise-mcp
./deploy.sh
```

**That's it!** The script deploys:
- PostgreSQL with equipment database
- Database MCP (equipment queries)
- Slack MCP (notifications)
- ACME Agent (Quarkus + LangChain4j)

**📖 Full documentation:** [QUICKSTART.md](QUICKSTART.md)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────┐
│  ACME Agent (Quarkus)               │
│  • Red Hat UI                       │
│  • LangChain4j orchestration        │
│  • Manual tool execution            │
└─────────────┬───────────────────────┘
              │
              ↓
┌─────────────────────────────────────┐
│  Backend Services (private-ai-demo) │
│  ┌──────────┐  ┌──────────┐        │
│  │ DB MCP   │  │Slack MCP │        │
│  └────┬─────┘  └──────────┘        │
│       ↓                             │
│  ┌──────────┐  ┌──────────┐        │
│  │PostgreSQL│  │ vLLM     │        │
│  │ Database │  │Mistral24B│        │
│  └──────────┘  └──────────┘        │
└─────────────────────────────────────┘
```

---

## 🧪 Demo Flows

### Scenario 1: Passing Calibration ✅
**Equipment:** LITHO-001 (EUV Scanner)  
**Data:** Clean telemetry (all readings within spec)  
**Result:** PASS verdict, success notification to Slack

### Scenario 2: Failed Calibration ❌
**Equipment:** LITHO-001  
**Data:** Out-of-spec overlay accuracy (8.1 nm peak)  
**Result:** FAIL verdict, critical alert to Slack with:
- Peak measurement: 8.1 nm (exceeds ±3.5 nm limit)
- Sustained violations from 11:03-11:09
- Emergency calibration recommendations

---

## 📦 What's Included

```
stage3-enterprise-mcp/
├── QUICKSTART.md              # 👈 START HERE - Complete deployment guide
├── deploy.sh                  # Automated deployment script
├── acme-lithoops-agent/       # Quarkus application
│   ├── src/main/java/         # Java source code
│   ├── src/main/resources/    # Config, UI, telemetry data
│   ├── deploy/                # Kubernetes manifests
│   └── pom.xml                # Maven dependencies
├── mcp-servers/
│   ├── database-mcp/          # PostgreSQL MCP server
│   └── slack-mcp/             # Slack notification MCP
├── gitops/                    # Kubernetes manifests
│   ├── database/              # PostgreSQL deployment
│   ├── mcp-servers/           # MCP deployments
│   └── acme-agent/            # ACME Agent deployment (archive)
└── docs/                      # Historical documentation
```

---

## 🎓 Key Learnings

### 1. **vLLM Tool Orchestration**
vLLM doesn't support native tool calling with "tool" roles. Solution: **manual orchestration**:
```java
// Gather all data first
String equipmentInfo = getEquipmentInfo(equipmentId);
String limits = getCalibrationLimits(equipmentId, "overlay");
String telemetry = readTelemetryData(telemetryFile);

// Send single comprehensive prompt to LLM
String prompt = buildAnalysisPrompt(equipmentInfo, limits, telemetry);
String analysis = llm.chat(prompt);
```

### 2. **MCP Protocol Pattern**
Generic `/execute` endpoint with tool name + parameters:
```java
// Request format
{
  "tool": "query_equipment",
  "parameters": {"equipment_id": "LITHO-001"}
}

// Response format
{
  "result": {"equipment": {...}}
}
```

### 3. **Cross-Namespace Communication**
RBAC configuration for ACME Agent to access vLLM and MCP services:
- ServiceAccount in `acme-calibration-ops`
- Role in `private-ai-demo` (vLLM access)
- RoleBinding for cross-namespace permissions

### 4. **Production Database Integration**
No mocks! Real PostgreSQL with:
- Equipment table (4 lithography tools)
- Service history (calibration records)
- Parts inventory (modules, sensors)

---

## 📊 Technical Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | Quarkus + LangChain4j | AI orchestration, REST API |
| **LLM** | vLLM (Mistral 24B) | Reasoning and analysis |
| **MCP Servers** | Python Flask | Tool servers (DB, Slack) |
| **Database** | PostgreSQL 15 | Equipment data |
| **Platform** | OpenShift 4.x | Kubernetes + Service Mesh |

---

## 🔗 Related Demos

- **Stage 1**: vLLM Deployment (Mistral 24B with vLLM)
- **Stage 2**: RAG Service (Document retrieval)
- **Stage 3**: This demo (Agentic orchestration)

---

## 📚 Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Complete setup guide 👈 **Start here!**
- **[ACME-LITHOOPS-ORCHESTRATOR.md](docs/ACME-LITHOOPS-ORCHESTRATOR.md)** - Detailed specification
- **[SERVICE-MESH-ARCHITECTURE.md](SERVICE-MESH-ARCHITECTURE.md)** - Networking decisions
- **[FINAL-STATUS.md](FINAL-STATUS.md)** - Current implementation status
- **[RED-HAT-MCP-ALIGNMENT.md](RED-HAT-MCP-ALIGNMENT.md)** - MCP design principles

---

## 🛠️ Maintenance

### View Logs
```bash
# ACME Agent
oc logs -f deployment/acme-agent -n acme-calibration-ops

# Database MCP
oc logs -f deployment/database-mcp -n private-ai-demo

# Slack MCP
oc logs -f deployment/slack-mcp -n private-ai-demo
```

### Update Application
```bash
cd acme-lithoops-agent
mvn clean package -DskipTests
oc start-build acme-agent --from-dir=. -n acme-calibration-ops --wait
oc rollout restart deployment/acme-agent -n acme-calibration-ops
```

### Database Queries
```bash
POD=$(oc get pod -l app=postgresql -n private-ai-demo -o jsonpath='{.items[0].metadata.name}')
oc exec -it $POD -n private-ai-demo -- \
  bash -c "PGPASSWORD=acme_secure_2025 psql -U acmeadmin -d acme_equipment"
```

---

## 🙏 Credits

- **Red Hat OpenShift** - Enterprise Kubernetes platform
- **Quarkus** - Supersonic Subatomic Java
- **LangChain4j** - AI orchestration for Java
- **vLLM** - High-throughput LLM serving
- **Mistral AI** - Mistral 24B model

---

**📖 Ready to deploy? → [QUICKSTART.md](QUICKSTART.md)**

**Built with ❤️ using Red Hat OpenShift**
