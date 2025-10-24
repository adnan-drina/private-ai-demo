# Stage 4: Model Integration with MCP + Llama Stack

## Overview

Stage 4 demonstrates enterprise agentic AI using the Model Context Protocol (MCP). This stage deploys an ACME manufacturing calibration agent that orchestrates multiple AI capabilities: database queries, RAG-enhanced document retrieval, expert LLM analysis, and team notifications.

## Components

### MCP Servers
- **Database MCP Server** - PostgreSQL query interface
  - Equipment metadata queries
  - Calibration history lookup
  - Specification retrieval
- **Slack MCP Server** - Team notification system
  - Alert notifications
  - Status updates
  - Collaboration triggers

### Data Layer
- **PostgreSQL Database** - Equipment metadata storage
  - Equipment specifications
  - Calibration records
  - Maintenance history

### Application
- **ACME Calibration Agent** - Quarkus application
  - Llama Stack integration
  - MCP server orchestration
  - RAG-enhanced analysis
  - Web UI for demonstrations

### Demo Tools
- **Agent Notebook** - Step-by-step workflow demonstration
  - Component interaction visualization
  - Technical flow explanation
  - Sovereignty and architecture discussion

## Prerequisites

- **Stages 1, 2, 3** deployed and validated
- Models serving with RAG capability
- Llama Stack orchestrator ready

## Deployment

```bash
# Deploy all Stage 4 components
./deploy.sh

# Validate deployment
./validate.sh
```

## Verification

Monitor deployment:

```bash
# Check PostgreSQL
oc get deployment postgresql -n private-ai-demo
oc get svc postgresql -n private-ai-demo

# Check MCP servers
oc get deployment database-mcp -n private-ai-demo
oc get deployment slack-mcp -n private-ai-demo

# Check ACME Agent
oc get deployment acme-agent -n private-ai-demo
oc get route acme-agent -n private-ai-demo

# Test ACME Agent UI
ACME_URL=$(oc get route acme-agent -n private-ai-demo -o jsonpath='{.spec.host}')
curl -k https://${ACME_URL}/api/health
```

## Agent Workflow

The ACME Calibration Agent orchestrates a multi-step AI workflow:

```
User Request: "Check calibration for Litho-Print-3000"
    ↓
ACME Agent (Quarkus + LangChain4j)
    ↓
1. Query Equipment DB (via Database MCP)
   ├→ Equipment specs
   ├→ Last calibration date
   └→ Operational parameters
    ↓
2. Retrieve Calibration Docs (via RAG)
   ├→ Llama Stack orchestrates
   ├→ Search Milvus for relevant procedures
   └→ Return calibration guidelines
    ↓
3. LLM Analysis (via vLLM)
   ├→ Analyze equipment status
   ├→ Compare with specifications
   └→ Generate expert recommendations
    ↓
4. Send Notifications (via Slack MCP)
   ├→ Alert maintenance team
   ├→ Include analysis summary
   └→ Add action items
    ↓
Comprehensive Response with Citations
```

## Demo Use Case

**ACME Lithography Manufacturing**

Equipment: Litho-Print-3000 Calibration System

The agent assists with:
- Equipment status inquiries
- Calibration procedure guidance
- Out-of-spec detection
- Maintenance team coordination

## Testing the Agent

### Via Web UI

```bash
# Get ACME Agent URL
oc get route acme-agent -n private-ai-demo -o jsonpath='{.spec.host}'

# Open in browser
# Navigate to: https://<acme-agent-url>
# Try: "Check calibration status for Litho-Print-3000"
```

### Via API

```bash
ACME_URL=$(oc get route acme-agent -n private-ai-demo -o jsonpath='{.spec.host}')

curl -k https://${ACME_URL}/api/calibrate \
  -H "Content-Type: application/json" \
  -d '{
    "equipmentId": "LITHO-3000",
    "query": "What is the calibration procedure?"
  }'
```

### Via Notebook

```bash
# Access OpenShift AI dashboard
# Navigate to: Workbenches → rag-testing
# Open: 05-acme-agent-demo.ipynb
# Run cells to see detailed workflow
```

## MCP Server Details

### Database MCP

Provides tools for:
- `query_equipment` - Get equipment details
- `get_calibration_history` - Retrieve past calibrations
- `check_specifications` - Verify specs

Connection:
```
Agent → database-mcp:8080 → postgresql:5432
```

### Slack MCP

Provides tools for:
- `send_message` - Post to channel
- `send_alert` - Send urgent notification
- `create_thread` - Start discussion

Configuration:
- Demo mode (logs only) or webhook URL

## Architecture Highlights

### Sovereignty
- **On-Premise Models** - All inference local
- **Data Privacy** - No external API calls
- **Full Control** - Custom model selection

### Integration Patterns
- **MCP Protocol** - Standardized tool interface
- **Llama Stack** - Central orchestration
- **RAG Enhancement** - Context-aware responses
- **Multi-Agent** - Composable AI workflows

## Troubleshooting

### PostgreSQL Connection Issues
- Check service: `oc get svc postgresql -n private-ai-demo`
- Test connection: `oc exec -it deployment/database-mcp -- nc -zv postgresql 5432`
- Verify init: `oc logs deployment/postgresql -n private-ai-demo`

### MCP Servers Not Responding
- Check logs: `oc logs deployment/database-mcp -n private-ai-demo`
- Verify service: `oc get svc database-mcp -n private-ai-demo`
- Test endpoint: `curl http://database-mcp:8080/health`

### ACME Agent Errors
- Check Llama Stack connection: `oc get svc llama-stack -n private-ai-demo`
- Verify MCP endpoints in agent config
- Check logs: `oc logs deployment/acme-agent -n private-ai-demo`

### Slack Notifications Not Working
- Verify webhook URL in Slack MCP deployment
- Check demo mode: Should see log messages
- Test: `curl -X POST http://slack-mcp:8080/send -d '{"message":"test"}'`

## GitOps Structure

```
gitops-new/stage04-model-integration/
├── postgresql/          # Database deployment + init schema
├── mcp-servers/
│   ├── database-mcp/    # PostgreSQL MCP server
│   └── slack-mcp/       # Slack notification MCP server
├── acme-agent/          # Quarkus agent application
└── notebooks/           # Agent demo notebook
```

## Topology View

In OpenShift Console → Topology:

```
🤖 ACME Agent (Quarkus)
  ├─→ 🦙 Llama Stack
  │     ├─→ 🔥 vLLM (Mistral models)
  │     └─→ 🗄️  Milvus (RAG)
  ├─→ 🔌 Database MCP
  │     └─→ 🐘 PostgreSQL
  └─→ 📢 Slack MCP
        └─→ 💬 Slack API
```

## Next Steps

Once Stage 4 is validated:
1. Test the complete agent workflow
2. Review component interactions in notebook
3. Demo complete! All 4 pillars of Red Hat AI demonstrated

## Red Hat AI Four Pillars

✅ **Pillar 1: Flexible Foundation** (Stage 1)
- vLLM efficient serving
- Multiple model formats
- GPU optimization

✅ **Pillar 2: Data & AI** (Stage 2)  
- RAG with enterprise data
- Vector storage
- Automated ingestion

✅ **Pillar 3: Trust & Governance** (Stage 3)
- Model evaluation
- Quality monitoring
- Observability

✅ **Pillar 4: Integration & Automation** (Stage 4)
- Agentic workflows
- MCP protocol
- Enterprise integration

## Documentation

- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Llama Stack Agents](https://llama-stack.readthedocs.io/en/latest/concepts/agents.html)
- [Quarkus + LangChain4j](https://docs.quarkiverse.io/quarkus-langchain4j/dev/index.html)
- [Red Hat AI Demos](https://github.com/rh-aiservices-bu/)
