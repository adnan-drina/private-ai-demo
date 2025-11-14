# 🔍 GUARDRAILS INTEGRATION ISSUE - ROOT CAUSE ANALYSIS

## Issue Summary
When the "Enable guardrails" checkbox is checked in llama-stack-playground (Chat or RAG flow), **ALL prompts get blocked**, even legitimate ones with no violations.

---

## Component Status ✅

All guardrails components are **healthy and functional**:

### 1. Guardrails Orchestrator
- **Pod**: `llama-guardrails-6895489545-wpzsd` - Running (2 containers)
- **Status**: Processing requests successfully
- **Detectors**: regex (PII) and hf_toxicity (HAP model)
- **Response Time**: ~3ms average

### 2. HF Toxicity Detector
- **Pod**: `guardrails-hf-toxicity-7795cb8b6c-twng5` - Running
- **Model**: `ibm-granite/granite-guardian-hap-38m`
- **Status**: Responding to requests (HTTP 200)

### 3. LlamaStack Safety Provider
- **Pod**: `llama-stack-74f85c7fbb-cvpzl` - Running
- **Provider**: `trustyai_fms` (TrustyAI Guardrails)
- **Shields**: `regex_guardrail`, `toxicity_guardrail`
- **Status**: Successfully calling guardrails

---

## Root Cause 🐛

The issue is in the **playground code**, specifically in the `_normalize_violation()` function in both `playground-chat.py` and `playground-rag.py`.

### Actual Response Structure from TrustyAI

When guardrails check passes, LlamaStack returns:

```json
{
  "violation": {
    "violation_level": "info",
    "user_message": "Content verified by shield regex_guardrail",
    "metadata": {
      "status": "pass",                    <-- Status is HERE
      "summary": {                          <-- Summary is HERE
        "messages_with_violations": 0,
        "total_violations_found": 0,
        "messages_passed": 1
      }
    }
  }
}
```

### Problem in Code

**File**: `playground-chat.py` (lines 44-73) and `playground-rag.py` (lines 122-151)

```python
def _normalize_violation(payload: object) -> Optional[object]:
    if payload is None:
        return None

    # BUG: Looking for payload.status, but it's at payload.metadata.status
    status_raw = _extract_attr(payload, "status")  # ❌ Returns None
    status_value = None
    if isinstance(status_raw, str):
        status_value = status_raw.lower()
    elif hasattr(status_raw, "value"):
        status_value = str(status_raw.value).lower()
    elif status_raw is not None:
        status_value = str(status_raw).lower()
    if status_value in {"pass", "verified", "ok"}:
        return None  # Never reached because status_raw is None!

    # BUG: Looking for payload.summary, but it's at payload.metadata.summary
    summary = _extract_attr(payload, "summary")  # ❌ Returns None
    if summary is not None:
        messages_with_violations = _extract_attr(summary, "messages_with_violations", 0)
        total_violations = _extract_attr(summary, "total_violations_found", 0)
        
        if messages_with_violations == 0 and total_violations == 0:
            return None  # Never reached because summary is None!

    return payload  # ⚠️ Always returns the payload as a violation!
```

### Why Everything Gets Blocked

1. When guardrails are enabled, `_run_guardrail()` is called
2. It calls LlamaStack's `safety.run_shield()`
3. Even when content passes, a `violation` object is returned (with status="pass")
4. `_normalize_violation()` receives this violation object
5. It tries to find `status` and `summary` at the top level (they're in `metadata`)
6. Both checks fail, so it returns the full `payload`
7. The playground treats ANY returned payload as a violation
8. The prompt is blocked with the "pass" message shown as an error!

---

## Evidence from Logs 📋

### LlamaStack Log (showing successful check):
```
output: {'violation': {'violation_level': 'info', 
  'user_message': 'Content verified by shield regex_guardrail (1 messages processed)', 
  'metadata': {
    'status': 'pass',   # ✅ Content passed
    'summary': {
      'messages_with_violations': 0,  # ✅ No violations
      'total_violations_found': 0     # ✅ No violations
    }
  }
}}
```

This is a **passing** check, but the playground sees it as a violation!

---

## Impact 📊

**Severity**: HIGH - Feature is completely broken

**Affected Components**:
- Chat flow in llama-stack-playground
- RAG flow in llama-stack-playground
- Both shields (regex_guardrail and toxicity_guardrail)

**User Experience**:
- Users cannot use guardrails at all
- All prompts are blocked regardless of content
- Confusing error message: "Content verified..." shown as a blocker

---

## Fix Required 🔧

The `_normalize_violation()` function needs to check for status and summary inside the `metadata` object:

### Option 1: Check metadata first
```python
def _normalize_violation(payload: object) -> Optional[object]:
    if payload is None:
        return None

    # First, check metadata if it exists
    metadata = _extract_attr(payload, "metadata")
    if metadata is not None:
        # Check status in metadata
        status_raw = _extract_attr(metadata, "status")
        # ... rest of status checking logic ...
        
        # Check summary in metadata
        summary = _extract_attr(metadata, "summary")
        # ... rest of summary checking logic ...
    
    # Fallback to top-level attributes (for backward compatibility)
    status_raw = _extract_attr(payload, "status")
    # ... continue with existing logic ...
```

### Option 2: Check both locations
```python
# Try metadata.status first, then top-level status
metadata = _extract_attr(payload, "metadata")
status_raw = _extract_attr(metadata, "status") if metadata else None
if status_raw is None:
    status_raw = _extract_attr(payload, "status")
```

---

## Additional Issues Identified 🔍

### 1. violation_level Not Checked
The response includes `violation_level: "info"` which indicates an informational message, not an actual violation. The code should also check this field.

### 2. Inconsistent API Response Structure
The TrustyAI provider's response structure nests important fields in `metadata`, which is inconsistent with how the playground code expects them at the top level. This suggests either:
- The provider format changed, OR
- The playground code was written for a different provider format

---

## Testing Recommendations 🧪

After fixing, test with:
1. ✅ Valid prompt with no violations
2. ❌ Prompt with PII (email, SSN, credit card)
3. ❌ Toxic content
4. ✅ Edge cases (empty prompts, very long prompts)
5. Both shields (regex_guardrail and toxicity_guardrail)
6. Both flows (Chat and RAG)

---

## Configuration Files Reviewed ✓

All configuration is correct:
- `guardrails-configmap.yaml` - Detectors properly configured
- `configmap.yaml` (LlamaStack) - Shields properly registered
- `guardrails-orchestrator.yaml` - Orchestrator configured correctly
- `hf-detector-deployment.yaml` - Detector running with HAP model

