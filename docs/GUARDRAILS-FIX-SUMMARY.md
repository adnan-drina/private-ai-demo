# 🛡️ Guardrails Fix - Implementation Summary

## Issues Fixed
**Problem**: When guardrails were enabled in llama-stack-playground (Chat or RAG), ALL prompts were blocked, even legitimate ones with no violations.

**Root Causes**: Two separate bugs were causing this behavior:

1. **Metadata Parsing Bug**: The `_normalize_violation()` function was looking for `status` and `summary` fields at the top level of the violation object, but TrustyAI provider returns these fields nested inside `metadata`.

2. **Missing Required Field**: The `_filter_guardrail_messages()` function was not adding the required `stop_reason` field to assistant messages, causing the LlamaStack safety API to return HTTP 400 validation errors.

---

## Solution Implemented

### Files Modified
1. `gitops/stage02-model-alignment/llama-stack/playground-chat.py`
2. `gitops/stage02-model-alignment/llama-stack/playground-rag.py`

### Fix 1: Correct Metadata Parsing
Updated the `_normalize_violation()` function in both files to:

1. **Check `violation_level`**: Recognize "info" level messages (informational, not violations)
2. **Extract `metadata` object**: Get the nested metadata containing status and summary
3. **Check `metadata.status` first**: Look for status in metadata, then fallback to top-level
4. **Check `metadata.summary` first**: Look for summary in metadata, then fallback to top-level
5. **Added "passed" status**: Include "passed" in the list of valid pass statuses

#### Code Snippet
```python
# Extract metadata (TrustyAI provider returns status/summary nested in metadata)
metadata = _extract_attr(payload, "metadata")

# Try to get status from metadata first, then fallback to top-level
status_raw = _extract_attr(metadata, "status") if metadata else None
if status_raw is None:
    status_raw = _extract_attr(payload, "status")

# Try to get summary from metadata first, then fallback to top-level
summary = _extract_attr(metadata, "summary") if metadata else None
if summary is None:
    summary = _extract_attr(payload, "summary")
```

### Fix 2: Add Required stop_reason Field
Updated the `_filter_guardrail_messages()` function in both files to:

1. **Iterate explicitly**: Change from list comprehension to explicit loop
2. **Add stop_reason**: Add `stop_reason: "end_of_turn"` field to assistant messages
3. **Check if missing**: Only add the field if not already present

#### Code Snippet
```python
def _filter_guardrail_messages(messages: list[dict]) -> list[dict]:
    """Remove system messages and ensure assistant messages have required fields."""
    filtered = []
    for msg in messages:
        if (msg or {}).get("role") == "system":
            continue
        
        # Add required stop_reason field for assistant messages
        if msg.get("role") == "assistant" and "stop_reason" not in msg:
            msg = {**msg, "stop_reason": "end_of_turn"}
        
        filtered.append(msg)
    
    return filtered if filtered else messages
```

---

## Deployment

### Git Commits
1. **Commit 1**: `f746f84` - fix(stage2): Fix guardrails blocking all prompts in playground
2. **Commit 2**: `7c9bad9` - fix(stage2): Add required stop_reason field to assistant messages in shield calls
- **Branch**: `main`
- **Pushed**: ✅ Deployed to remote

### OpenShift
- **ArgoCD Sync**: ✅ Stage 02 synced successfully
- **ConfigMaps**: ✅ Both `llama-stack-playground-chat` and `llama-stack-playground-rag` updated
- **Deployment**: ✅ Restarted (`llama-stack-playground`)
- **Pod**: ✅ New pod running with both fixes

### Verification
- ✅ Fix 1 signature: "Extract metadata" comment present
- ✅ Fix 2 signature: `stop_reason` field addition present
- ✅ Both fixes verified in `/app/page/playground/chat.py` and `/app/page/playground/rag.py`

---

## Testing Instructions

### Access Playground
- **Chat**: https://llama-stack-playground-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/playground
- **RAG**: https://llama-stack-playground-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/rag

### Test Cases

#### ✅ Test 1: Normal Prompt (Should PASS)
1. Enable guardrails checkbox
2. Select shield: `regex_guardrail` or `toxicity_guardrail`
3. Enter prompt: "What are the benefits of AI?"
4. **Expected**: Response is generated normally (NOT blocked)

#### ❌ Test 2: PII Content (Should BLOCK)
1. Enable guardrails checkbox
2. Select shield: `regex_guardrail`
3. Enter prompt: "My email is john@example.com and SSN is 123-45-6789"
4. **Expected**: Blocked with violation message

#### ❌ Test 3: Toxic Content (Should BLOCK)
1. Enable guardrails checkbox
2. Select shield: `toxicity_guardrail`
3. Enter toxic prompt
4. **Expected**: Blocked with violation message

#### ✅ Test 4: RAG with Guardrails (Should PASS)
1. Upload documents in RAG page
2. Enable guardrails
3. Ask question about documents
4. **Expected**: RAG response generated normally

---

## Technical Details

### Issue 1: TrustyAI Response Structure
```json
{
  "violation": {
    "violation_level": "info",
    "user_message": "Content verified by shield regex_guardrail",
    "metadata": {
      "status": "pass",
      "summary": {
        "messages_with_violations": 0,
        "total_violations_found": 0,
        "messages_passed": 1
      }
    }
  }
}
```

**Before Fix**:
- Looked for `violation.status` (doesn't exist)
- Looked for `violation.summary` (doesn't exist)
- Always returned payload as violation
- Result: ALL prompts blocked

**After Fix**:
- Checks `violation.metadata.status` first
- Checks `violation.metadata.summary` first
- Falls back to top-level for compatibility
- Result: Proper pass/fail detection

### Issue 2: LlamaStack Safety API Requirements
```python
# Error before fix:
RequestValidationError: [{'type': 'missing', 'loc': ('body', 'messages', 1, 'assistant', 'stop_reason'), 'msg': 'Field required'}]
```

**Before Fix**:
- Assistant messages sent without `stop_reason` field
- LlamaStack API validation failed with HTTP 400
- Shield check never executed

**After Fix**:
- Assistant messages include `stop_reason: "end_of_turn"`
- API validation passes
- Shield check executes successfully

---

## Backward Compatibility

Both fixes are **fully backward compatible**:

### Fix 1:
- Checks metadata fields first (for TrustyAI provider)
- Falls back to top-level fields (for other providers)
- Existing functionality preserved

### Fix 2:
- Only adds `stop_reason` if not already present
- Uses standard value `"end_of_turn"`
- Compatible with LlamaStack API requirements

---

## Related Documentation

- Full root cause analysis: `docs/GUARDRAILS-ISSUE-ANALYSIS.md`
- Commit 1: https://github.com/adnan-drina/private-ai-demo/commit/f746f84
- Commit 2: https://github.com/adnan-drina/private-ai-demo/commit/7c9bad9

---

## Deployment Timeline

| Step | Status | Commit |
|------|--------|--------|
| Issue identified | ✅ | User report |
| Root cause analysis | ✅ | Deep dive |
| Fix 1: Metadata parsing | ✅ | f746f84 |
| Fix 2: stop_reason field | ✅ | 7c9bad9 |
| Pushed to remote | ✅ | GitHub |
| ArgoCD sync | ✅ | Stage 02 |
| ConfigMaps updated | ✅ | Both scripts |
| Deployment restarted | ✅ | New pod running |
| Verified in pod | ✅ | Both fixes |
| Ready for testing | ✅ | NOW |

---

**Status**: ✅ **BOTH FIXES DEPLOYED AND READY FOR TESTING**
