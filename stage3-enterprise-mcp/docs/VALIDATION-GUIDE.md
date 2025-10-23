# Stage 3 Validation Guide - ACME LithoOps Agent

**Quick validation checklist for testing the deployed ACME agent in your environment**

---

## 🔍 Step 1: Verify Deployment

### Check all components are running

```bash
# Switch to project
oc project private-ai-demo

# Check deployments
oc get deployments -l 'component in (mcp-server,agent)'

# Expected output:
# NAME           READY   UP-TO-DATE   AVAILABLE   AGE
# acme-agent     1/1     1            1           Xm
# database-mcp   1/1     1            1           Xm
# slack-mcp      1/1     1            1           Xm

# Check pods are running
oc get pods -l 'component in (mcp-server,agent)'

# All should show STATUS: Running, READY: 1/1
```

### Get the Agent URL

```bash
# Get the external route
AGENT_URL="https://$(oc get route acme-agent -n private-ai-demo -o jsonpath='{.spec.host}')"
echo $AGENT_URL

# Should output something like:
# https://acme-agent-private-ai-demo.apps.cluster-n8cnx.n8cnx.sandbox2830.opentlc.com
```

---

## 🧪 Step 2: Health Checks

### Test Agent Health

```bash
# Health check
curl -s $AGENT_URL/health | jq

# Expected output:
# {
#   "service": "acme-agent",
#   "status": "healthy"
# }
```

### Test MCP Connectivity

```bash
# Test MCP connectivity
curl -s $AGENT_URL/ops/test | jq

# Expected output:
# {
#   "database_mcp": "✅ Reachable",
#   "slack_mcp": "✅ Reachable"
# }
```

---

## ✅ Step 3: Flow 1 - Calibration Check (Clean Data → PASS)

### Run the test

```bash
curl -X POST $AGENT_URL/ops/calibration/check \
  -H 'Content-Type: application/json' \
  -d '{
    "tool": "L-900-07",
    "product": "PX-7",
    "layer": "M1",
    "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_clean.csv",
    "slackNotify": true
  }' | jq
```

### Expected Response

```json
{
  "correlationId": "31981906-b5ae-431c-9ca3-790269dbc584",
  "verdict": "PASS",
  "actions": [],
  "citations": [
    {
      "doc": "ACME_01_ACME_DFO_Calibration_SOP_v1.9",
      "section": "§3.2 Daily Calibration",
      "page": 12
    }
  ],
  "limits": {
    "overlayUCL": 3.5,
    "doseUniformityUCL": 2.5,
    "bfTarget": 0.5,
    "bfTolerance": 0.1
  },
  "measured": {
    "maxOverlay": 3.0,
    "doseUniformity": 0.41,
    "bestFocus": 0.52,
    "vibration": 0.4,
    "sustainedOverlayViolation": false,
    "pointCount": 10
  },
  "reportPath": "./documents/scenario2/reports/CR-20251008-142241-L-900-07-PX-7-M1.txt",
  "slackMsgId": "2025-10-08T14:22:41.945352",
  "equipmentInfo": {
    "id": "L-900-07",
    "type": "L-900 EUV Scanner",
    "model": "ASML TWINSCAN NXE:3600D",
    "status": "Operational",
    "location": "Fab 3, Bay 12"
  }
}
```

### Verify Results

✅ **Check verdict**: Should be `"PASS"`  
✅ **Check overlay**: `maxOverlay: 3.0` (< 3.5 UCL) ✅  
✅ **Check actions**: Should be `[]` (empty, no actions needed)  
✅ **Check report**: `reportPath` should be present  
✅ **Check Slack**: `slackMsgId` should be present (demo mode)

---

## ❌ Step 4: Flow 2 - Calibration Check (Out-of-Spec → FAIL)

### Run the test

```bash
curl -X POST $AGENT_URL/ops/calibration/check \
  -H 'Content-Type: application/json' \
  -d '{
    "tool": "L-900-07",
    "product": "PX-7",
    "layer": "M1",
    "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_outofspec.csv",
    "slackNotify": true
  }' | jq
```

### Expected Response

```json
{
  "correlationId": "ec9011ca-5d5b-4b24-a2ab-ed9aa33644f1",
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
    "sustainedOverlayViolation": true,
    "pointCount": 10
  }
}
```

### Verify Results

✅ **Check verdict**: Should be `"FAIL"`  
✅ **Check overlay**: `maxOverlay: 4.74` (> 3.5 UCL) ❌  
✅ **Check vibration**: `vibration: 1.0` (> 0.8 threshold) ❌  
✅ **Check sustained violation**: `sustainedOverlayViolation: true` ✅  
✅ **Check actions**: Should have 4 recommended actions  
✅ **Check Slack**: Alert should be sent (check logs)

---

## 📋 Step 5: View Logs & Reports

### View Agent Logs (with correlation IDs)

```bash
# Get the agent pod name
AGENT_POD=$(oc get pod -l app=acme-agent -n private-ai-demo -o name | head -1)

# View logs (last 50 lines)
oc logs -n private-ai-demo $AGENT_POD --tail=50

# Follow logs in real-time
oc logs -n private-ai-demo $AGENT_POD -f
```

**What to look for:**
```
[31981906-b5ae-431c-9ca3-790269dbc584] - AgentOrchestrator: Starting calibration check
[31981906-b5ae-431c-9ca3-790269dbc584] - QueryEquipmentSkill: Looking up L-900-07
[31981906-b5ae-431c-9ca3-790269dbc584] - WatchTelemetrySkill: overlay=3.00nm, doseU=0.41%
[31981906-b5ae-431c-9ca3-790269dbc584] - CompareAgainstLimitsSkill: Verdict=PASS
[31981906-b5ae-431c-9ca3-790269dbc584] - NotifySlackSkill: Slack notification sent
```

### View Slack MCP Logs (see the alerts)

```bash
# Get Slack MCP pod
SLACK_POD=$(oc get pod -l app=slack-mcp -n private-ai-demo -o name | head -1)

# View logs
oc logs -n private-ai-demo $SLACK_POD --tail=80 | grep -A 20 "ACME LithoOps"
```

**Expected Output (PASS):**
```
🟢 *ACME LithoOps: PASS*

*Equipment:* L-900-07
*Status:* PASS

*Measurements:*
• Overlay: 3.00 nm (UCL 3.50 nm)
• Dose Uniformity: 0.41% (UCL 2.50%)
• Vibration: 0.40 mm/s

_[correlationId: 31981906-b5ae-431c-9ca3-790269dbc584]_
```

**Expected Output (FAIL):**
```
🔴 *ACME LithoOps: FAIL*

*Equipment:* L-900-07
*Status:* FAIL

*Measurements:*
• Overlay: 4.74 nm (UCL 3.50 nm)
• Dose Uniformity: 0.60% (UCL 2.50%)
• Vibration: 1.00 mm/s

*Recommended Actions:*
• Investigate overlay calibration
• Check DFO baseline
• Inspect pump vibration
• Check mechanical stability

_[correlationId: ec9011ca-5d5b-4b24-a2ab-ed9aa33644f1]_
```

### View Generated Reports

```bash
# List reports
oc exec -n private-ai-demo $AGENT_POD -- ls -lh /app/documents/scenario2/reports/

# View the most recent report
LATEST_REPORT=$(oc exec -n private-ai-demo $AGENT_POD -- ls -t /app/documents/scenario2/reports/ | head -1)
oc exec -n private-ai-demo $AGENT_POD -- cat /app/documents/scenario2/reports/$LATEST_REPORT
```

**Expected Report Content:**
```
ACME LithoOps Calibration Report
═══════════════════════════════════════════════════════════════

Equipment: L-900-07
Product: PX-7
Layer: M1
Timestamp: 2025-10-08 14:22:41 UTC
Verdict: PASS

Measured Values vs Limits
──────────────────────────────────────────────────────────────
Parameter              Measured    Limit (UCL)
Overlay (nm)           3.00        3.50
Dose Uniformity (%)    0.41        2.50
Best Focus (μm)        0.52        0.50 ± 0.10
Vibration (mm/s)       0.40        0.8


References:
  [ACME_01_ACME_DFO_Calibration_SOP_v1.9] §3.2 Daily Calibration, p.12

[correlationId: 31981906-b5ae-431c-9ca3-790269dbc584]
```

---

## 🔄 Step 6: Run Multiple Tests (Stress Test)

### Quick test script

```bash
#!/bin/bash
# Run 5 calibration checks alternating between clean and out-of-spec

AGENT_URL="https://$(oc get route acme-agent -n private-ai-demo -o jsonpath='{.spec.host}')"

echo "Running 5 calibration checks..."

for i in {1..5}; do
  echo ""
  echo "=== Test $i ==="
  
  if [ $((i % 2)) -eq 0 ]; then
    # Even: Out-of-spec (FAIL)
    echo "Testing out-of-spec (expect FAIL)..."
    curl -s -X POST $AGENT_URL/ops/calibration/check \
      -H 'Content-Type: application/json' \
      -d '{
        "tool": "L-900-07",
        "product": "PX-7",
        "layer": "M1",
        "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_outofspec.csv",
        "slackNotify": true
      }' | jq -r '.verdict, .measured.maxOverlay'
  else
    # Odd: Clean (PASS)
    echo "Testing clean data (expect PASS)..."
    curl -s -X POST $AGENT_URL/ops/calibration/check \
      -H 'Content-Type: application/json' \
      -d '{
        "tool": "L-900-07",
        "product": "PX-7",
        "layer": "M1",
        "telemetryPath": "./documents/scenario2/telemetry/acme_telemetry_clean.csv",
        "slackNotify": true
      }' | jq -r '.verdict, .measured.maxOverlay'
  fi
  
  sleep 2
done

echo ""
echo "=== All tests complete ==="
```

Save this as `test-calibration.sh`, make it executable, and run:
```bash
chmod +x test-calibration.sh
./test-calibration.sh
```

---

## 📊 Step 7: Verify Database MCP

### Test equipment query

```bash
# Inside agent pod, test Database MCP directly
oc exec -n private-ai-demo $AGENT_POD -- curl -s -X POST http://database-mcp:8080/execute \
  -H 'Content-Type: application/json' \
  -d '{
    "tool": "query_equipment",
    "parameters": {
      "equipment_id": "L-900-07"
    }
  }' | python3 -m json.tool
```

**Expected Response:**
```json
{
  "result": {
    "found": true,
    "equipment": {
      "id": "L-900-07",
      "type": "L-900 EUV Scanner",
      "model": "ASML TWINSCAN NXE:3600D",
      "status": "Operational",
      "location": "Fab 3, Bay 12",
      "customer": "ACME Semiconductor"
    }
  }
}
```

### Test parts inventory

```bash
oc exec -n private-ai-demo $AGENT_POD -- curl -s -X POST http://database-mcp:8080/execute \
  -H 'Content-Type: application/json' \
  -d '{
    "tool": "query_parts_inventory",
    "parameters": {
      "part_number": "P12345"
    }
  }' | python3 -m json.tool
```

---

## ✅ Validation Checklist

| Test | Expected Result | Status |
|------|-----------------|--------|
| **Deployment** |||
| ☐ All pods running | 3 pods (acme-agent, slack-mcp, database-mcp) | |
| ☐ All services created | 3 services | |
| ☐ Route accessible | External URL working | |
| **Health Checks** |||
| ☐ Agent health | `{"status": "healthy"}` | |
| ☐ Slack MCP reachable | `"✅ Reachable"` | |
| ☐ Database MCP reachable | `"✅ Reachable"` | |
| **Flow 1 (Clean)** |||
| ☐ Verdict | `"PASS"` | |
| ☐ Overlay | < 3.5 nm | |
| ☐ Actions | [] (empty) | |
| ☐ Report generated | Yes | |
| ☐ Slack alert | Sent (demo mode) | |
| **Flow 2 (Out-of-Spec)** |||
| ☐ Verdict | `"FAIL"` | |
| ☐ Overlay | > 3.5 nm | |
| ☐ Sustained violation | Detected | |
| ☐ Actions | 4 recommendations | |
| ☐ Report generated | Yes | |
| ☐ Slack alert | Sent with violations | |
| **Observability** |||
| ☐ Correlation IDs | Present in all logs | |
| ☐ Agent logs | Structured and readable | |
| ☐ Slack MCP logs | Alert content visible | |
| ☐ Reports readable | Text format, citations included | |

---

## 🐛 Troubleshooting

### Pod not running
```bash
# Check pod status
oc get pods -l app=acme-agent -n private-ai-demo

# View pod events
oc describe pod -l app=acme-agent -n private-ai-demo

# View pod logs
oc logs -l app=acme-agent -n private-ai-demo
```

### MCP not reachable
```bash
# Check MCP pod status
oc get pods -l app=slack-mcp -n private-ai-demo
oc get pods -l app=database-mcp -n private-ai-demo

# Test MCP health directly
oc exec -n private-ai-demo $AGENT_POD -- curl -s http://slack-mcp:8080/health
oc exec -n private-ai-demo $AGENT_POD -- curl -s http://database-mcp:8080/health
```

### Route not accessible
```bash
# Check route
oc get route acme-agent -n private-ai-demo

# Test from inside cluster
oc exec -n private-ai-demo $AGENT_POD -- curl -s http://localhost:8080/health
```

### No reports generated
```bash
# Check write permissions
oc exec -n private-ai-demo $AGENT_POD -- ls -ld /app/documents/scenario2/reports/

# Check if directory exists
oc exec -n private-ai-demo $AGENT_POD -- mkdir -p /app/documents/scenario2/reports/
```

---

## 📚 Additional Resources

- **Full README**: `stage3-enterprise-mcp/README-scenario2-acme.md`
- **Implementation Details**: `stage3-enterprise-mcp/IMPLEMENTATION-SUCCESS.md`
- **Deployment Script**: `stage3-enterprise-mcp/deploy.sh`

---

**Happy Testing!** 🚀

If you encounter any issues, check the logs first - correlation IDs will help you trace requests end-to-end.


