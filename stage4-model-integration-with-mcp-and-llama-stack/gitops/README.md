# GitOps Manifests

Kubernetes manifests for deploying ACME LithoOps Agent infrastructure.

---

## 📁 Directory Structure

```
gitops/
├── README.md              # This file
├── database/              # PostgreSQL deployment
│   ├── postgresql-deployment.yaml    # PostgreSQL StatefulSet/Deployment
│   └── init-schema.sql               # Database schema and initial data
├── mcp-servers/           # Model Context Protocol servers
│   ├── database-mcp/      # Database MCP Server
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── slack-mcp/         # Slack MCP Server
│       ├── deployment.yaml
│       └── service.yaml
└── acme-agent/            # Legacy - ACME Agent manifests moved to acme-lithoops-agent/deploy/
    ├── deployment.yaml
    ├── service.yaml
    ├── route.yaml
    └── ...
```

**Note:** ACME Agent manifests are now in `acme-lithoops-agent/deploy/` for better project organization.

---

## 🗄️ Database (`database/`)

### `postgresql-deployment.yaml`
Complete PostgreSQL deployment including:
- **Deployment**: PostgreSQL 15 with persistent storage
- **Service**: Internal cluster service
- **Secret**: `postgresql-credentials` (auto-created)
- **PVC**: 1Gi persistent volume for data

**Apply:**
```bash
oc apply -f gitops/database/postgresql-deployment.yaml
```

### `init-schema.sql`
Database schema and initial data:
- **equipment** table (4 lithography tools)
- **service_history** table (calibration records)
- **parts_inventory** table (spare parts catalog)
- **calibration_records** table (historical calibrations)

**Load schema:**
```bash
POD=$(oc get pod -l app=postgresql -n private-ai-demo -o jsonpath='{.items[0].metadata.name}')
cat gitops/database/init-schema.sql | oc exec -i -n private-ai-demo $POD -- \
  bash -c "PGPASSWORD=acme_secure_2025 psql -U acmeadmin -d acme_equipment"
```

---

## 🔌 MCP Servers (`mcp-servers/`)

### Database MCP (`database-mcp/`)

**Purpose:** Provides equipment data queries via MCP protocol

**Tools:**
- `query_equipment` - Get equipment details
- `query_service_history` - Get maintenance records
- `query_parts_inventory` - Check spare parts availability

**deployment.yaml**
- Image: Built from `mcp-servers/database-mcp/`
- Port: 8080
- Environment: PostgreSQL connection details (from Secret)
- Health checks: `/health` endpoint

**service.yaml**
- Type: ClusterIP
- Port: 8080
- Selector: `app: database-mcp`

**Apply:**
```bash
oc apply -f gitops/mcp-servers/database-mcp/deployment.yaml
oc apply -f gitops/mcp-servers/database-mcp/service.yaml
```

---

### Slack MCP (`slack-mcp/`)

**Purpose:** Sends notifications and alerts to Slack

**Tools:**
- `send_slack_message` - Simple text message
- `send_equipment_alert` - Formatted equipment alert
- `send_maintenance_plan` - Maintenance plan notification

**deployment.yaml**
- Image: Built from `mcp-servers/slack-mcp/`
- Port: 8080
- Environment: Slack webhook URL (from Secret, optional)
- Health checks: `/health` endpoint
- **Demo Mode:** Runs without webhook (console logging)

**service.yaml**
- Type: ClusterIP
- Port: 8080
- Selector: `app: slack-mcp`

**Apply:**
```bash
# Optional: Create Slack webhook secret first
oc create secret generic slack-webhook \
  --from-literal=webhook-url="https://hooks.slack.com/services/YOUR/WEBHOOK/URL" \
  -n private-ai-demo

# Deploy Slack MCP
oc apply -f gitops/mcp-servers/slack-mcp/deployment.yaml
oc apply -f gitops/mcp-servers/slack-mcp/service.yaml
```

---

## 🤖 ACME Agent (`acme-lithoops-agent/deploy/`)

**Note:** Manifests moved to `acme-lithoops-agent/deploy/` for better organization.

**Resources:**
- `serviceaccount.yaml` - ServiceAccount for cross-namespace access
- `role.yaml` - Role in `private-ai-demo` namespace
- `rolebinding.yaml` - Bind ServiceAccount to Role
- `deployment.yaml` - Quarkus application deployment
- `service.yaml` - ClusterIP service
- `route.yaml` - OpenShift Route for external access

**Apply:**
```bash
oc apply -f acme-lithoops-agent/deploy/serviceaccount.yaml
oc apply -f acme-lithoops-agent/deploy/role.yaml -n private-ai-demo
oc apply -f acme-lithoops-agent/deploy/rolebinding.yaml
oc apply -f acme-lithoops-agent/deploy/deployment.yaml
oc apply -f acme-lithoops-agent/deploy/service.yaml
oc apply -f acme-lithoops-agent/deploy/route.yaml
```

---

## 🔄 Deployment Order

**Important:** Deploy in this order to ensure dependencies are met:

1. **PostgreSQL**
   ```bash
   oc apply -f gitops/database/postgresql-deployment.yaml
   oc wait --for=condition=available --timeout=60s deployment/postgresql -n private-ai-demo
   ```

2. **Load Database Schema**
   ```bash
   POD=$(oc get pod -l app=postgresql -n private-ai-demo -o jsonpath='{.items[0].metadata.name}')
   cat gitops/database/init-schema.sql | oc exec -i -n private-ai-demo $POD -- \
     bash -c "PGPASSWORD=acme_secure_2025 psql -U acmeadmin -d acme_equipment"
   ```

3. **Database MCP** (depends on PostgreSQL)
   ```bash
   oc apply -f gitops/mcp-servers/database-mcp/
   ```

4. **Slack MCP** (independent)
   ```bash
   oc apply -f gitops/mcp-servers/slack-mcp/
   ```

5. **ACME Agent** (depends on MCP servers and vLLM)
   ```bash
   oc apply -f acme-lithoops-agent/deploy/
   ```

**Or use automated script:**
```bash
./deploy.sh
```

---

## 🔧 Configuration

### Environment Variables

**Database MCP:**
```yaml
env:
  - name: POSTGRES_HOST
    value: postgresql.private-ai-demo.svc.cluster.local
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

**Slack MCP:**
```yaml
env:
  - name: SLACK_WEBHOOK_URL
    valueFrom:
      secretKeyRef:
        name: slack-webhook
        key: webhook-url
        optional: true  # Allows demo mode
  - name: DEFAULT_CHANNEL
    value: '#acme-litho'
```

---

## 🔐 Required Secrets

### `postgresql-credentials` (auto-created)
```bash
oc get secret postgresql-credentials -n private-ai-demo
```

### `slack-webhook` (optional, manual)
```bash
oc create secret generic slack-webhook \
  --from-literal=webhook-url="YOUR_WEBHOOK_URL" \
  -n private-ai-demo
```

See [SECRETS.md](../SECRETS.md) for complete documentation.

---

## 🧪 Testing

### Test Database MCP
```bash
oc run test-db-mcp --image=registry.access.redhat.com/ubi9/ubi-minimal:latest --rm -i --restart=Never -n private-ai-demo -- \
  curl -s http://database-mcp:8080/execute \
  -H "Content-Type: application/json" \
  -d '{"tool":"query_equipment","parameters":{"equipment_id":"LITHO-001"}}'
```

### Test Slack MCP
```bash
oc run test-slack-mcp --image=registry.access.redhat.com/ubi9/ubi-minimal:latest --rm -i --restart=Never -n private-ai-demo -- \
  curl -s http://slack-mcp:8080/execute \
  -H "Content-Type: application/json" \
  -d '{"tool":"send_slack_message","parameters":{"message":"Test from GitOps","channel":"#acme-litho"}}'
```

---

## 📊 Resource Requirements

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| PostgreSQL | 100m | 128Mi | 500m | 512Mi |
| Database MCP | 100m | 128Mi | 500m | 512Mi |
| Slack MCP | 100m | 128Mi | 500m | 512Mi |
| ACME Agent | 500m | 512Mi | 2000m | 2Gi |

**Total (minimum):** 0.8 CPU, 896Mi memory

---

## 🧹 Cleanup

```bash
# Delete ACME Agent
oc delete all,sa,role,rolebinding,route -l app=acme-agent -n acme-calibration-ops

# Delete MCP Servers
oc delete deployment,service database-mcp slack-mcp -n private-ai-demo

# Delete PostgreSQL
oc delete deployment,service,pvc,secret -l app=postgresql -n private-ai-demo
oc delete secret postgresql-credentials -n private-ai-demo

# Delete Slack webhook secret
oc delete secret slack-webhook -n private-ai-demo
```

---

## 📚 Additional Resources

- **[QUICKSTART.md](../QUICKSTART.md)** - Complete deployment guide
- **[SECRETS.md](../SECRETS.md)** - Secret management
- **[README.md](../README.md)** - Project overview

---

**Last Updated:** 2025-10-08  
**Maintainer:** ACME LithoOps Team
