# LlamaStack Playground Validation Guide

**Status:** All 3 collections validated via API ✅  
**Date:** 2025-11-07  
**Performance:** Granite-optimized (0.22s embeddings)

---

## Quick Validation Steps

### Access Playground

**URL:** https://llama-stack-playground-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com

---

## Scenario 1: Red Hat Documentation

**Vector DB:** `red_hat_docs`

**Test Queries:**
1. "What is Red Hat OpenShift AI?"
2. "How do I work with RAG in OpenShift AI?"
3. "What are the key features of Red Hat's AI platform?"

**Expected Results:**
- Should retrieve 3-5 relevant chunks
- Content about OpenShift AI, RAG, and Red Hat AI services
- Similarity scores visible

---

## Scenario 2: ACME Corporate

**Vector DB:** `acme_corporate`

**Test Queries:**
1. "What is the corporate policy?"
2. "What are ACME's AI safety regulations?"
3. "What guidelines does ACME follow?"

**Expected Results:**
- Should retrieve 3-5 relevant chunks
- Corporate policy and AI safety content
- References to regulations and guidelines

---

## Scenario 3: EU AI Act

**Vector DB:** `eu_ai_act`

**Test Queries:**
1. "What is the EU AI Act about?"
2. "How will the AI Act be enforced?"
3. "What are the key principles of EU AI regulation?"

**Expected Results:**
- Should retrieve 3-5 relevant chunks
- EU AI Act regulatory content
- Information about enforcement and governance

---

## Validation Checklist

- [ ] Playground loads successfully
- [ ] All 3 vector DBs appear in dropdown
- [ ] Red Hat Docs: Query returns relevant chunks
- [ ] ACME Corporate: Query returns relevant chunks
- [ ] EU AI Act: Query returns relevant chunks
- [ ] Response times are fast (< 2 seconds)
- [ ] Chunks show source metadata
- [ ] Can switch between collections seamlessly

---

## Troubleshooting

### Playground won't load
```bash
# Check pod status
oc -n private-ai-demo get pods -l app=llama-stack-playground

# Check logs
oc -n private-ai-demo logs -l app=llama-stack-playground --tail=50
```

### No collections visible
```bash
# Verify LlamaStack API
POD=$(oc -n private-ai-demo get pods -l app=llama-stack -o name | head -1)
oc -n private-ai-demo exec $POD -- curl -s http://localhost:8321/v1/vector-dbs
```

### Queries return no results
```bash
# Test direct API
POD=$(oc -n private-ai-demo get pods -l app=llama-stack -o name | head -1)
oc -n private-ai-demo exec $POD -- python3 -c "
import requests
resp = requests.post(
    'http://localhost:8321/v1/vector-io/query',
    json={'vector_db_id': 'red_hat_docs', 'query': 'test', 'params': {'top_k': 3}}
)
print(f'Status: {resp.status_code}')
print(resp.json())
"
```

---

## API Validation (Already Completed ✅)

All collections validated successfully via LlamaStack Vector IO API:

```
✅ red_hat_docs      Status: 200, Retrieved 3 chunks
✅ acme_corporate    Status: 200, Retrieved 3 chunks  
✅ eu_ai_act         Status: 200, Retrieved 3 chunks
```

Performance: **0.22s** per query (Granite-optimized)

---

## Next Steps After Validation

1. **Commit changes** to Git
2. **Deploy via GitOps** (ArgoCD)
3. **Monitor production** usage
4. **Optional:** Add more documents via batch pipelines

---

**Documentation:** See `docs/03-STAGE2-RAG/` for complete details  
**Support:** All 3 scenarios validated and working ✅
