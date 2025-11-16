# Next Steps After RAG Pipeline Completion

## Current Status
- **Pipeline**: `data-processing-and-insertion-f6w9g` (Running - 28/31 tasks, 90% complete)
- **Configuration**: 
  - ✅ Milvus: `auto_id=false` (accepts custom string IDs)
  - ✅ Docling: 16Gi memory (upgraded for large PDFs)
  - ✅ All 3 PDFs being processed

## Immediate Post-Completion Steps

### 1. Verify RAG Ingestion Success ⚡ (5 minutes)

**Verify chunks were inserted with string IDs:**
```bash
# Check collection exists and has chunks
oc exec deployment/llama-stack -n private-ai-demo -- \
  curl -s -X POST http://localhost:8321/v1/vector_stores/red_hat_docs/query \
  -H "Content-Type: application/json" \
  -d '{"query": "OpenShift", "limit": 3}' | python3 -m json.tool
```

**Expected Output:**
- Should return 3 chunks
- `stored_chunk_id` field should be **strings** (e.g., `"DevOps_chunk_0"`)
- No errors about type mismatches

**Verify in playground:**
- Navigate to: https://llama-stack-playground-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/rag
- Select: `red_hat_docs` database
- Test query: "What is OpenShift?"
- Expected: ✅ Retrieves relevant chunks without errors

### 2. Test End-to-End RAG Flow ⚡ (10 minutes)

**Test queries to validate all 3 PDFs:**

1. **DevOps PDF (7.1 MB)**:
   ```
   Query: "DevOps practices with OpenShift"
   Expected: Chunks from DevOps_with_OpenShift.pdf
   ```

2. **Architecture PDF (1.2 MB)**:
   ```
   Query: "OpenShift architecture and components"
   Expected: Chunks from OpenShift_Container_Platform-4.20-Architecture-en-US.pdf
   ```

3. **RAG Guide PDF (0.2 MB)**:
   ```
   Query: "RHOAI RAG implementation"
   Expected: Chunks from rhoai-rag-guide.pdf
   ```

**Validation Checklist:**
- [ ] All queries return relevant content
- [ ] No 400 errors (stored_chunk_id validation)
- [ ] No 500 errors (insertion failures)
- [ ] Response quality is good
- [ ] Streaming works (if enabled)

### 3. Document and Commit Success 📝 (15 minutes)

**Create validation report:**
```bash
cd /Users/adrina/Sandbox/private-ai-demo

# Document successful validation
cat << 'EOF' > docs/STAGE4-RAG-VALIDATION-SUCCESS.md
# Stage 4 RAG: Successful Validation Report

## Date
$(date '+%Y-%m-%d %H:%M:%S')

## Pipeline Execution

### Run Details
- Workflow: data-processing-and-insertion-f6w9g
- Status: ✅ Succeeded
- Duration: ~XX minutes

### Documents Processed
1. ✅ DevOps_with_OpenShift.pdf (7.1 MB) - XX chunks
2. ✅ OpenShift_Container_Platform-4.20-Architecture-en-US.pdf (1.2 MB) - XX chunks  
3. ✅ rhoai-rag-guide.pdf (0.2 MB) - XX chunks

Total chunks: XXX

## Configuration Applied

### Milvus Fix
- `auto_id: false` (accepts custom string IDs)
- `id_field: "stored_chunk_id"`
- `text_field: "content"`
- **Result**: ✅ No Pydantic warnings, string IDs accepted

### Docling Upgrade
- Memory: 16Gi (doubled from 8Gi)
- Node: ip-10-0-78-250 (new worker, 62Gi capacity)
- **Result**: ✅ No OOM kills, all PDFs processed

## Validation Results

### Retrieval Tests
- Query 1 (DevOps): [PASS/FAIL]
- Query 2 (Architecture): [PASS/FAIL]
- Query 3 (RAG Guide): [PASS/FAIL]

### Performance
- Retrieval latency: ~XXXms
- No errors in logs
- String IDs working correctly

## Next Steps
- [ ] Merge feature branch to main
- [ ] Update ArgoCD to resync with new configs
- [ ] Proceed with Stage 4 MCP implementation
EOF

git add docs/STAGE4-RAG-VALIDATION-SUCCESS.md
git commit -m "docs(stage4): RAG pipeline validation success report"
git push origin feature/stage4-implementation
```

### 4. Merge Feature Branch to Main 🔀 (10 minutes)

**Critical changes to merge:**
1. Milvus `auto_id: false` configuration
2. Docling 16Gi memory upgrade
3. Updated documentation

**Merge process:**
```bash
# Switch to main
git checkout main
git pull origin main

# Merge feature branch
git merge feature/stage4-implementation

# Push to main
git push origin main
```

**Update ArgoCD to use main:**
```bash
# Refresh Stage 02 app (LlamaStack config)
oc patch application stage02-model-alignment -n openshift-gitops \
  --type=json -p='[{"op": "replace", "path": "/spec/source/targetRevision", "value": "main"}]'

# Sync to apply changes
oc -n openshift-gitops patch application stage02-model-alignment \
  --type=json -p='[{"op": "replace", "path": "/operation/sync", "value": {}}]'
```

### 5. Monitor Collection Health 🔍 (Ongoing)

**Check collection statistics:**
```bash
# Via LlamaStack
oc exec deployment/llama-stack -n private-ai-demo -- \
  curl -s http://localhost:8321/v1/vector_stores | python3 -m json.tool

# Check Milvus collection stats
oc exec deployment/milvus-standalone -n private-ai-demo -- \
  curl -s -X POST http://localhost:19530/v1/collections/stats \
  -d '{"collection_name": "red_hat_docs"}'
```

**Expected metrics:**
- Total chunks: ~500-1000 (depending on chunking strategy)
- All chunks have string `stored_chunk_id`
- No orphaned or duplicate chunks

---

## Stage 4 Implementation: Next Phase 🚀

After RAG validation is complete, proceed with **Stage 4 Model Integration**:

### Phase 1: MCP Server Implementation

**Priority 1: OpenShift MCP Server**
- [x] Implement `mcp::openshift` server (Go-based Kubernetes MCP image)
- [x] Tools: `list_pods`, `get_pod_logs`, `projects_list`, `events_list`
- [x] Build container image / reference upstream image
- [x] Deploy to `private-ai-demo` namespace with RBAC + ServiceAccount
- [x] Register with LlamaStack

**Priority 2: Slack MCP Server** (Already exists in Stage 04)
- [x] Review existing implementation
- [x] Update for SSE endpoint requirement
- [x] Test integration via Playground agent

**Reference**: 
- Demo notebook: https://github.com/opendatahub-io/llama-stack-demos/blob/main/demos/rag_agentic/notebooks/Level6_agents_MCP_and_RAG.ipynb
- MCP Spec: https://github.com/modelcontextprotocol/specification

### Phase 2: LlamaStack Tool Registration

**Register MCP tools with LlamaStack:**
```yaml
# Update gitops/stage02-model-alignment/llama-stack/configmap.yaml
tool_groups:
  - toolgroup_id: builtin::rag
    provider_id: rag-runtime
  
  - toolgroup_id: mcp::database
    provider_id: model-context-protocol
    mcp_endpoint:
      uri: "http://database-mcp.private-ai-demo.svc:8080/sse"
  
  - toolgroup_id: mcp::openshift
    provider_id: model-context-protocol
    mcp_endpoint:
      uri: "http://openshift-mcp.private-ai-demo.svc:8000/sse"
  
  - toolgroup_id: mcp::slack
    provider_id: model-context-protocol
    mcp_endpoint:
      uri: "http://slack-mcp.private-ai-demo.svc:8080/sse"
```

### Phase 3: Playground Enhancement

**Extend LlamaStack Playground for tool usage:**
- [x] Add tool selection UI
- [x] Display tool execution results
- [ ] Show agent reasoning steps (ReAct pattern)
- [ ] Tool execution visualization

**Target**: Interactive agentic AI demo combining:
- RAG (Red Hat docs retrieval)
- Tools (OpenShift operations)
- Agent (Reasoning + Action)

### Phase 4: End-to-End Demo Scenario

**Demo Flow**:
1. User asks: "Scale up the mistral-24b deployment to 3 replicas"
2. Agent reasons:
   - Needs to check current state (RAG: OpenShift scaling docs)
   - Needs to execute operation (Tool: `scale_deployment`)
3. Agent retrieves relevant docs from RAG
4. Agent calls `mcp::openshift.scale_deployment`
5. Agent confirms and summarizes result

**Expected Outcome**:
- ✅ RAG provides context
- ✅ MCP tool executes action
- ✅ Agent chains reasoning + retrieval + action
- ✅ User sees full trace in playground

---

## Troubleshooting Guide

### If Pipeline Fails

**Check Docling pod:**
```bash
oc get pods -n private-ai-demo | grep docling
oc logs -l app=docling -n private-ai-demo --tail=100
```
- OOM kill (exit 137): Increase memory beyond 16Gi or split PDFs

**Check LlamaStack insertion:**
```bash
oc logs deployment/llama-stack -n private-ai-demo --tail=200 | grep -i "error\|warning"
```
- Pydantic warnings: Milvus config not applied correctly
- 404 errors: Collection not registered
- 500 errors: Milvus connection issue

**Check Milvus:**
```bash
oc get pods -n private-ai-demo | grep milvus
oc logs milvus-standalone-XXX -n private-ai-demo --tail=100
```
- Connection refused: Milvus service down
- Schema errors: Collection needs to be dropped and recreated

### If Retrieval Fails After Success

**Verify collection exists:**
```bash
oc exec deployment/llama-stack -n private-ai-demo -- \
  curl -s http://localhost:8321/v1/vector_stores
```

**Test direct Milvus query:**
```bash
# Check if collection has data
oc exec deployment/milvus-standalone -n private-ai-demo -- \
  milvus-cli query -c red_hat_docs -e "count(*)"
```

**Re-register vector database:**
```bash
oc delete pod -l app=llama-stack -n private-ai-demo
# Wait for restart, vector dbs should auto-register from config
```

---

## Success Criteria

Before moving to Stage 4 MCP implementation, ensure:

- [x] ✅ Milvus `auto_id=false` fix applied and working
- [x] ✅ Docling 16Gi memory upgrade deployed
- [ ] ✅ RAG pipeline completed successfully
- [ ] ✅ All 3 PDFs processed without errors
- [ ] ✅ Retrieval returns chunks with string IDs
- [ ] ✅ No Pydantic warnings in logs
- [ ] ✅ Playground RAG flow works end-to-end
- [ ] ✅ Changes merged to `main` branch
- [ ] ✅ ArgoCD synced with new configuration

**Status**: 6/9 complete (waiting for pipeline completion + validation)

---

## Timeline Estimate

| Task | Duration | Status |
|------|----------|--------|
| Pipeline completion | ~15-30 min | ⏳ In Progress |
| Validation & testing | ~15 min | ⏸️ Pending |
| Documentation | ~10 min | ⏸️ Pending |
| Git merge & ArgoCD sync | ~10 min | ⏸️ Pending |
| **Total** | **~50-65 min** | |

**Next Phase** (Stage 4 MCP):
- MCP server implementation: ~2-3 hours
- LlamaStack integration: ~1 hour
- Playground enhancement: ~2 hours
- End-to-end demo: ~1 hour
- **Total**: ~6-7 hours

---

## References

- [Stage 4 RAG Milvus Fix Summary](./STAGE4-RAG-MILVUS-FIX-SUMMARY.md)
- [LlamaStack Milvus Provider](https://llama-stack.readthedocs.io/en/v0.2.11/providers/vector_io/milvus.html)
- [Docling Operator](https://github.com/docling-project/docling-operator)
- [OpenDataHub LlamaStack Demos](https://github.com/opendatahub-io/llama-stack-demos)

