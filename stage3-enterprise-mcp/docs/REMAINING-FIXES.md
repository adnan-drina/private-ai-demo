# Remaining Fixes Required

## Current Status

✅ **Working:**
1. vLLM Integration - Manual tool orchestration (no role errors)
2. Slack MCP - Sends alerts successfully
3. Telemetry file reading - Fixed path issue

❌ **Not Working:**
1. Database MCP Client - Needs MCP protocol implementation
2. Llama Stack RAG Client - Needs endpoint fixes  
3. All database queries (equipment, service history, parts)

## Issues from Latest Test (Correlation ID: bb2cbaf1)

### 1. Database MCP Client (404 errors)
**Error:** `NOT FOUND, status code 404` when invoking `DatabaseMcpClient#queryEquipment`

**Root Cause:** Still using old REST endpoints instead of MCP protocol

**Current (Wrong):**
```java
@Path("/tools")
@POST @Path("/query_equipment")
EquipmentQueryResponse queryEquipment(EquipmentQueryRequest request);
```

**Should Be:**
```java
@Path("/execute")
@POST
McpResponse execute(McpRequest request);
// Call with: {"tool": "query_equipment", "parameters": {"equipmentId": "..."}}
```

**Files to Fix:**
- `DatabaseMcpClient.java` - Already updated interface, needs tool usage updates
- `CalibrationTools.java` lines 117, 195, 223 - Update all database calls to use MCP format:
  ```java
  // OLD:
  EquipmentQueryResponse response = databaseMcp.queryEquipment(
      new EquipmentQueryRequest(equipmentId)
  );
  
  // NEW:
  Map<String, Object> params = Map.of("equipmentId", equipmentId);
  var request = new DatabaseMcpClient.McpRequest("query_equipment", params);
  var response = databaseMcp.execute(request);
  Map<String, Object> equipment = (Map<String, Object>) response.result.get("equipment");
  ```

### 2. Llama Stack RAG Client (404 errors)
**Error:** `Not Found, status code 404` when invoking `LlamaStackClient#createSession`

**Root Cause:** Incorrect Llama Stack API endpoints

**Current (Wrong):**
```java
@POST @Path("/sessions")  
SessionResponse createSession(SessionRequest request);
```

**Should Be:** Need to check actual Llama Stack API docs

**Investigation Needed:**
1. Check Llama Stack pod logs for available endpoints
2. Test endpoints manually with curl
3. Update `LlamaStackClient.java` with correct paths
4. May need to use `/v1/rag` or `/v1/memory` endpoints

### 3. Telemetry File Path
**Error:** `java.io.FileNotFoundException: acme_telemetry_clean.csv`

**Fix Applied:** ✅ Already fixed in latest code
```java
String fullPath = filePath.startsWith("/") ? filePath : "/deployments/data/telemetry/" + filePath;
```

## Implementation Plan

### Phase 1: Fix Database MCP Client
1. Update `CalibrationTools.java` getEquipmentInfo() method:
   ```java
   Map<String, Object> params = Map.of("equipmentId", equipmentId);
   var request = new DatabaseMcpClient.McpRequest("query_equipment", params);
   var response = databaseMcp.execute(request);
   ```

2. Update getServiceHistory() method similarly

3. Update queryParts() method similarly

### Phase 2: Fix Llama Stack RAG Client
1. Test Llama Stack endpoints:
   ```bash
   curl http://rag-stack-service.private-ai-demo:8321/health
   curl http://rag-stack-service.private-ai-demo:8321/v1/...
   ```

2. Check Llama Stack documentation/logs for correct API

3. Update `LlamaStackClient.java` with correct endpoints

4. Update `CalibrationTools.java` getCalibrationLimits() method

### Phase 3: Build and Test
1. Rebuild application: `mvn clean package`
2. Deploy: `oc start-build acme-agent`
3. Test end-to-end calibration check
4. Verify all tools return real data (not errors)

## Expected End State

When complete, a calibration check should:
1. ✅ Query real equipment data from Database MCP
2. ✅ Get real calibration limits from Llama Stack RAG
3. ✅ Read actual telemetry CSV data
4. ✅ LLM analyzes real data (not error messages)
5. ✅ Send Slack notification with actual verdict
6. ✅ Return meaningful PASS/FAIL based on real measurements

## Test Command

```bash
curl -sk -X POST "https://acme-agent-acme-calibration-ops.apps.cluster-n8cnx.n8cnx.sandbox2830.opentlc.com/api/v1/ops/calibration/check" \
  -H "Content-Type: application/json" \
  -d '{"equipmentId":"LITHO-001","telemetryFile":"acme_telemetry_clean.csv"}'
```

## Success Criteria

The response should contain:
- Real equipment model/status (not "Error querying equipment")
- Real calibration limits from docs (not "Error retrieving calibration limits")  
- Real telemetry measurements analyzed
- Concrete PASS/FAIL verdict based on actual data comparison
- Specific out-of-spec measurements if any

---

**Next Steps:** Fix Database MCP calls in Calibration Tools.java (3 methods), then fix Llama Stack RAG client.

