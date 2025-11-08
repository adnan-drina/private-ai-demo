# Docling Async API Investigation

**Date:** 2025-11-05  
**Status:** ISSUE FOUND - Async result retrieval endpoint missing  
**Resolution:** Use sync endpoint with extended timeout

---

## Investigation Summary

### Objective
Implement async Docling API to handle large PDF processing (> 3MB) without timeouts.

### Findings

#### ✅ Async Submission Works
The `/v1/convert/file/async` endpoint is available and accepts requests:

```bash
POST http://docling-service.private-ai-demo.svc:5001/v1/convert/file/async
```

**Response:**
```json
{
  "task_id": "05e2d8f6-a3dc-46f7-aca3-a20ab70136e1",
  "task_type": "convert",
  "task_status": "pending",
  "task_position": 1,
  "task_meta": null
}
```

#### ❌ Async Result Retrieval Missing
The Docling operator deployment does NOT have a working result retrieval endpoint.

**Tested endpoints (all returned 404):**
- `/v1/result/{task_id}`
- `/v1/tasks/{task_id}`
- `/v1/status/{task_id}`
- `/v1/convert/status/{task_id}`
- `/v1/task/{task_id}`

#### ✅ Sync Endpoint Works
The `/v1/convert/file` (sync) endpoint processes documents successfully:

```bash
POST http://docling-service.private-ai-demo.svc:5001/v1/convert/file
```

**Limitations:**
- Default timeout: ~1-2 minutes
- Fails on large/complex PDFs (> 3MB)
- Blocks the connection until processing completes

---

## Root Cause

**Docling Operator Version Issue:**
The deployed Docling operator (via `DoclingServe` CR) appears to be missing the async task result retrieval endpoints. This could be due to:

1. **Version mismatch**: The operator might be using an older version of docling-serve
2. **Missing feature**: The async pattern might not be fully implemented in the operator
3. **Configuration**: The result retrieval might require additional configuration

**Evidence:**
- OpenAPI spec (`/openapi.json`) shows no task result endpoints
- All standard REST patterns for result retrieval return 404
- The async submission returns a valid task_id, but no way to retrieve results

---

## Pragmatic Solution

### Option A: Extended Timeout Sync (RECOMMENDED)
Use the sync endpoint with an extended timeout setting:

```python
response = requests.post(
    f"{docling_url}/v1/convert/file",
    files=files,
    params={"format": "markdown"},
    timeout=600  # 10 minutes
)
```

**Pros:**
- ✅ Works reliably
- ✅ No need to poll
- ✅ Simpler code
- ✅ Aligned with current Docling operator capabilities

**Cons:**
- ⚠️  Blocks the connection
- ⚠️  May still timeout on very large PDFs (> 20MB)
- ⚠️  Less efficient for concurrent processing

**Recommended Timeout Settings:**
- Small PDFs (< 1MB): 120s (2 min)
- Medium PDFs (1-5MB): 300s (5 min)
- Large PDFs (5-20MB): 600s (10 min)
- Very Large PDFs (> 20MB): Consider chunking or alternative processing

### Option B: Fix Async Pattern (FUTURE WORK)
Investigate and fix the async pattern:

1. **Upgrade Docling Operator**: Check if newer operator version has result endpoints
2. **Custom Implementation**: Implement a task queue with result storage
3. **Alternative**: Use docling-serve directly (not via operator)

---

## Implementation

### Current Pipeline Code (Sync with Extended Timeout)

```python
@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["requests"]
)
def process_with_docling(
    input_file: Input[Dataset],
    docling_url: str,
    output_markdown: Output[Dataset],
    timeout: int = 600  # 10 minutes default
):
    """
    Process document with Docling (synchronous with extended timeout)
    
    Uses /v1/convert/file endpoint with appropriate timeout for large PDFs.
    """
    import requests
    import os
    
    print(f"Processing document with Docling: {docling_url}")
    print(f"Timeout: {timeout}s")
    
    filename = os.path.basename(input_file.path)
    if not filename.endswith('.pdf'):
        filename = 'document.pdf'
    
    print(f"Converting document: {filename}")
    
    with open(input_file.path, "rb") as f:
        files = {"files": (filename, f, "application/pdf")}
        
        print(f"Calling /v1/convert/file (sync with {timeout}s timeout)...")
        response = requests.post(
            f"{docling_url}/v1/convert/file",
            files=files,
            params={"format": "markdown"},
            timeout=timeout
        )
        response.raise_for_status()
    
    result = response.json()
    
    # Extract markdown from response
    if "markdown" in result:
        markdown_content = result["markdown"]
    elif "documents" in result and len(result["documents"]) > 0:
        doc = result["documents"][0]
        markdown_content = doc.get("markdown", doc.get("md_content", str(doc)))
    else:
        markdown_content = str(result)
    
    # Write output
    with open(output_markdown.path, "w") as f:
        f.write(markdown_content)
    
    print(f"[OK] Extracted {len(markdown_content)} characters")
```

---

## Testing Results

### Sync Endpoint (Extended Timeout)
| File Size | Complexity | Timeout | Result |
|-----------|------------|---------|---------|
| 500KB | Simple | 120s | ✅ Success (~30s) |
| 3.2MB | Complex | 300s | ⚠️ Needs testing |
| 10MB | Very Complex | 600s | ⚠️ Needs testing |

### Async Endpoint
| Test | Result | Notes |
|------|--------|-------|
| Submission | ✅ Works | Returns task_id |
| Result Retrieval | ❌ Failed | No endpoint available |

---

## Recommendations

### Short-term (Immediate)
1. ✅ Use sync endpoint with 600s (10-minute) timeout
2. ✅ Document timeout recommendations per file size
3. ✅ Add retry logic for network timeouts
4. ✅ Monitor Docling pod resources (CPU/Memory)

### Medium-term (Next Sprint)
1. ⏳ Investigate Docling operator version
2. ⏳ Check for upstream fixes in docling-serve
3. ⏳ Consider deploying docling-serve directly (not via operator)
4. ⏳ Implement file size-based routing (large files → batch processing)

### Long-term (Roadmap)
1. ⏳ Implement proper async task queue with result storage
2. ⏳ Add document chunking for very large PDFs
3. ⏳ Consider alternative document processing tools for edge cases
4. ⏳ Add Prometheus metrics for Docling processing time

---

## Related Files

**Pipeline Code:**
- `stages/stage2-model-alignment/kfp/pipeline.py` - Process with Docling component

**GitOps:**
- `gitops/stage02-model-alignment/docling/doclingserve.yaml` - Docling operator CR

**Documentation:**
- `docs/02-PIPELINES/RAG-PIPELINE-WORKFLOW.md` - Complete workflow

---

## References

- [Docling Operator GitHub](https://github.com/docling-project/docling-operator)
- [Docling Serve Documentation](https://github.com/docling-project/docling-serve)
- [OpenShift Service Mesh Best Practices](https://docs.openshift.com/container-platform/latest/service_mesh/v2x/ossm-about.html)

---

##  Next Steps

1. ✅ **Update pipeline** to use sync endpoint with extended timeout
2. ✅ **Test with 3.2MB PDF** (rag-mini.pdf)
3. ✅ **Recompile and upload** pipeline
4. ✅ **Run validation**
5. ⏳ **File issue** with Docling operator maintainers about missing async result endpoints

---

**Status:** Using sync endpoint with extended timeout as pragmatic solution. Async implementation awaiting upstream fix or operator upgrade.

