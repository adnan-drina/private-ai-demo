# Red Hat Official MCP Server Alignment

**Date**: October 8, 2025  
**Status**: Aligned with Red Hat's Official MCP Deployment Method  
**Reference**: [How to deploy MCP servers on OpenShift using ToolHive](https://developers.redhat.com/articles/2025/10/01/how-deploy-mcp-servers-openshift-using-toolhive)

---

## 🎯 Red Hat's Official Approach: ToolHive

Red Hat recommends using **ToolHive** - a Kubernetes operator that simplifies deploying and managing MCP servers on OpenShift.

### Why ToolHive?

**From Red Hat Documentation:**
> "ToolHive provides a Kubernetes-native way to deploy, manage, and scale Model Context Protocol (MCP) servers. It handles the complexity of container orchestration, service discovery, and lifecycle management, allowing developers to focus on building AI agents rather than infrastructure."

**Key Benefits:**
- ✅ Kubernetes-native (CRDs + Operator pattern)
- ✅ Automatic service discovery
- ✅ Built-in security (RBAC, ServiceAccounts)
- ✅ Scales with OpenShift
- ✅ GitOps compatible

---

## 📦 ToolHive Architecture

```
┌─────────────────────────────────────────────────────────┐
│           OpenShift AI / OpenShift Cluster              │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │         ToolHive Operator (Helm Chart)             │ │
│  │  • Watches MCPServer CRDs                          │ │
│  │  • Creates Deployments, Services, ConfigMaps       │ │
│  │  • Manages MCP server lifecycle                    │ │
│  └──────────────────┬─────────────────────────────────┘ │
│                     │                                    │
│         ┌───────────┴───────────┬───────────┐           │
│         │                       │           │           │
│         ↓                       ↓           ↓           │
│  ┌─────────────┐         ┌─────────────┐  ┌─────────────┐
│  │ MCPServer   │         │ MCPServer   │  │ MCPServer   │
│  │   (CRD)     │         │   (CRD)     │  │   (CRD)     │
│  │             │         │             │  │             │
│  │ Name: fetch │         │ Name: k8s   │  │ Name: github│
│  │ Type: fetch │         │ Type: k8s   │  │ Type: github│
│  └─────────────┘         └─────────────┘  └─────────────┘
│         │                       │                 │       │
│         ↓                       ↓                 ↓       │
│  ┌─────────────┐         ┌─────────────┐  ┌─────────────┐
│  │  MCP Fetch  │         │  MCP K8s    │  │ MCP GitHub  │
│  │  Server Pod │         │ Server Pod  │  │  Server Pod │
│  └─────────────┘         └─────────────┘  └─────────────┘
│         │                       │                 │       │
└─────────┼───────────────────────┼─────────────────┼───────┘
          │                       │                 │
          ↓                       ↓                 ↓
   [Web Fetch]            [Kubernetes API]    [GitHub API]
```

---

## 🚀 Deployment Steps (Red Hat Official)

### Step 1: Prerequisites

```bash
# Ensure you have:
# - OpenShift cluster access (cluster-admin for CRD installation)
# - oc CLI installed
# - Helm 3.x installed
# - MCP Inspector (optional, for testing)
```

### Step 2: Install ToolHive Operator

```bash
# Log in to OpenShift
oc login <cluster-url>

# Create ToolHive namespace
oc new-project toolhive-system

# Clone ToolHive repository
git clone https://github.com/stacklok/toolhive
cd toolhive
git checkout toolhive-operator-0.2.18  # Use specific version

# Install CRDs
helm upgrade -i toolhive-operator-crds \
  deploy/charts/operator-crds

# Install Operator (OpenShift-specific values)
helm upgrade -i toolhive-operator \
  deploy/charts/operator \
  --values deploy/charts/operator/values-openshift.yaml
```

### Step 3: Verify Installation

```bash
# Check operator is running
oc get pods -n toolhive-system

# Expected output:
# NAME                                 READY   STATUS    RESTARTS   AGE
# toolhive-operator-<hash>             1/1     Running   0          1m

# Verify CRDs are installed
oc get crds | grep mcpserver
# Expected: mcpservers.mcp.stacklok.io
```

### Step 4: Deploy MCP Servers

**Option A: Use ToolHive Examples**

```bash
# Fetch MCP Server (web scraping)
oc create -f examples/operator/mcp-servers/mcpserver_fetch.yaml

# Kubernetes MCP Server (cluster management)
oc create -f examples/operator/mcp-servers/mcpserver_k8s.yaml

# GitHub MCP Server (repository operations)
oc create -f examples/operator/mcp-servers/mcpserver_github.yaml
```

**Option B: Create Custom MCPServer CRs**

```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: database-mcp
  namespace: private-ai-demo
spec:
  serverType: custom
  image: quay.io/your-org/database-mcp:latest
  port: 8080
  env:
  - name: DATABASE_URL
    value: "postgresql://postgres:5432/equipment"
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

### Step 5: Expose Services

```bash
# Expose MCP server for external access
oc expose service mcp-fetch-proxy -n private-ai-demo

# Get route
oc get route mcp-fetch-proxy -n private-ai-demo
```

### Step 6: Test with MCP Inspector

```bash
# Launch MCP Inspector (optional)
npx @modelcontextprotocol/inspector

# Connect to: http://<route-url>
```

---

## 📋 Red Hat Official MCP Servers

### 1. Kubernetes MCP Server ⭐ Red Hat Developed

**Purpose**: AI-powered Kubernetes cluster management

**Source**: [developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management)

**Capabilities:**
- `get_pods` - List pods in namespace
- `get_services` - List services
- `get_deployments` - List deployments
- `describe_pod` - Get detailed pod information
- `get_logs` - Fetch pod logs
- `scale_deployment` - Scale replicas up/down
- `get_events` - Get cluster events

**Deployment:**
```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: kubernetes-mcp
  namespace: private-ai-demo
spec:
  serverType: k8s
  serviceAccount: mcp-k8s-reader  # RBAC required
  rbac:
    clusterRole: view  # Or custom role
```

**Use Cases:**
- AI agents that manage OpenShift workloads
- Autonomous troubleshooting
- Cluster health monitoring
- Automated scaling decisions

---

### 2. Official MCP Servers (Stacklok/Anthropic)

**Available via ToolHive:**

#### Fetch MCP Server
- **Purpose**: Web scraping and HTML fetching
- **Tools**: `fetch_url`, `fetch_html`, `extract_text`
- **Use Case**: AI agents that need web content

#### GitHub MCP Server
- **Purpose**: Repository operations
- **Tools**: `list_repos`, `get_file`, `create_pr`, `search_code`
- **Use Case**: AI-powered DevOps assistants

#### Filesystem MCP Server
- **Purpose**: File operations
- **Tools**: `read_file`, `write_file`, `list_dir`, `search_files`
- **Use Case**: AI agents that work with local files

#### Brave Search MCP Server
- **Purpose**: Web search
- **Tools**: `search_web`, `get_snippets`
- **Use Case**: AI agents that need real-time information

---

## 🔧 Custom MCP Servers for Our Demo

Following Red Hat's ToolHive pattern, we'll create custom MCP servers:

### Database MCP Server

**MCPServer CR:**
```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: database-mcp
  namespace: private-ai-demo
  labels:
    app: database-mcp
    use-case: field-service
spec:
  serverType: custom
  image: quay.io/redhat-ai-demo/database-mcp:v1.0
  port: 8080
  env:
  - name: DATABASE_TYPE
    value: "postgresql"
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: database-credentials
        key: url
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

**Container Image** (Python Flask):
```python
# database_mcp_server.py
from flask import Flask, request, jsonify
import psycopg2
import os

app = Flask(__name__)

# MCP protocol endpoint
@app.route('/tools', methods=['GET'])
def list_tools():
    """Return available tools (MCP protocol)"""
    return jsonify({
        "tools": [
            {
                "name": "query_equipment",
                "description": "Get equipment details by ID",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "equipment_id": {"type": "string"}
                    },
                    "required": ["equipment_id"]
                }
            },
            # ... more tools
        ]
    })

@app.route('/execute', methods=['POST'])
def execute_tool():
    """Execute a tool (MCP protocol)"""
    data = request.json
    tool = data.get('tool')
    params = data.get('parameters', {})
    
    # Execute tool logic
    if tool == 'query_equipment':
        result = query_equipment_from_db(params['equipment_id'])
    else:
        result = {"error": "Unknown tool"}
    
    return jsonify({"result": result})

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

@app.route('/ready', methods=['GET'])
def ready():
    # Check database connection
    try:
        conn = psycopg2.connect(os.getenv('DATABASE_URL'))
        conn.close()
        return jsonify({"status": "ready"})
    except:
        return jsonify({"status": "not_ready"}), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

**Containerfile:**
```dockerfile
FROM registry.access.redhat.com/ubi9/python-39:latest

WORKDIR /app

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY database_mcp_server.py .

# Non-root user
USER 1001

EXPOSE 8080

CMD ["python", "database_mcp_server.py"]
```

---

### Calendar MCP Server

Similar structure, but for calendar operations:

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
    value: "google"  # or "mock"
  - name: GOOGLE_CALENDAR_CREDENTIALS
    valueFrom:
      secretKeyRef:
        name: calendar-credentials
        key: credentials.json
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
```

---

### Email MCP Server

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

---

### CRM MCP Server

```yaml
apiVersion: mcp.stacklok.io/v1alpha1
kind: MCPServer
metadata:
  name: crm-mcp
  namespace: private-ai-demo
spec:
  serverType: custom
  image: quay.io/redhat-ai-demo/crm-mcp:v1.0
  port: 8080
  env:
  - name: CRM_PROVIDER
    value: "salesforce"  # or "mock"
  - name: SALESFORCE_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: crm-credentials
        key: api_token
```

---

## 🎯 Updated Implementation Plan

### Phase 1: ToolHive Setup (Days 1-2)

**Tasks:**
1. Install ToolHive operator on OpenShift
2. Verify CRDs are installed
3. Deploy Kubernetes MCP Server (Red Hat official)
4. Test with MCP Inspector
5. Create project structure for custom MCPs

**Deliverables:**
- ✅ ToolHive operator running
- ✅ Kubernetes MCP server deployed
- ✅ Can query pods/services via MCP

---

### Phase 2: Custom MCP Servers (Days 3-5)

**Tasks:**
1. Build Database MCP server (Python Flask)
2. Build Calendar MCP server
3. Build Email MCP server
4. Build CRM MCP server
5. Create MCPServer CRs for each
6. Deploy via ToolHive
7. Test each server individually

**Deliverables:**
- ✅ 4 custom MCP servers deployed
- ✅ All MCPServer CRs in GitOps
- ✅ Health checks passing

---

### Phase 3: Quarkus AI Agent (Days 6-7)

**Tasks:**
1. Create Quarkus project with LangChain4j
2. Integrate with vLLM (Stage 1 Mistral)
3. Create MCP client to communicate with ToolHive servers
4. Implement agent logic (tool selection, orchestration)
5. Add REST API endpoints
6. Deploy to OpenShift

**Deliverables:**
- ✅ Quarkus agent deployed
- ✅ Can call all MCP servers
- ✅ Simple demo working

---

### Phase 4: Complex Workflows (Days 8-9)

**Tasks:**
1. Implement multi-step workflow orchestration
2. Add conversation memory
3. Add error handling and retries
4. Create demo scenarios:
   - Simple query: "What is equipment ABC123?"
   - Complex workflow: "Schedule maintenance for ABC123"
5. Test end-to-end

**Deliverables:**
- ✅ Complex workflows working
- ✅ Agent makes autonomous decisions
- ✅ Demo ready

---

### Phase 5: Native Compilation & Polish (Day 10)

**Tasks:**
1. Build GraalVM native image
2. Deploy native version
3. Benchmark performance
4. Add Prometheus metrics
5. Finalize GitOps manifests
6. Write documentation

**Deliverables:**
- ✅ Native image deployed
- ✅ Performance targets met
- ✅ Production ready

---

## 📊 Comparison: Custom vs ToolHive Approach

| Aspect | Previous Plan (Custom) | New Plan (ToolHive) | Winner |
|--------|----------------------|-------------------|--------|
| **Deployment** | Manual K8s manifests | MCPServer CRDs | ✅ ToolHive |
| **Lifecycle** | Manual scaling, updates | Operator-managed | ✅ ToolHive |
| **Discovery** | Manual service URLs | Auto-discovery | ✅ ToolHive |
| **Standards** | Custom REST API | MCP protocol | ✅ ToolHive |
| **Ecosystem** | Isolated | Use official MCP servers | ✅ ToolHive |
| **Red Hat Alignment** | None | Official method | ✅ ToolHive |
| **Complexity** | Lower (DIY) | Higher (operator) | ⚖️ Tradeoff |
| **Time to Demo** | Faster | Slightly slower | ⚖️ Tradeoff |

**Verdict**: Use ToolHive for production-aligned demos

---

## 🚀 GitOps Structure (ToolHive-based)

```
gitops/
├── components/
│   ├── toolhive/                      # NEW: ToolHive operator
│   │   ├── namespace.yaml
│   │   ├── helm-values.yaml           # OpenShift-specific values
│   │   └── kustomization.yaml
│   │
│   ├── mcp-servers/                   # Custom MCP servers
│   │   ├── database-mcp/
│   │   │   ├── mcpserver.yaml         # MCPServer CR
│   │   │   ├── configmap.yaml         # Mock data
│   │   │   ├── secret.yaml            # DB credentials
│   │   │   └── kustomization.yaml
│   │   ├── calendar-mcp/
│   │   │   ├── mcpserver.yaml
│   │   │   ├── secret.yaml
│   │   │   └── kustomization.yaml
│   │   ├── email-mcp/
│   │   │   ├── mcpserver.yaml
│   │   │   ├── secret.yaml
│   │   │   └── kustomization.yaml
│   │   ├── crm-mcp/
│   │   │   ├── mcpserver.yaml
│   │   │   ├── secret.yaml
│   │   │   └── kustomization.yaml
│   │   └── official-mcp-servers/      # Optional: official servers
│   │       ├── kubernetes-mcp.yaml    # Red Hat K8s MCP
│   │       ├── github-mcp.yaml
│   │       └── fetch-mcp.yaml
│   │
│   └── quarkus-agent/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── route.yaml
│       ├── serviceaccount.yaml
│       ├── rbac.yaml                  # Access to MCP servers
│       └── kustomization.yaml
│
└── overlays/
    └── stage3-enterprise-mcp/
        ├── kustomization.yaml
        └── README.md
```

---

## 🎬 Demo Flow (Updated)

### 1. Introduction (3 minutes)

**Show ToolHive Architecture:**
> "Red Hat's approach to MCP servers uses **ToolHive** - a Kubernetes operator that brings the Model Context Protocol to OpenShift. This is production-grade infrastructure, not a custom solution."

**Show MCPServer CRDs:**
```bash
oc get mcpservers -n private-ai-demo
```

Expected output:
```
NAME            TYPE      STATUS    AGE
kubernetes-mcp  k8s       Ready     2d
database-mcp    custom    Ready     1d
calendar-mcp    custom    Ready     1d
email-mcp       custom    Ready     1d
crm-mcp         custom    Ready     1d
```

---

### 2. Kubernetes MCP Demo (5 minutes)

**Show Red Hat's Kubernetes MCP Server:**

**Query**: "What pods are running in the private-ai-demo namespace?"

**Agent Execution:**
1. Calls Kubernetes MCP → `get_pods("private-ai-demo")`
2. Returns pod list with status

**Response:**
> "I found 8 pods running in private-ai-demo:
> - mistral-24b-quantized-predictor: Running (3/3 containers)
> - rag-stack: Running (1/1 containers)
> - milvus-standalone: Running (1/1 containers)
> - database-mcp: Running (1/1 containers)
> - calendar-mcp: Running (1/1 containers)
> - email-mcp: Running (1/1 containers)
> - crm-mcp: Running (1/1 containers)
> - quarkus-agent: Running (1/1 containers)"

**Talking Point:**
> "This is Red Hat's official Kubernetes MCP server. The AI agent has full visibility into cluster state. In production, this enables autonomous troubleshooting, auto-scaling, and self-healing workflows."

---

### 3. Field Service Workflow (10 minutes)

**Query**: "Schedule maintenance for equipment ABC123 next Tuesday afternoon"

**Show ToolHive Service Discovery:**
> "The agent doesn't hardcode service URLs. ToolHive provides automatic service discovery. The agent queries ToolHive for available MCP servers and their capabilities."

**Agent Execution (multi-MCP):**
1. Query equipment (Database MCP via ToolHive)
2. Check availability (Calendar MCP via ToolHive)
3. Book appointment (Calendar MCP)
4. Send email (Email MCP via ToolHive)
5. Create ticket (CRM MCP via ToolHive)

**Show ToolHive Metrics:**
```bash
oc get mcpserver database-mcp -o yaml | grep -A 5 "status:"
```

```yaml
status:
  ready: true
  lastHeartbeat: "2025-10-08T15:00:00Z"
  requestsHandled: 1247
  averageLatency: "45ms"
```

---

### 4. Production Benefits (5 minutes)

**Show ToolHive Operator Benefits:**

1. **Automatic Scaling:**
```yaml
spec:
  replicas: 3  # ToolHive manages autoscaling
```

2. **Health Monitoring:**
```bash
oc describe mcpserver database-mcp
```

3. **Easy Updates:**
```bash
# Change image version
oc patch mcpserver database-mcp --type=merge \
  -p '{"spec":{"image":"quay.io/redhat-ai-demo/database-mcp:v2.0"}}'
```

4. **RBAC Integration:**
```yaml
spec:
  serviceAccount: database-mcp-sa
  rbac:
    role: database-reader
```

**Talking Points:**
> "This is production infrastructure:
> - **Red Hat supported** - ToolHive is the official method
> - **Kubernetes-native** - CRDs, operators, RBAC
> - **Scalable** - ToolHive manages replicas
> - **Observable** - Built-in metrics
> - **Secure** - ServiceAccounts + RBAC
> - **GitOps ready** - All configuration in Git
>
> This isn't a demo hack. This is how you deploy MCP servers in production OpenShift environments."

---

## ✅ Success Criteria

| Criteria | Target | Red Hat Alignment |
|----------|--------|------------------|
| **ToolHive Deployed** | ✅ | 100% Official Method |
| **MCPServer CRDs** | ✅ | 100% Standard |
| **Kubernetes MCP** | ✅ | Red Hat Developed |
| **Custom MCPs** | 4 servers | ToolHive Managed |
| **Agent Integration** | Quarkus + LangChain4j | Red Hat Aligned |
| **GitOps** | 100% | Red Hat Best Practice |
| **Performance** | <1s startup, <50MB | Native Compilation |

---

## 📚 References

### Red Hat Official Documentation
- **ToolHive Deployment Guide**: [developers.redhat.com/articles/2025/10/01/how-deploy-mcp-servers-openshift-using-toolhive](https://developers.redhat.com/articles/2025/10/01/how-deploy-mcp-servers-openshift-using-toolhive)
- **Kubernetes MCP Server**: [developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management)
- **Red Hat Demo Platform**: [connect.redhat.com/en/partner-program/benefits/demo-platform](https://connect.redhat.com/en/partner-program/benefits/demo-platform)

### ToolHive Resources
- **GitHub Repository**: [github.com/stacklok/toolhive](https://github.com/stacklok/toolhive)
- **MCP Server Examples**: [github.com/stacklok/toolhive/tree/main/examples/operator/mcp-servers](https://github.com/stacklok/toolhive/tree/main/examples/operator/mcp-servers)
- **Helm Charts**: [github.com/stacklok/toolhive/tree/main/deploy/charts](https://github.com/stacklok/toolhive/tree/main/deploy/charts)

### Model Context Protocol
- **Official Site**: [modelcontextprotocol.io](https://modelcontextprotocol.io)
- **Official MCP Servers**: [github.com/modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers)
- **MCP Inspector**: [github.com/modelcontextprotocol/inspector](https://github.com/modelcontextprotocol/inspector)

---

**Next Step**: Install ToolHive operator and deploy Kubernetes MCP server! 🚀


