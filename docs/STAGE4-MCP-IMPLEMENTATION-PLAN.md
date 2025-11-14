# 🔧 Stage 4: MCP Server Implementation Plan

## Overview
Detailed technical implementation plans for the three MCP servers needed for Stage 4.

---

## 1. PostgreSQL Database MCP Server (`mcp::database`)

### Purpose
Provide MCP interface to PostgreSQL for ACME equipment queries

### Technology Stack
- **Language**: Python 3.11
- **Framework**: FastAPI (async support)
- **Database**: psycopg2 or asyncpg
- **Server**: Uvicorn

### File Structure
```
mcp-servers/database-mcp/
├── Dockerfile
├── requirements.txt
├── app.py                 # Main FastAPI application
├── config.py              # Configuration
├── models.py              # Pydantic models
├── database/
│   ├── __init__.py
│   ├── connection.py      # DB connection pool
│   └── queries.py         # SQL queries
├── tools/
│   ├── __init__.py
│   ├── equipment.py       # Equipment tools
│   ├── calibration.py     # Calibration tools
│   └── specifications.py  # Specifications tools
└── tests/
    └── test_tools.py
```

### API Endpoints

#### 1. Tool Discovery
```http
GET /tools
```

**Response**:
```json
{
  "tools": [
    {
      "name": "query_equipment",
      "description": "Get equipment details by ID or name",
      "inputSchema": {
        "type": "object",
        "properties": {
          "equipment_id": {
            "type": "string",
            "description": "Equipment ID (e.g., LITHO-3000)"
          }
        },
        "required": ["equipment_id"]
      }
    },
    {
      "name": "get_calibration_history",
      "description": "Retrieve calibration history for equipment",
      "inputSchema": {
        "type": "object",
        "properties": {
          "equipment_id": {"type": "string"},
          "limit": {"type": "integer", "default": 10}
        },
        "required": ["equipment_id"]
      }
    },
    {
      "name": "check_specifications",
      "description": "Verify equipment specifications and tolerances",
      "inputSchema": {
        "type": "object",
        "properties": {
          "equipment_id": {"type": "string"}
        },
        "required": ["equipment_id"]
      }
    }
  ]
}
```

#### 2. Tool Execution
```http
POST /tools/call
Content-Type: application/json

{
  "name": "query_equipment",
  "arguments": {
    "equipment_id": "LITHO-3000"
  }
}
```

**Response**:
```json
{
  "content": [
    {
      "type": "text",
      "text": "Equipment: Litho-Print-3000\nStatus: Operational\nLast Calibration: 2025-11-01\nNext Due: 2025-12-01"
    }
  ]
}
```

### Implementation: app.py

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import psycopg2
from psycopg2.extras import RealDictCursor
import os

app = FastAPI(title="Database MCP Server")

# Database connection
def get_db_connection():
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "postgresql"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        database=os.getenv("POSTGRES_DB"),
        user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
        cursor_factory=RealDictCursor
    )

# Models
class ToolInput(BaseModel):
    type: str = "object"
    properties: Dict[str, Any]
    required: List[str]

class Tool(BaseModel):
    name: str
    description: str
    inputSchema: ToolInput

class ToolCall(BaseModel):
    name: str
    arguments: Dict[str, Any]

class ContentItem(BaseModel):
    type: str = "text"
    text: str

class ToolResponse(BaseModel):
    content: List[ContentItem]

# Tool definitions
TOOLS = [
    Tool(
        name="query_equipment",
        description="Get equipment details by ID or name. Returns equipment status, specifications, and last calibration date.",
        inputSchema=ToolInput(
            properties={
                "equipment_id": {
                    "type": "string",
                    "description": "Equipment ID (e.g., LITHO-3000)"
                }
            },
            required=["equipment_id"]
        )
    ),
    Tool(
        name="get_calibration_history",
        description="Retrieve calibration history for equipment. Shows past calibration dates, results, and technician notes.",
        inputSchema=ToolInput(
            properties={
                "equipment_id": {"type": "string", "description": "Equipment ID"},
                "limit": {"type": "integer", "description": "Number of records to return", "default": 10}
            },
            required=["equipment_id"]
        )
    ),
    Tool(
        name="check_specifications",
        description="Verify equipment specifications and tolerances. Returns target values, current readings, and compliance status.",
        inputSchema=ToolInput(
            properties={
                "equipment_id": {"type": "string", "description": "Equipment ID"}
            },
            required=["equipment_id"]
        )
    ),
]

# Endpoints
@app.get("/tools")
async def list_tools():
    return {"tools": [tool.dict() for tool in TOOLS]}

@app.get("/health")
async def health():
    try:
        conn = get_db_connection()
        conn.close()
        return {"status": "healthy"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

@app.post("/tools/call", response_model=ToolResponse)
async def call_tool(tool_call: ToolCall):
    try:
        if tool_call.name == "query_equipment":
            result = query_equipment(tool_call.arguments["equipment_id"])
        elif tool_call.name == "get_calibration_history":
            result = get_calibration_history(
                tool_call.arguments["equipment_id"],
                tool_call.arguments.get("limit", 10)
            )
        elif tool_call.name == "check_specifications":
            result = check_specifications(tool_call.arguments["equipment_id"])
        else:
            raise HTTPException(status_code=404, detail=f"Tool {tool_call.name} not found")
        
        return ToolResponse(content=[ContentItem(text=result)])
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Tool implementations
def query_equipment(equipment_id: str) -> str:
    conn = get_db_connection()
    cur = conn.cursor()
    
    cur.execute("""
        SELECT equipment_id, equipment_name, equipment_type, status, 
               location, last_calibration_date, next_calibration_due
        FROM equipment
        WHERE equipment_id = %s OR equipment_name ILIKE %s
    """, (equipment_id, f"%{equipment_id}%"))
    
    result = cur.fetchone()
    conn.close()
    
    if not result:
        return f"Equipment {equipment_id} not found"
    
    return f"""Equipment Details:
ID: {result['equipment_id']}
Name: {result['equipment_name']}
Type: {result['equipment_type']}
Status: {result['status']}
Location: {result['location']}
Last Calibration: {result['last_calibration_date']}
Next Due: {result['next_calibration_due']}"""

def get_calibration_history(equipment_id: str, limit: int = 10) -> str:
    conn = get_db_connection()
    cur = conn.cursor()
    
    cur.execute("""
        SELECT calibration_date, result, technician, notes
        FROM calibration_history
        WHERE equipment_id = %s
        ORDER BY calibration_date DESC
        LIMIT %s
    """, (equipment_id, limit))
    
    results = cur.fetchall()
    conn.close()
    
    if not results:
        return f"No calibration history found for {equipment_id}"
    
    history = f"Calibration History for {equipment_id}:\n\n"
    for idx, record in enumerate(results, 1):
        history += f"{idx}. Date: {record['calibration_date']}\n"
        history += f"   Result: {record['result']}\n"
        history += f"   Technician: {record['technician']}\n"
        history += f"   Notes: {record['notes']}\n\n"
    
    return history

def check_specifications(equipment_id: str) -> str:
    conn = get_db_connection()
    cur = conn.cursor()
    
    cur.execute("""
        SELECT specification_name, target_value, tolerance, unit, current_reading
        FROM equipment_specifications
        WHERE equipment_id = %s
    """, (equipment_id,))
    
    results = cur.fetchall()
    conn.close()
    
    if not results:
        return f"No specifications found for {equipment_id}"
    
    specs = f"Specifications for {equipment_id}:\n\n"
    for spec in results:
        in_spec = abs(float(spec['current_reading']) - float(spec['target_value'])) <= float(spec['tolerance'])
        status = "✓ IN SPEC" if in_spec else "✗ OUT OF SPEC"
        
        specs += f"• {spec['specification_name']}\n"
        specs += f"  Target: {spec['target_value']} {spec['unit']}\n"
        specs += f"  Tolerance: ±{spec['tolerance']} {spec['unit']}\n"
        specs += f"  Current: {spec['current_reading']} {spec['unit']} {status}\n\n"
    
    return specs
```

### Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
```

### requirements.txt

```
fastapi==0.104.1
uvicorn==0.24.0
psycopg2-binary==2.9.9
pydantic==2.5.0
python-dotenv==1.0.0
```

### Environment Variables

```yaml
env:
- name: POSTGRES_HOST
  value: "postgresql.private-ai-demo.svc"
- name: POSTGRES_PORT
  value: "5432"
- name: POSTGRES_DB
  valueFrom:
    secretKeyRef:
      name: postgresql-credentials
      key: POSTGRES_DB
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: postgresql-credentials
      key: POSTGRES_USER
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgresql-credentials
      key: POSTGRES_PASSWORD
```

---

## 2. Slack MCP Server (`mcp::slack`)

### Purpose
Send notifications to Slack channels (demo mode: log only)

### Technology Stack
- **Language**: Python 3.11
- **Framework**: FastAPI
- **Mode**: Demo (logs) / Production (Slack SDK)

### File Structure
```
mcp-servers/slack-mcp/
├── Dockerfile
├── requirements.txt
├── app.py              # Main FastAPI application
├── config.py           # Configuration
├── models.py           # Pydantic models
├── slack/
│   ├── __init__.py
│   ├── client.py       # Slack client wrapper
│   └── demo.py         # Demo mode (log only)
└── tests/
    └── test_slack.py
```

### API Endpoints

#### 1. Tool Discovery
```http
GET /tools
```

**Response**:
```json
{
  "tools": [
    {
      "name": "send_message",
      "description": "Send a message to a Slack channel",
      "inputSchema": {
        "type": "object",
        "properties": {
          "channel": {"type": "string"},
          "message": {"type": "string"}
        },
        "required": ["channel", "message"]
      }
    },
    {
      "name": "send_alert",
      "description": "Send an urgent alert notification",
      "inputSchema": {
        "type": "object",
        "properties": {
          "channel": {"type": "string"},
          "message": {"type": "string"},
          "priority": {"type": "string", "enum": ["high", "medium", "low"]}
        },
        "required": ["channel", "message"]
      }
    }
  ]
}
```

### Implementation: app.py (Demo Mode)

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any
from datetime import datetime
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Slack MCP Server (Demo Mode)")

DEMO_MODE = os.getenv("DEMO_MODE", "true").lower() == "true"

class ToolInput(BaseModel):
    type: str = "object"
    properties: Dict[str, Any]
    required: List[str]

class Tool(BaseModel):
    name: str
    description: str
    inputSchema: ToolInput

class ToolCall(BaseModel):
    name: str
    arguments: Dict[str, Any]

class ContentItem(BaseModel):
    type: str = "text"
    text: str

class ToolResponse(BaseModel):
    content: List[ContentItem]

TOOLS = [
    Tool(
        name="send_message",
        description="Send a message to a Slack channel",
        inputSchema=ToolInput(
            properties={
                "channel": {"type": "string", "description": "Slack channel name"},
                "message": {"type": "string", "description": "Message content"}
            },
            required=["channel", "message"]
        )
    ),
    Tool(
        name="send_alert",
        description="Send an urgent alert notification with priority level",
        inputSchema=ToolInput(
            properties={
                "channel": {"type": "string", "description": "Slack channel name"},
                "message": {"type": "string", "description": "Alert message"},
                "priority": {"type": "string", "enum": ["high", "medium", "low"], "default": "medium"}
            },
            required=["channel", "message"]
        )
    ),
]

@app.get("/tools")
async def list_tools():
    return {"tools": [tool.dict() for tool in TOOLS]}

@app.get("/health")
async def health():
    return {"status": "healthy", "mode": "demo" if DEMO_MODE else "production"}

@app.post("/tools/call", response_model=ToolResponse)
async def call_tool(tool_call: ToolCall):
    try:
        if tool_call.name == "send_message":
            result = send_message(
                tool_call.arguments["channel"],
                tool_call.arguments["message"]
            )
        elif tool_call.name == "send_alert":
            result = send_alert(
                tool_call.arguments["channel"],
                tool_call.arguments["message"],
                tool_call.arguments.get("priority", "medium")
            )
        else:
            raise HTTPException(status_code=404, detail=f"Tool {tool_call.name} not found")
        
        return ToolResponse(content=[ContentItem(text=result)])
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def send_message(channel: str, message: str) -> str:
    timestamp = datetime.now().isoformat()
    
    if DEMO_MODE:
        # Demo mode: just log
        logger.info(f"[DEMO] Slack Message to #{channel}: {message}")
        return f"✓ Message sent to #{channel} (demo mode - logged only)"
    else:
        # Production mode: use Slack SDK
        try:
            from slack_sdk import WebClient
            client = WebClient(token=os.getenv("SLACK_BOT_TOKEN"))
            response = client.chat_postMessage(channel=channel, text=message)
            return f"✓ Message sent to #{channel} (ts: {response['ts']})"
        except Exception as e:
            logger.error(f"Failed to send Slack message: {e}")
            return f"✗ Failed to send message: {str(e)}"

def send_alert(channel: str, message: str, priority: str = "medium") -> str:
    timestamp = datetime.now().isoformat()
    
    # Format alert with priority emoji
    priority_emoji = {
        "high": "🚨",
        "medium": "⚠️",
        "low": "ℹ️"
    }
    
    formatted_message = f"{priority_emoji.get(priority, '📢')} **ALERT ({priority.upper()})**\n\n{message}"
    
    if DEMO_MODE:
        logger.warning(f"[DEMO] Slack Alert to #{channel} [{priority}]: {message}")
        return f"✓ Alert sent to #{channel} with {priority} priority (demo mode - logged only)"
    else:
        try:
            from slack_sdk import WebClient
            client = WebClient(token=os.getenv("SLACK_BOT_TOKEN"))
            response = client.chat_postMessage(
                channel=channel,
                text=formatted_message,
                blocks=[
                    {
                        "type": "section",
                        "text": {
                            "type": "mrkdwn",
                            "text": formatted_message
                        }
                    }
                ]
            )
            return f"✓ Alert sent to #{channel} (ts: {response['ts']})"
        except Exception as e:
            logger.error(f"Failed to send Slack alert: {e}")
            return f"✗ Failed to send alert: {str(e)}"
```

### Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
```

### requirements.txt

```
fastapi==0.104.1
uvicorn==0.24.0
pydantic==2.5.0
python-dotenv==1.0.0
# Uncomment for production mode:
# slack-sdk==3.23.0
```

---

## 3. OpenShift MCP Server (`mcp::openshift`) - Optional

### Strategy: Use Existing Implementation

**Recommended**: Deploy [kubernetes-mcp-server by manusa](https://github.com/manusa/kubernetes-mcp-server)

### Why Use Existing?
- ✅ Full Kubernetes API coverage
- ✅ Battle-tested implementation
- ✅ Includes `pods_log` tool (demo uses this)
- ✅ Can be deployed as-is

### Deployment Manifest

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openshift-mcp
  namespace: private-ai-demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: openshift-mcp-reader
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-mcp-reader-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: openshift-mcp-reader
subjects:
- kind: ServiceAccount
  name: openshift-mcp
  namespace: private-ai-demo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openshift-mcp
  namespace: private-ai-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: openshift-mcp
  template:
    metadata:
      labels:
        app: openshift-mcp
    spec:
      serviceAccountName: openshift-mcp
      containers:
      - name: openshift-mcp
        image: ghcr.io/manusa/kubernetes-mcp-server:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: PORT
          value: "8080"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: openshift-mcp
  namespace: private-ai-demo
spec:
  selector:
    app: openshift-mcp
  ports:
  - port: 8080
    targetPort: 8080
```

### Tools Provided
- `pods_list` - List pods in namespace
- `pods_get` - Get pod details
- `pods_log` - Get pod logs (used in demo)
- `deployments_list` - List deployments
- And many more...

---

## BuildConfig Strategy

### For Custom Python Servers (database-mcp, slack-mcp)

**Option A: Binary Build (S2I)**
```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: database-mcp
spec:
  source:
    type: Binary
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: python:3.11
  output:
    to:
      kind: ImageStreamTag
      name: database-mcp:latest
```

**Build Command**:
```bash
oc start-build database-mcp --from-dir=./mcp-servers/database-mcp --follow
```

**Option B: Dockerfile Build**
```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: database-mcp
spec:
  source:
    type: Git
    git:
      uri: https://github.com/adnan-drina/private-ai-demo.git
      ref: feature/stage4-implementation
    contextDir: mcp-servers/database-mcp
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: database-mcp:latest
```

---

## Testing Strategy

### 1. Unit Tests
Test each tool independently:
```bash
# Test database-mcp
curl -X POST http://database-mcp:8080/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "query_equipment",
    "arguments": {"equipment_id": "LITHO-3000"}
  }'
```

### 2. Integration Tests
Test with LlamaStack:
```bash
# List tools
curl http://llama-stack:8321/tools/list

# Test tool call via LlamaStack
curl -X POST http://llama-stack:8321/agents/turn/create \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "acme-agent",
    "messages": [{"role": "user", "content": "Check equipment LITHO-3000"}],
    "tools": ["mcp::database"]
  }'
```

### 3. End-to-End Tests
Test via Playground UI:
1. Enable database tool
2. Ask: "What is the status of Litho-Print-3000?"
3. Verify tool call executes
4. Verify response includes equipment data

---

## Next Steps

1. **Implement database-mcp** (Priority 1)
2. **Implement slack-mcp** (Priority 1)
3. **Build container images**
4. **Deploy and test independently**
5. **Register with LlamaStack**
6. **Test via Playground**
7. **Deploy openshift-mcp** (Optional)

---

**Status**: 📝 **Ready for Implementation**

