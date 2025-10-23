# Stage 3 Implementation Plan: ToolHive + Quarkus (Red Hat Aligned)

**Date**: October 8, 2025  
**Status**: Implementation Plan - Red Hat Official Methodology  
**Alignment**: 100% Red Hat ToolHive + Kubernetes MCP Server

---

## 🎯 Red Hat Official Approach

Based on Red Hat's official documentation:
- **ToolHive Operator**: Kubernetes-native MCP server management
- **Kubernetes MCP Server**: Red Hat's official cluster management MCP
- **MCPServer CRDs**: Declarative MCP server deployment
- **GitOps**: All configuration in Git

**References**:
- [How to deploy MCP servers on OpenShift using ToolHive](https://developers.redhat.com/articles/2025/10/01/how-deploy-mcp-servers-openshift-using-toolhive)
- [Kubernetes MCP server: AI-powered cluster management](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management)

---

## 📦 MCP Servers (5 Total)

### 1. Kubernetes MCP Server ⭐ (Red Hat Official)

**Type**: Official Red Hat MCP  
**Purpose**: AI-powered OpenShift cluster management

**Capabilities:**
- `get_pods` - List pods in namespace with status
- `get_deployments` - List deployments
- `get_services` - List services
- `describe_pod` - Get detailed pod information
- `get_logs` - Fetch pod logs (last N lines)
- `scale_deployment` - Scale replicas up/down
- `get_events` - Get cluster events
- `get_nodes` - List cluster nodes (if RBAC allows)

**Deployment** (ToolHive MCPServer CR):
```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: kubernetes-mcp
  namespace: private-ai-demo
  labels:
    app: kubernetes-mcp
    mcp-type: official
    vendor: redhat
spec:
  serverType: k8s
  serviceAccount: mcp-k8s-reader
  rbac:
    clusterRole: view  # Or custom ClusterRole
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

**RBAC** (required):
```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-k8s-reader
  namespace: private-ai-demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: mcp-k8s-reader-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: mcp-k8s-reader
  namespace: private-ai-demo
```

**Demo Use Cases:**
- "What pods are running in private-ai-demo?"
- "Show me the logs for the mistral-24b pod"
- "How many GPU nodes are available?"
- "Scale the mistral-24b deployment to 2 replicas"

---

### 2. Slack MCP Server 💬 (Custom - Based on Previous Work)

**Type**: Custom MCP (Python Flask)  
**Purpose**: Team collaboration and notifications

**Previous Implementation** (Proven):
- ✅ Slack webhook integration
- ✅ Natural language commands
- ✅ Formatted alerts with severity levels
- ✅ Equipment-specific notifications
- ✅ Kubernetes Secret for webhook URL

**Capabilities:**
- `send_slack_message` - Send custom message to channel
- `send_equipment_alert` - Formatted equipment alert with:
  - Equipment ID
  - Status/defect rate
  - Impact analysis (yield loss, wafer value)
  - Recommended actions
  - Timestamp
- `send_shift_report` - Formatted shift summary
- `send_maintenance_plan` - Formatted maintenance plan

**Deployment** (ToolHive MCPServer CR):
```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: slack-mcp
  namespace: private-ai-demo
  labels:
    app: slack-mcp
    mcp-type: custom
    integration: slack
spec:
  serverType: custom
  image: quay.io/redhat-ai-demo/slack-mcp:v1.0
  port: 8080
  env:
  - name: SLACK_WEBHOOK_URL
    valueFrom:
      secretKeyRef:
        name: slack-webhook
        key: webhook-url
  - name: DEFAULT_CHANNEL
    value: "#mcp-demo"
  - name: DEFAULT_USERNAME
    value: "AI Field Service Agent"
  - name: DEFAULT_ICON
    value: ":robot_face:"
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  livenessProbe:
    httpGet:
      path: /health
      port: 8080
    initialDelaySeconds: 10
    periodSeconds: 10
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
```

**Secret** (Slack Webhook):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: slack-webhook
  namespace: private-ai-demo
type: Opaque
stringData:
  webhook-url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

**Implementation** (slack_mcp_server.py):
```python
from flask import Flask, request, jsonify
import requests
import os
from datetime import datetime

app = Flask(__name__)

SLACK_WEBHOOK_URL = os.getenv('SLACK_WEBHOOK_URL')
DEFAULT_CHANNEL = os.getenv('DEFAULT_CHANNEL', '#mcp-demo')

@app.route('/tools', methods=['GET'])
def list_tools():
    """Return available Slack tools (MCP protocol)"""
    return jsonify({
        "tools": [
            {
                "name": "send_slack_message",
                "description": "Send a custom message to Slack channel",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "message": {"type": "string", "description": "Message content"},
                        "channel": {"type": "string", "description": "Channel name (optional)"}
                    },
                    "required": ["message"]
                }
            },
            {
                "name": "send_equipment_alert",
                "description": "Send formatted equipment alert to Slack",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "equipment_id": {"type": "string"},
                        "status": {"type": "string"},
                        "defect_rate": {"type": "number"},
                        "baseline": {"type": "number"},
                        "impact": {"type": "string"}
                    },
                    "required": ["equipment_id", "status"]
                }
            },
            {
                "name": "send_maintenance_plan",
                "description": "Send formatted maintenance plan to Slack",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "equipment_id": {"type": "string"},
                        "plan": {"type": "string"},
                        "priority": {"type": "string"}
                    },
                    "required": ["equipment_id", "plan"]
                }
            }
        ]
    })

@app.route('/execute', methods=['POST'])
def execute_tool():
    """Execute a Slack tool (MCP protocol)"""
    data = request.json
    tool = data.get('tool')
    params = data.get('parameters', {})
    
    if tool == 'send_slack_message':
        return send_message(params)
    elif tool == 'send_equipment_alert':
        return send_alert(params)
    elif tool == 'send_maintenance_plan':
        return send_plan(params)
    else:
        return jsonify({"error": "Unknown tool"}), 400

def send_message(params):
    """Send simple Slack message"""
    message = params.get('message', '')
    channel = params.get('channel', DEFAULT_CHANNEL)
    
    payload = {
        "channel": channel,
        "text": message,
        "username": os.getenv('DEFAULT_USERNAME', 'AI Agent'),
        "icon_emoji": os.getenv('DEFAULT_ICON', ':robot_face:')
    }
    
    try:
        response = requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)
        response.raise_for_status()
        return jsonify({
            "result": {
                "success": True,
                "channel": channel,
                "timestamp": datetime.now().isoformat()
            }
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def send_alert(params):
    """Send formatted equipment alert"""
    equipment_id = params.get('equipment_id')
    status = params.get('status')
    defect_rate = params.get('defect_rate', 0)
    baseline = params.get('baseline', 0)
    impact = params.get('impact', 'Unknown')
    
    # Format rich Slack message
    message = f"""🚨 *EQUIPMENT ALERT*

*Equipment:* {equipment_id}
*Status:* {status}
*Defect Rate:* {defect_rate}% (Baseline: {baseline}%)
*Impact:* {impact}

*Recommended Actions:*
• Investigate root cause immediately
• Check calibration logs
• Review recent process changes
• Escalate to engineering if needed

*Reported:* {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}"""
    
    payload = {
        "channel": DEFAULT_CHANNEL,
        "text": message,
        "username": "Equipment Intelligence Agent",
        "icon_emoji": ":factory:"
    }
    
    try:
        response = requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)
        response.raise_for_status()
        return jsonify({
            "result": {
                "success": True,
                "equipment_id": equipment_id,
                "channel": DEFAULT_CHANNEL,
                "timestamp": datetime.now().isoformat()
            }
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def send_plan(params):
    """Send formatted maintenance plan"""
    equipment_id = params.get('equipment_id')
    plan = params.get('plan')
    priority = params.get('priority', 'Normal')
    
    message = f"""🔧 *MAINTENANCE PLAN GENERATED*

*Equipment:* {equipment_id}
*Priority:* {priority}

*Plan:*
{plan}

*Generated:* {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}"""
    
    payload = {
        "channel": DEFAULT_CHANNEL,
        "text": message,
        "username": "Maintenance Planning Agent",
        "icon_emoji": ":wrench:"
    }
    
    try:
        response = requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)
        response.raise_for_status()
        return jsonify({
            "result": {
                "success": True,
                "equipment_id": equipment_id,
                "timestamp": datetime.now().isoformat()
            }
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

@app.route('/ready', methods=['GET'])
def ready():
    # Check webhook is configured
    if not SLACK_WEBHOOK_URL:
        return jsonify({"status": "not_ready", "reason": "webhook_not_configured"}), 503
    return jsonify({"status": "ready"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

**Containerfile**:
```dockerfile
FROM registry.access.redhat.com/ubi9/python-39:latest

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY slack_mcp_server.py .

USER 1001

EXPOSE 8080

CMD ["python", "slack_mcp_server.py"]
```

**requirements.txt**:
```
flask==3.0.0
requests==2.31.0
```

**Demo Use Cases:**
- "Send a message to Slack: 'Maintenance complete for ABC123'"
- "Alert the team about equipment ABC123 defect rate increase"
- "Send the maintenance plan to Slack"

---

### 3. Database MCP Server (Custom)

**Type**: Custom MCP (Python Flask)  
**Purpose**: Equipment database queries

**Capabilities:**
- `query_equipment` - Get equipment details by ID
- `query_service_history` - Get maintenance history
- `query_parts_inventory` - Check parts availability
- `query_technician_schedule` - Find available technicians

**MCPServer CR**:
```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: database-mcp
  namespace: private-ai-demo
spec:
  serverType: custom
  image: quay.io/redhat-ai-demo/database-mcp:v1.0
  port: 8080
  env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: database-credentials
        key: url
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
```

**Mock Database** (SQLite for demo):
```sql
-- Equipment table
CREATE TABLE equipment (
    id TEXT PRIMARY KEY,
    type TEXT,
    status TEXT,
    location TEXT,
    customer TEXT
);

INSERT INTO equipment VALUES 
    ('ABC123', 'L-900 EUV Scanner', 'Operational', 'Fab 3, Bay 12', 'ACME Semiconductor'),
    ('DEF456', 'Overlay Metrology', 'Maintenance Due', 'Fab 3, Bay 8', 'ACME Semiconductor');

-- Service history
CREATE TABLE service_history (
    id INTEGER PRIMARY KEY,
    equipment_id TEXT,
    date TEXT,
    type TEXT,
    notes TEXT
);

INSERT INTO service_history VALUES 
    (1, 'ABC123', '2024-10-01', 'Preventive Maintenance', 'DFO calibration completed'),
    (2, 'ABC123', '2024-09-15', 'Calibration', 'Overlay calibration');

-- Parts inventory
CREATE TABLE parts (
    part_number TEXT PRIMARY KEY,
    name TEXT,
    quantity INTEGER,
    location TEXT
);

INSERT INTO parts VALUES 
    ('P12345', 'DFO Module', 3, 'Warehouse A'),
    ('P67890', 'EUV Source', 1, 'Warehouse B');

-- Technician schedule
CREATE TABLE technicians (
    id TEXT PRIMARY KEY,
    name TEXT,
    skill_level TEXT,
    available_slots TEXT  -- JSON array
);

INSERT INTO technicians VALUES 
    ('TECH-007', 'John Smith', 'Senior', '["2024-10-15T14:00:00", "2024-10-15T16:00:00"]'),
    ('TECH-012', 'Jane Doe', 'Expert', '["2024-10-15T09:00:00", "2024-10-16T14:00:00"]');
```

---

### 4. Calendar MCP Server (Custom)

**Type**: Custom MCP (Python Flask)  
**Purpose**: Appointment scheduling

**Capabilities:**
- `check_availability` - Find free time slots
- `schedule_appointment` - Book maintenance time
- `cancel_appointment` - Cancel booking
- `list_appointments` - Get schedule for date range

**MCPServer CR**:
```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: calendar-mcp
  namespace: private-ai-demo
spec:
  serverType: custom
  image: quay.io/redhat-ai-demo/calendar-mcp:v1.0
  port: 8080
  env:
  - name: CALENDAR_PROVIDER
    value: "mock"  # or "google" with credentials
```

**Mock Implementation** (in-memory):
```python
# Simple in-memory calendar for demo
appointments = {}

def check_availability(date, duration_hours=2):
    """Find free slots on given date"""
    # Mock: return 2-3 available slots
    return [
        {"start": f"{date}T09:00:00", "end": f"{date}T11:00:00", "technician": "TECH-007"},
        {"start": f"{date}T14:00:00", "end": f"{date}T16:00:00", "technician": "TECH-007"},
        {"start": f"{date}T10:00:00", "end": f"{date}T12:00:00", "technician": "TECH-012"}
    ]
```

---

### 5. Email MCP Server (Custom)

**Type**: Custom MCP (Python Flask)  
**Purpose**: Customer notifications

**Capabilities:**
- `send_email` - Send notification email
- `send_confirmation` - Send appointment confirmation

**MCPServer CR**:
```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: email-mcp
  namespace: private-ai-demo
spec:
  serverType: custom
  image: quay.io/redhat-ai-demo/email-mcp:v1.0
  port: 8080
  env:
  - name: SMTP_SERVER
    value: "smtp.example.com"
  - name: SMTP_PORT
    value: "587"
  - name: SMTP_USERNAME
    valueFrom:
      secretKeyRef:
        name: email-credentials
        key: username
  - name: SMTP_PASSWORD
    valueFrom:
      secretKeyRef:
        name: email-credentials
        key: password
```

**Mock Implementation** (log to console):
```python
def send_email(to, subject, body):
    """Send email (or log in demo mode)"""
    print(f"📧 EMAIL SENT")
    print(f"To: {to}")
    print(f"Subject: {subject}")
    print(f"Body: {body}")
    return {"success": True, "message_id": f"msg-{uuid.uuid4().hex[:8]}"}
```

---

## 🏗️ Quarkus AI Agent

**Technology Stack:**
- Quarkus 3.x
- LangChain4j
- GraalVM Native Image
- JAX-RS (REST API)
- Micrometer (Metrics)

**Dependencies** (pom.xml):
```xml
<dependencies>
    <!-- Quarkus -->
    <dependency>
        <groupId>io.quarkus</groupId>
        <artifactId>quarkus-rest</artifactId>
    </dependency>
    <dependency>
        <groupId>io.quarkus</groupId>
        <artifactId>quarkus-rest-jackson</artifactId>
    </dependency>
    
    <!-- LangChain4j -->
    <dependency>
        <groupId>dev.langchain4j</groupId>
        <artifactId>langchain4j</artifactId>
        <version>0.30.0</version>
    </dependency>
    <dependency>
        <groupId>dev.langchain4j</groupId>
        <artifactId>langchain4j-open-ai</artifactId>
        <version>0.30.0</version>
    </dependency>
    
    <!-- HTTP Client -->
    <dependency>
        <groupId>io.quarkus</groupId>
        <artifactId>quarkus-rest-client</artifactId>
    </dependency>
    
    <!-- Metrics -->
    <dependency>
        <groupId>io.quarkus</groupId>
        <artifactId>quarkus-micrometer-registry-prometheus</artifactId>
    </dependency>
</dependencies>
```

**Configuration** (application.properties):
```properties
# Application
quarkus.application.name=quarkus-ai-agent
quarkus.http.port=8080

# vLLM (Stage 1 Mistral)
vllm.url=https://mistral-24b-quantized-private-ai-demo.apps.cluster-n8cnx.n8cnx.sandbox2830.opentlc.com/v1
vllm.model-id=mistral-24b-quantized
vllm.api-key=dummy

# ToolHive MCP Servers (auto-discovered via ToolHive)
toolhive.namespace=private-ai-demo
mcp.kubernetes.service=kubernetes-mcp.private-ai-demo.svc:8080
mcp.slack.service=slack-mcp.private-ai-demo.svc:8080
mcp.database.service=database-mcp.private-ai-demo.svc:8080
mcp.calendar.service=calendar-mcp.private-ai-demo.svc:8080
mcp.email.service=email-mcp.private-ai-demo.svc:8080

# Agent settings
agent.max-iterations=10
agent.timeout-seconds=30

# Metrics
quarkus.micrometer.export.prometheus.enabled=true
```

**REST API** (AgentResource.java):
```java
@Path("/api/agent")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class AgentResource {
    
    @Inject
    AgentService agentService;
    
    @POST
    @Path("/chat")
    public Response chat(ChatRequest request) {
        try {
            String response = agentService.processQuery(request.getMessage());
            return Response.ok(new ChatResponse(response)).build();
        } catch (Exception e) {
            return Response.serverError()
                .entity(Map.of("error", e.getMessage()))
                .build();
        }
    }
    
    @GET
    @Path("/tools")
    public Response listTools() {
        List<String> tools = agentService.getAvailableTools();
        return Response.ok(Map.of("tools", tools)).build();
    }
    
    @GET
    @Path("/health")
    public Response health() {
        return Response.ok(Map.of("status", "healthy")).build();
    }
}
```

---

## 🗓️ Implementation Phases (10 Days)

### Phase 1: ToolHive Setup (Days 1-2)

**Goal**: Install ToolHive operator and deploy Kubernetes MCP

**Tasks:**
1. Log in to OpenShift cluster
2. Create `toolhive-system` namespace
3. Clone ToolHive repository
4. Install ToolHive CRDs via Helm
5. Install ToolHive operator with OpenShift values
6. Verify operator is running
7. Deploy Kubernetes MCP Server (Red Hat official)
8. Create RBAC (ServiceAccount + ClusterRoleBinding)
9. Test Kubernetes MCP with `get_pods`
10. Install MCP Inspector (optional)

**Commands:**
```bash
# Install ToolHive
oc login <cluster-url>
oc new-project toolhive-system
git clone https://github.com/stacklok/toolhive
cd toolhive
git checkout toolhive-operator-0.2.18

helm upgrade -i toolhive-operator-crds deploy/charts/operator-crds
helm upgrade -i toolhive-operator deploy/charts/operator \
  --values deploy/charts/operator/values-openshift.yaml

# Deploy Kubernetes MCP
oc apply -f stage3-enterprise-mcp/gitops/mcp-servers/kubernetes-mcp/

# Test
oc get mcpservers -n private-ai-demo
oc get pods -n private-ai-demo -l app=kubernetes-mcp
```

**Deliverables:**
- ✅ ToolHive operator running
- ✅ Kubernetes MCP server deployed
- ✅ Can query pods via MCP Inspector
- ✅ GitOps manifests committed

---

### Phase 2: Slack MCP Server (Days 3-4)

**Goal**: Deploy Slack MCP server with previous proven implementation

**Tasks:**
1. Copy previous Slack MCP code
2. Create `slack_mcp_server.py`
3. Create `Containerfile` and `requirements.txt`
4. Build container image
5. Push to `quay.io/redhat-ai-demo/slack-mcp:v1.0`
6. Create Slack webhook secret
7. Create MCPServer CR
8. Deploy via ToolHive
9. Test with MCP Inspector
10. Send test message to #mcp-demo

**Commands:**
```bash
# Build image
cd stage3-enterprise-mcp/mcp-servers/slack-mcp
podman build -t quay.io/redhat-ai-demo/slack-mcp:v1.0 .
podman push quay.io/redhat-ai-demo/slack-mcp:v1.0

# Create secret
oc create secret generic slack-webhook \
  --from-literal=webhook-url=https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  -n private-ai-demo

# Deploy
oc apply -f gitops/mcp-servers/slack-mcp/

# Test
oc get mcpserver slack-mcp -n private-ai-demo
```

**Deliverables:**
- ✅ Slack MCP container built and pushed
- ✅ Slack MCP deployed via ToolHive
- ✅ Test message sent successfully
- ✅ GitOps manifests committed

---

### Phase 3: Database, Calendar, Email MCPs (Day 5)

**Goal**: Deploy remaining custom MCP servers

**Tasks:**
1. Build Database MCP (SQLite mock data)
2. Build Calendar MCP (in-memory mock)
3. Build Email MCP (console logging)
4. Build and push all container images
5. Create MCPServer CRs for each
6. Deploy via ToolHive
7. Test each server individually

**Deliverables:**
- ✅ All 5 MCP servers deployed
- ✅ All healthy and passing readiness probes
- ✅ Can call each via MCP Inspector

---

### Phase 4: Quarkus Agent - Foundation (Days 6-7)

**Goal**: Create Quarkus agent with LangChain4j + vLLM integration

**Tasks:**
1. Create Quarkus project: `quarkus create app redhat-ai-demo:quarkus-agent`
2. Add LangChain4j dependencies
3. Configure vLLM endpoint (Stage 1 Mistral)
4. Create `AgentResource` (REST API)
5. Create `AgentService` (business logic)
6. Create `McpClientService` (MCP communication)
7. Test LLM connectivity
8. Test calling one MCP server (Kubernetes MCP)
9. Deploy to OpenShift (JVM mode first)
10. Create Route for external access

**Deliverables:**
- ✅ Quarkus app deployed (JVM mode)
- ✅ Can call vLLM for reasoning
- ✅ Can call Kubernetes MCP tools
- ✅ Simple demo working: "What pods are running?"

---

### Phase 5: Multi-Tool Orchestration (Days 8-9)

**Goal**: Implement complex workflows with multiple MCP servers

**Tasks:**
1. Integrate all 5 MCP servers into agent
2. Implement LangChain4j tool orchestration
3. Add conversation memory
4. Create demo scenarios:
   - Simple: "What is equipment ABC123?"
   - Complex: "Schedule maintenance for ABC123 next Tuesday and notify the team"
5. Test multi-step workflows
6. Add error handling and retries
7. Add logging and observability

**Deliverables:**
- ✅ Agent can orchestrate across all 5 MCPs
- ✅ Complex workflow demo working
- ✅ Slack notifications working
- ✅ End-to-end demo ready

---

### Phase 6: Native Compilation & Production (Day 10)

**Goal**: Build GraalVM native image and finalize for production

**Tasks:**
1. Configure native compilation in `pom.xml`
2. Add reflection configuration (if needed)
3. Build native image: `./mvnw package -Pnative`
4. Build native container image
5. Deploy native version to OpenShift
6. Benchmark performance:
   - Startup time (target: <1s)
   - Memory usage (target: <50MB)
   - Response time (target: <3s)
7. Add Prometheus metrics
8. Configure horizontal pod autoscaling
9. Finalize GitOps manifests
10. Write documentation

**Deliverables:**
- ✅ Native image deployed
- ✅ Performance targets met
- ✅ Metrics exposed
- ✅ HPA configured
- ✅ Production ready

---

## 🎬 Demo Flow (30 minutes)

### 1. Introduction (3 min)

**Show ToolHive Architecture:**
> "Red Hat uses **ToolHive** - the official Kubernetes operator for MCP servers. This isn't a custom solution - this is production infrastructure."

```bash
oc get mcpservers -n private-ai-demo
```

Expected:
```
NAME             TYPE      STATUS   AGE
kubernetes-mcp   k8s       Ready    2d    ← Red Hat official
slack-mcp        custom    Ready    1d
database-mcp     custom    Ready    1d
calendar-mcp     custom    Ready    1d
email-mcp        custom    Ready    1d
```

---

### 2. Kubernetes MCP Demo (5 min) ⭐

**Query**: "What pods are running in private-ai-demo namespace?"

**Show Agent Logic:**
1. LLM reasoning: "User wants pod list, use Kubernetes MCP `get_pods` tool"
2. Agent calls ToolHive-managed Kubernetes MCP
3. Returns formatted pod list with status

**Talking Point:**
> "This is Red Hat's official Kubernetes MCP server. The AI has full cluster visibility. In production, this enables:
> - Autonomous troubleshooting
> - Predictive scaling
> - Self-healing workflows
> - Compliance monitoring"

---

### 3. Slack Integration Demo (5 min) 💬

**Query**: "Alert the team about equipment ABC123 maintenance completion"

**Show Slack MCP:**
1. Agent decides to use Slack MCP
2. Formats equipment alert
3. Sends to #mcp-demo channel
4. Show live Slack message!

**Show in Slack:**
```
🚨 EQUIPMENT ALERT
Equipment: ABC123
Status: Maintenance Complete
Impact: Production can resume
Reported: 2025-10-08 15:30:00 UTC
```

**Talking Point:**
> "This is real Slack integration via MCP. Previous demos had 'Send to Slack' buttons. Now? Just ask the AI. It understands intent and takes action."

---

### 4. Complex Workflow Demo (10 min) 🚀

**Query**: "Schedule preventive maintenance for equipment ABC123 next Tuesday afternoon and notify the customer"

**Show Multi-MCP Orchestration:**

```
🤔 Agent Planning Workflow...

Step 1: Query equipment details
  └─ MCP: database-mcp → tool: query_equipment
  └─ Result: ABC123 (L-900 EUV Scanner, Customer: ACME Semiconductor)

Step 2: Check parts inventory
  └─ MCP: database-mcp → tool: query_parts_inventory
  └─ Result: DFO Module available (3 in stock)

Step 3: Find available technician
  └─ MCP: calendar-mcp → tool: check_availability
  └─ Result: TECH-007 (John Smith) free Tue 2pm-5pm

Step 4: Book appointment
  └─ MCP: calendar-mcp → tool: schedule_appointment
  └─ Result: Appointment booked Tue Oct 15, 2pm-4pm

Step 5: Send customer email
  └─ MCP: email-mcp → tool: send_email
  └─ Result: Email sent to customer@acme.com

Step 6: Send Slack notification
  └─ MCP: slack-mcp → tool: send_maintenance_plan
  └─ Result: Notification sent to #mcp-demo

✅ Workflow Complete! (6 steps, 5 MCP servers, 4.2 seconds)
```

**Show Results:**
1. Appointment in calendar
2. Email sent (log)
3. Slack message posted

**Talking Point:**
> "**This is where AI becomes infrastructure:**
> 
> **6 system calls** across 5 different backends:
> - Database (on-premise PostgreSQL) → 2 calls
> - Calendar (cloud Google Calendar) → 2 calls
> - Email (on-premise SMTP) → 1 call
> - Slack (SaaS) → 1 call
> 
> **Red Hat AI Pillar 3**: MCP servers run wherever systems live. No forced migration.
> 
> **Red Hat AI Pillar 4**: AI that acts, not just answers. Autonomous workflows.
> 
> **Business Impact:**
> - **95% time reduction** (15 minutes → 30 seconds)
> - **Zero data entry errors**
> - **Complete audit trail**
> - **Scales to 1000s of requests/day**"

---

### 5. ToolHive Benefits (5 min)

**Show ToolHive Operator Features:**

**1. Declarative Management**
```yaml
# Just apply MCPServer CRs
oc apply -f mcpserver-slack.yaml
# ToolHive handles: deployment, service, health checks, RBAC
```

**2. Auto-Scaling**
```bash
oc patch mcpserver database-mcp --type=merge \
  -p '{"spec":{"replicas":3}}'
# ToolHive scales pods automatically
```

**3. Easy Updates**
```bash
oc patch mcpserver slack-mcp --type=merge \
  -p '{"spec":{"image":"quay.io/redhat-ai-demo/slack-mcp:v2.0"}}'
# ToolHive handles rolling update
```

**4. Built-in Observability**
```bash
oc describe mcpserver slack-mcp
```
Shows:
- Health status
- Request count
- Average latency
- Error rate

**Talking Point:**
> "ToolHive is production infrastructure:
> - **Red Hat supported** - Official deployment method
> - **Kubernetes-native** - CRDs, operators, GitOps
> - **Observable** - Built-in metrics
> - **Secure** - ServiceAccounts + RBAC
> - **Scalable** - Horizontal pod autoscaling
> 
> This isn't a demo hack. This is how you deploy MCP servers at scale."

---

### 6. Quarkus Native Benefits (2 min)

**Show Performance Metrics:**

| Metric | JVM Mode | Native Mode | Improvement |
|--------|----------|-------------|-------------|
| Startup Time | 2.3s | 0.08s | **29x faster** |
| Memory (RSS) | 380MB | 45MB | **8x less** |
| Container Size | 420MB | 160MB | **2.6x smaller** |

**Talking Point:**
> "Quarkus native compilation with GraalVM:
> - **Sub-second startup** - Serverless-ready
> - **Minimal memory** - Cost-effective at scale
> - **Enterprise Java** - Developers already know it
> - **Production-ready** - Red Hat supported"

---

## 📊 Success Criteria

| Criteria | Target | Status |
|----------|--------|--------|
| **ToolHive Deployed** | ✅ | Operator + CRDs |
| **Kubernetes MCP** | ✅ | Red Hat Official |
| **Slack MCP** | ✅ | Custom, proven code |
| **Database MCP** | ✅ | Custom with SQLite |
| **Calendar MCP** | ✅ | Custom, mock |
| **Email MCP** | ✅ | Custom, mock/SMTP |
| **Quarkus Agent** | ✅ | LangChain4j + Native |
| **Multi-Tool Workflow** | ✅ | 6-step demo |
| **Startup Time** | <1s | Native Image |
| **Memory** | <50MB | Native Image |
| **Response Time** | <3s | End-to-end |
| **GitOps** | 100% | All in Git |

---

## 📁 GitOps Structure

```
gitops/
├── components/
│   ├── toolhive/
│   │   ├── namespace.yaml
│   │   ├── helm-values-openshift.yaml
│   │   └── kustomization.yaml
│   │
│   ├── mcp-servers/
│   │   ├── kubernetes-mcp/          # Red Hat official
│   │   │   ├── mcpserver.yaml
│   │   │   ├── serviceaccount.yaml
│   │   │   ├── rbac.yaml
│   │   │   └── kustomization.yaml
│   │   │
│   │   ├── slack-mcp/               # Custom (proven)
│   │   │   ├── mcpserver.yaml
│   │   │   ├── secret.yaml
│   │   │   └── kustomization.yaml
│   │   │
│   │   ├── database-mcp/
│   │   │   ├── mcpserver.yaml
│   │   │   ├── configmap.yaml       # Mock data
│   │   │   └── kustomization.yaml
│   │   │
│   │   ├── calendar-mcp/
│   │   │   ├── mcpserver.yaml
│   │   │   └── kustomization.yaml
│   │   │
│   │   └── email-mcp/
│   │       ├── mcpserver.yaml
│   │       ├── secret.yaml
│   │       └── kustomization.yaml
│   │
│   └── quarkus-agent/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── route.yaml
│       ├── configmap.yaml
│       └── kustomization.yaml
│
└── overlays/
    └── stage3-enterprise-mcp/
        ├── kustomization.yaml
        └── README.md
```

---

## 🚀 Quick Start

### 1. Install ToolHive

```bash
cd stage3-enterprise-mcp
./scripts/01-install-toolhive.sh
```

### 2. Deploy MCP Servers

```bash
./scripts/02-deploy-mcp-servers.sh
```

### 3. Deploy Quarkus Agent

```bash
./scripts/03-deploy-quarkus-agent.sh
```

### 4. Test Demo

```bash
./scripts/04-test-demo.sh
```

---

## 📚 References

### Red Hat Official
- [ToolHive Deployment Guide](https://developers.redhat.com/articles/2025/10/01/how-deploy-mcp-servers-openshift-using-toolhive)
- [Kubernetes MCP Server](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management)
- [Red Hat Demo Platform](https://connect.redhat.com/en/partner-program/benefits/demo-platform)

### ToolHive
- [GitHub: stacklok/toolhive](https://github.com/stacklok/toolhive)
- [Helm Charts](https://github.com/stacklok/toolhive/tree/main/deploy/charts)
- [Examples](https://github.com/stacklok/toolhive/tree/main/examples/operator/mcp-servers)

### MCP Protocol
- [Official Site](https://modelcontextprotocol.io)
- [MCP Servers](https://github.com/modelcontextprotocol/servers)
- [MCP Inspector](https://github.com/modelcontextprotocol/inspector)

### Quarkus + LangChain4j
- [Quarkus](https://quarkus.io)
- [LangChain4j](https://docs.langchain4j.dev)
- [Quarkus AI Examples](https://github.com/quarkusio/quarkus-langchain4j-examples)

---

**Next Step**: Start Phase 1 - Install ToolHive! 🚀


