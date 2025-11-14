# 🔍 Stage 4: Demo Analysis & Implementation Plan

## Overview
This document analyzes the [OpenDataHub LlamaStack Level 6 Demo](https://github.com/opendatahub-io/llama-stack-demos/blob/main/demos/rag_agentic/notebooks/Level6_agents_MCP_and_RAG.ipynb) and plans how to adapt it to our private-ai-demo infrastructure.

**Source**: [Level6_agents_MCP_and_RAG.ipynb](https://raw.githubusercontent.com/opendatahub-io/llama-stack-demos/main/demos/rag_agentic/notebooks/Level6_agents_MCP_and_RAG.ipynb)

---

## 📊 Demo Notebook Architecture Analysis

### Demo Use Case
**Scenario**: DevOps troubleshooting workflow

**Steps**:
1. Review OpenShift logs for a failing pod
2. Categorize the pod status (Normal/Error)
3. Search troubleshooting documentation using RAG
4. Send Slack message to ops team with summary

### Key Components

#### 1. **MCP Tools Used**
- **`mcp::openshift`** - Kubernetes/OpenShift cluster interaction
  - Tool: `pods_log` - Fetch pod logs
  - Source: [kubernetes-mcp-server by manusa](https://github.com/manusa/kubernetes-mcp-server)
  
- **`mcp::slack`** - Slack notifications
  - Tool: `slack_post_message` - Send messages to channels
  - Source: [Slack MCP Server](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/slack)

#### 2. **Built-in RAG Tool**
- **`builtin::rag`** - Knowledge search
  - Tool: `knowledge_search`
  - Uses: Vector DB (Milvus) for document retrieval
  - Configuration:
    ```python
    builtin_rag = dict(
        name="builtin::rag",
        args={
            "vector_db_ids": [vector_db_id],
        },
    )
    ```

#### 3. **Agent Types Demonstrated**

##### A. Prompt Chaining (Directed)
- Fixed sequence of steps
- Manual orchestration
- Each step explicitly defined

##### B. ReAct Agent (Autonomous)
- Dynamic reasoning and action
- Self-directed tool selection
- Iterative "Reason then Act" loop
- More flexible and adaptive

**ReAct Agent Definition**:
```python
agent = ReActAgent(
    client=client,
    model=model_id,
    tools=["mcp::slack", "mcp::openshift", builtin_rag],
    response_format={
        "type": "json_schema",
        "json_schema": ReActOutput.model_json_schema(),
    },
    sampling_params={"max_tokens": 512},
)
```

#### 4. **Tool Registration Pattern**
Tools are registered by namespace identifier:
- MCP tools: `"mcp::slack"`, `"mcp::openshift"`
- Built-in tools: `builtin::rag` (dict with config)

---

## 🏗️ Our Current Stage 4 Architecture

### Components We Have

#### 1. **PostgreSQL Database**
- **Purpose**: Equipment metadata storage
- **Schema**: ACME calibration equipment
- **Status**: ✅ Manifest ready

#### 2. **Slack MCP Server**
- **Purpose**: Team notifications
- **Location**: `gitops/stage04-model-integration/mcp-servers/slack-mcp/`
- **Status**: ⚠️ No image/implementation
- **Expected**: Python-based MCP server

#### 3. **Database MCP Server** (Custom)
- **Purpose**: PostgreSQL query interface
- **Location**: `gitops/stage04-model-integration/mcp-servers/database-mcp/`
- **Status**: ⚠️ No image/implementation
- **Tools Planned**:
  - `query_equipment`
  - `get_calibration_history`
  - `check_specifications`

#### 4. **ACME Agent** (Quarkus)
- **Purpose**: Orchestration UI
- **Location**: `gitops/stage04-model-integration/acme-agent/`
- **Status**: ⚠️ No image/implementation
- **Stack**: Java + Quarkus + LangChain4j

#### 5. **LlamaStack Playground** (Stage 2)
- **Status**: ✅ Deployed and working
- **Location**: `gitops/stage02-model-alignment/llama-stack/`
- **Features**:
  - Chat interface
  - RAG interface
  - Guardrails integration
  - Streaming responses

#### 6. **RAG Infrastructure** (Stage 2)
- **Vector DB**: Milvus
- **Collections**: 
  - `red_hat_docs`
  - `acme_corporate`
  - `eu_ai_act`
- **Status**: ✅ Deployed and working

---

## 🎯 Adaptation Strategy: Demo → Our Implementation

### Key Differences

| Aspect | Demo Notebook | Our Implementation |
|--------|---------------|-------------------|
| **Interface** | Jupyter Notebook | LlamaStack Playground (Web UI) |
| **Use Case** | DevOps pod troubleshooting | ACME equipment calibration |
| **MCP Tools** | `mcp::openshift`, `mcp::slack` | `mcp::database`, `mcp::slack` (+ optional `mcp::openshift`) |
| **RAG Data** | OpenShift troubleshooting docs | ACME calibration procedures |
| **Agent** | Programmatic (Python) | Integrated in Playground UI |

### Our Adapted Use Case

**ACME Lithography Calibration Assistant**

**Workflow**:
1. User asks: "Check calibration for Litho-Print-3000"
2. Agent queries equipment DB (via `mcp::database`)
3. Agent retrieves calibration docs (via `builtin::rag`)
4. Agent analyzes with LLM
5. Agent sends alert (via `mcp::slack`)
6. User sees comprehensive response in Playground

---

## 🔧 MCP Server Implementation Analysis

### How MCP Servers Work

Based on the demo references:

#### Architecture
```
LlamaStack Server
  ├──→ MCP Registry (registered servers)
  │    ├──→ mcp::openshift (Kubernetes MCP Server)
  │    ├──→ mcp::slack (Slack MCP Server)
  │    └──→ mcp::database (Custom - PostgreSQL)
  │
  └──→ Agent Runtime
       └──→ Tool Calls → MCP Server Endpoints
```

#### MCP Server Requirements
1. **HTTP/SSE Server** - Expose tools via HTTP API
2. **Tool Discovery** - List available tools
3. **Tool Execution** - Execute tool calls with parameters
4. **Response Format** - Return structured results

#### Reference Implementation Pattern

**From kubernetes-mcp-server**:
- Language: Any (TypeScript, Python, Java)
- Protocol: Model Context Protocol (MCP)
- Endpoints:
  - `GET /tools` - List available tools
  - `POST /tools/{tool_name}` - Execute tool
- Tools exposed as JSON schemas

---

## 📝 Implementation Plan: mcp::openshift

### Option 1: Use Existing kubernetes-mcp-server

**Source**: https://github.com/manusa/kubernetes-mcp-server

**Pros**:
- ✅ Already implements full Kubernetes API
- ✅ Includes `pods_log` tool (demo uses this)
- ✅ Battle-tested implementation
- ✅ Can be deployed as-is

**Cons**:
- TypeScript/Node.js (different from our Python stack)
- May include more tools than needed

**Deployment**:
```yaml
# gitops/stage04-model-integration/mcp-servers/openshift-mcp/
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openshift-mcp
spec:
  containers:
  - name: openshift-mcp
    image: ghcr.io/manusa/kubernetes-mcp-server:latest
    env:
    - name: KUBECONFIG
      value: /var/run/secrets/kubernetes.io/serviceaccount
```

### Option 2: Build Custom Python MCP Server

**Pros**:
- ✅ Consistent with our stack (Python)
- ✅ Only tools we need
- ✅ Customizable for ACME use case

**Cons**:
- More development effort
- Need to implement MCP protocol

**Tools to Implement**:
- `get_pod_logs` - Fetch pod logs
- `get_pod_status` - Check pod health
- `list_pods` - List pods in namespace

### Option 3: Skip mcp::openshift Initially

**Focus on core ACME use case first**:
- ✅ `mcp::database` (critical for equipment queries)
- ✅ `mcp::slack` (for notifications)
- ⏸️ `mcp::openshift` (nice-to-have for ops demo)

**Rationale**: Our primary use case is calibration, not pod troubleshooting

---

## 📝 Implementation Plan: mcp::database (Priority)

### Purpose
Provide MCP interface to PostgreSQL for equipment queries

### Tools to Implement

#### 1. `query_equipment`
```json
{
  "name": "query_equipment",
  "description": "Get equipment details by ID or name",
  "parameters": {
    "equipment_id": "string"
  }
}
```

**SQL**:
```sql
SELECT * FROM equipment WHERE equipment_id = ?
```

#### 2. `get_calibration_history`
```json
{
  "name": "get_calibration_history",
  "description": "Retrieve calibration history for equipment",
  "parameters": {
    "equipment_id": "string",
    "limit": "integer"
  }
}
```

**SQL**:
```sql
SELECT * FROM calibration_history 
WHERE equipment_id = ? 
ORDER BY calibration_date DESC 
LIMIT ?
```

#### 3. `check_specifications`
```json
{
  "name": "check_specifications",
  "description": "Verify equipment specifications and tolerances",
  "parameters": {
    "equipment_id": "string"
  }
}
```

**SQL**:
```sql
SELECT specification_name, target_value, tolerance, unit
FROM equipment_specifications
WHERE equipment_id = ?
```

### Implementation: Python Flask/FastAPI

**File Structure**:
```
mcp-servers/database-mcp/
├── Dockerfile
├── requirements.txt
├── app.py               # MCP server
├── tools/
│   ├── __init__.py
│   ├── equipment.py     # Equipment query tools
│   └── calibration.py   # Calibration tools
└── db/
    └── connection.py    # PostgreSQL connection
```

**app.py** (Flask/FastAPI):
```python
from flask import Flask, request, jsonify
import psycopg2

app = Flask(__name__)

# MCP Server endpoints
@app.route('/tools', methods=['GET'])
def list_tools():
    return jsonify({
        "tools": [
            {
                "name": "query_equipment",
                "description": "Get equipment details",
                "parameters": {...}
            },
            ...
        ]
    })

@app.route('/tools/<tool_name>', methods=['POST'])
def execute_tool(tool_name):
    params = request.json
    result = execute_tool_logic(tool_name, params)
    return jsonify(result)
```

---

## 📝 Implementation Plan: mcp::slack

### Our Existing Manifest
Location: `gitops/stage04-model-integration/mcp-servers/slack-mcp/deployment.yaml`

**Current Config**:
```yaml
env:
- name: PORT
  value: "8080"
- name: SLACK_WEBHOOK_URL
  valueFrom:
    secretKeyRef:
      name: slack-webhook
      key: url  # Need to create this secret
```

### Tools Required

#### 1. `send_message`
```json
{
  "name": "send_message",
  "description": "Send a message to a Slack channel",
  "parameters": {
    "channel": "string",
    "message": "string"
  }
}
```

#### 2. `send_alert`
```json
{
  "name": "send_alert",
  "description": "Send an urgent notification",
  "parameters": {
    "channel": "string",
    "message": "string",
    "priority": "high|medium|low"
  }
}
```

### Implementation Options

**Option A: Use Official Slack MCP Server**
- Source: https://github.com/modelcontextprotocol/servers-archived/tree/main/src/slack
- Language: TypeScript
- Docker: Build from source

**Option B: Custom Python Implementation**
- Use `slack_sdk` Python package
- Simpler for demo mode (logs only)
- Easy to switch to real Slack later

---

## 📚 RAG Data Alignment

### Demo's RAG Data
- **Purpose**: OpenShift troubleshooting documentation
- **Processing**: Chunked and embedded in Milvus
- **Usage**: Agent searches for error solutions

### Our RAG Data (Existing)

#### Collections We Have:
1. **`red_hat_docs`** - Red Hat product documentation
2. **`acme_corporate`** - ACME corporate policies
3. **`eu_ai_act`** - EU AI Act regulations

#### What We Need for ACME Demo:
**New Collection**: `acme_calibration_docs`

**Content**:
- Litho-Print-3000 calibration procedures
- Equipment specifications
- Troubleshooting guides
- Maintenance schedules

### Data Processing Workflow

**Current (Stage 2)**:
```
Documents → Docling → Chunks → Embeddings → Milvus
```

**For ACME Docs**:
1. Create calibration documents (PDF/Markdown)
2. Use existing Docling pipeline
3. Store in new collection: `acme_calibration_docs`
4. Reference in agent config

**Document Topics Needed**:
- Calibration frequency requirements
- Tolerance specifications
- Common error codes
- Corrective actions
- Safety procedures

---

## 🔧 Tool Registration in LlamaStack

### How Tools Are Registered

Based on the demo, tools are registered at the **LlamaStack server level**, not in the playground.

#### Registration Methods

##### 1. MCP Server Registration
**In LlamaStack config** (`run.yaml`):
```yaml
providers:
  - provider_type: mcp
    config:
      servers:
        - name: slack
          type: stdio
          command: node
          args: ["/path/to/slack-mcp-server"]
        
        - name: openshift
          type: http
          url: "http://openshift-mcp:8080"
        
        - name: database
          type: http
          url: "http://database-mcp:8080"
```

##### 2. Built-in Tool Registration
**RAG is built-in**, configured per-agent:
```python
tools=[
    "mcp::slack",
    "mcp::database",
    {
        "name": "builtin::rag",
        "args": {
            "vector_db_ids": ["acme_calibration_docs"]
        }
    }
]
```

### Playground Configuration

#### Current Playground Features (Stage 2)
- ✅ Chat interface
- ✅ RAG interface
- ✅ Guardrails selection
- ✅ Shield configuration
- ⚠️ **No explicit MCP tool selection UI**

#### How Demo Uses Tools
**Programmatic (Python SDK)**:
```python
agent = ReActAgent(
    client=client,
    model=model_id,
    tools=["mcp::slack", "mcp::openshift", builtin_rag],
    ...
)
```

#### Adaptation for Playground

**Challenge**: Playground UI doesn't have explicit tool selection

**Solutions**:

##### Option A: Extend Playground UI
Add tool selection checkboxes:
```python
# In playground-chat.py or playground-rag.py
available_tools = llama_stack_api.client.tools.list()
selected_tools = st.multiselect(
    "Available Tools",
    options=[tool.identifier for tool in available_tools],
    help="Select MCP tools to enable for this conversation"
)
```

##### Option B: Pre-configured Agent Modes
Add dropdown for different agent profiles:
```python
agent_profiles = {
    "ACME Calibration": ["mcp::database", "mcp::slack", "builtin::rag"],
    "DevOps Assistant": ["mcp::openshift", "mcp::slack", "builtin::rag"],
    "Basic Chat": []
}
```

##### Option C: Always-On Tools
Enable all tools by default, let LLM decide:
```python
# Agent automatically has access to all registered tools
response = llama_stack_api.client.inference.chat_completion(
    model_id=selected_model,
    messages=messages,
    tools="all",  # Use all available tools
)
```

---

## 🎯 Recommended Implementation Approach

### Phase 1: Foundation (Current)
**Status**: ✅ Complete
- [x] LlamaStack deployed
- [x] Playground UI working
- [x] RAG infrastructure (Milvus)
- [x] Guardrails integrated

### Phase 2: MCP Infrastructure (Next)
**Priority**: Build core MCP servers

#### A. Database MCP Server (High Priority)
1. **Create Python implementation**
   - Flask/FastAPI server
   - PostgreSQL connection
   - 3 tools: query_equipment, get_calibration_history, check_specifications
2. **Build container image**
   - Dockerfile
   - BuildConfig in OpenShift
3. **Deploy and test**
   - Deploy to `private-ai-demo` namespace
   - Test endpoints independently

#### B. Slack MCP Server (High Priority)
1. **Decide implementation**
   - Option 1: Official TypeScript server (build from source)
   - Option 2: Custom Python (simpler for demo)
2. **Configure Slack webhook** (or demo mode)
3. **Build and deploy**

#### C. OpenShift MCP Server (Optional)
1. **Use existing kubernetes-mcp-server**
   - Deploy pre-built image
   - Configure ServiceAccount with RBAC
2. **Or skip** for initial ACME demo

### Phase 3: RAG Data
1. **Create calibration documents**
   - Litho-Print-3000 procedures
   - Equipment specs
   - Troubleshooting guides
2. **Ingest into Milvus**
   - Use existing Docling pipeline
   - New collection: `acme_calibration_docs`
3. **Test retrieval**

### Phase 4: LlamaStack Configuration
1. **Register MCP servers** in `run.yaml`
2. **Test tool discovery**
   ```bash
   curl http://llama-stack:8321/tools/list
   ```
3. **Verify tool calls work**

### Phase 5: Playground Integration
1. **Extend Playground UI** (Option A or B)
   - Add tool selection UI
   - Or add agent profile dropdown
2. **Test in Playground**
   - Enable ACME tools
   - Ask calibration questions
   - Verify tool calls execute
3. **Iterate and refine**

### Phase 6: ACME Agent (Optional)
**If Quarkus agent is needed**:
1. **Build Quarkus app**
   - LangChain4j integration
   - Web UI
   - MCP client
2. **Or use Playground as primary interface**

---

## 📋 Implementation Checklist

### Immediate Next Steps

- [ ] **Create PostgreSQL init schema** for ACME equipment
  - Equipment table
  - Calibration history table
  - Specifications table

- [ ] **Implement database-mcp Python server**
  - Flask/FastAPI app
  - 3 core tools
  - Dockerfile

- [ ] **Implement slack-mcp server** (demo mode)
  - Python implementation
  - Log messages instead of real Slack
  - Dockerfile

- [ ] **Build container images**
  - Create BuildConfigs
  - Build in OpenShift
  - Tag as `:latest`

- [ ] **Create calibration documents**
  - Litho-Print-3000 manual
  - Calibration procedures
  - Troubleshooting guide

- [ ] **Ingest documents into Milvus**
  - Use Docling pipeline
  - Create `acme_calibration_docs` collection

- [ ] **Update LlamaStack config**
  - Register database-mcp
  - Register slack-mcp
  - Test tool listing

- [ ] **Extend Playground UI**
  - Add tool selection
  - Test tool integration

- [ ] **Create demo script**
  - Example prompts
  - Expected behavior
  - Validation steps

---

## 🎓 Key Learnings from Demo

### 1. **MCP Tools Are Registered Server-Side**
Not in the notebook/playground - they're configured in LlamaStack

### 2. **ReAct Agents Are More Flexible**
Better than prompt chaining for complex, dynamic tasks

### 3. **Tool Naming Convention**
- MCP tools: `mcp::{server_name}`
- Built-in tools: `builtin::{tool_name}` (dict with config)

### 4. **RAG Tool Integration**
RAG is just another tool in the agent's toolbox, called dynamically

### 5. **Agent Autonomy**
The LLM decides which tools to use and in what order (ReAct pattern)

---

## 🚀 Success Criteria

**Stage 4 Demo is successful when**:

1. ✅ User can ask: "Check calibration for Litho-Print-3000"
2. ✅ Agent queries database-mcp for equipment info
3. ✅ Agent searches acme_calibration_docs via RAG
4. ✅ Agent generates calibration analysis
5. ✅ Agent sends Slack notification (demo mode: logs)
6. ✅ User sees complete response in Playground UI
7. ✅ All tool calls visible in conversation

---

## 📚 References

- [Demo Notebook](https://raw.githubusercontent.com/opendatahub-io/llama-stack-demos/main/demos/rag_agentic/notebooks/Level6_agents_MCP_and_RAG.ipynb)
- [kubernetes-mcp-server](https://github.com/manusa/kubernetes-mcp-server)
- [Slack MCP Server](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/slack)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [LlamaStack Agents](https://llama-stack.readthedocs.io/en/latest/concepts/agents.html)

---

**Status**: 📝 **Analysis Complete - Ready for Implementation Planning**

**Next**: Create detailed implementation tasks for each MCP server

