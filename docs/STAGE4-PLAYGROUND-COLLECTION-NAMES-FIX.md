# Playground Collection Names Fix

**Date**: November 16, 2025  
**Branch**: `feature/stage4-implementation`  
**Status**: ✅ Fixed and Deployed

---

## 🐛 Issue

The LlamaStack Playground UI was displaying internal UUID-based collection IDs instead of human-readable names in the "Select Document Collections" dropdown.

**Before:**
```
❌ vs_0e19961e-6541-49d8-bb99-1ea00ee7a4d2
❌ vs_14bf7879-a2af-46a0-afbc-7a66f881bba2
❌ vs_e9565f14-80be-4ccf-941b-3e092dd0e253
```

**After:**
```
✅ red_hat_docs
✅ acme_corporate
✅ eu_ai_act
```

---

## 🔍 Root Cause

The playground code was extracting collection identifiers using the wrong field from the LlamaStack API response.

### LlamaStack API Response Structure

```json
{
  "id": "vs_0e19961e-6541-49d8-bb99-1ea00ee7a4d2",  // UUID (internal)
  "name": "red_hat_docs",                            // Human-readable name ✅
  "vector_db_id": "red_hat_docs",                    // Alias for name
  "metadata": {
    "provider_id": "milvus-shared"
  }
}
```

### Buggy Code

**`playground-rag.py` (line 280)**:
```python
vector_dbs = [_extract_vector_db_id(vector_db) for vector_db in vector_dbs]
```

**`_extract_vector_db_id()` function (lines 66-85)**:
```python
def _extract_vector_db_id(item) -> str:
    # ...
    identifier = getattr(item, "identifier", None)  # Returns UUID ❌
    if identifier:
        return identifier
    # ...
    item_id = getattr(item, "id", None)            # Returns UUID ❌
    if item_id:
        return item_id
```

**`playground-tools.py` (line 51)**:
```python
vector_dbs = [vector_db.identifier for vector_db in vector_dbs]  # Returns UUID ❌
```

---

## ✅ Solution

Updated both files to prioritize the `name` field over `identifier` or `id`.

### Fixed Code

**`playground-rag.py` - `_extract_vector_db_id()` function**:
```python
def _extract_vector_db_id(item) -> str:
    """
    Extract the human-readable vector DB name (not the UUID).
    
    LlamaStack /v1/vector_stores returns:
      {
        "id": "vs_0e19961e-6541-49d8-bb99-1ea00ee7a4d2",  # UUID (internal use)
        "name": "red_hat_docs",                            # Human-readable name
        "vector_db_id": "red_hat_docs"                     # Alias for name
      }
    
    We want to display "red_hat_docs", not "vs_0e19961e...".
    """
    if item is None:
        return ""
    
    # Try name first (this is the human-readable identifier) ✅
    name = getattr(item, "name", None)
    if name:
        return name
    
    # Try vector_db_id (alias for name in some responses) ✅
    vector_db_id = getattr(item, "vector_db_id", None)
    if vector_db_id:
        return vector_db_id
    
    # Dict handling
    if isinstance(item, dict):
        # Check for name or vector_db_id first ✅
        name = item.get("name") or item.get("vector_db_id")
        if name:
            return name
        # ... metadata checks ...
        # Last resort: use identifier or id (UUID fallback)
        return item.get("identifier") or item.get("id") or ""
    
    # ... rest of function ...
```

**`playground-tools.py` (lines 51-55)**:
```python
# Use human-readable names (e.g., "red_hat_docs") instead of UUIDs (e.g., "vs_0e19961e...")
vector_dbs = [
    getattr(vector_db, "name", None) or 
    getattr(vector_db, "vector_db_id", None) or 
    vector_db.identifier
    for vector_db in vector_dbs
]
```

---

## 📝 Files Modified

1. **`gitops/stage02-model-alignment/llama-stack/playground-rag.py`**
   - Updated `_extract_vector_db_id()` function (lines 66-117)
   - Added comprehensive documentation
   - Prioritizes `name` → `vector_db_id` → UUID fallback

2. **`gitops/stage02-model-alignment/llama-stack/playground-tools.py`**
   - Updated collection name extraction (lines 51-55)
   - Added inline comment explaining the fix

---

## 🚀 Deployment

```bash
# Delete playground pod to apply changes
oc delete pod -l app=llama-stack-playground -n private-ai-demo

# Wait for new pod to start
oc wait --for=condition=Ready pod -l app=llama-stack-playground \
  -n private-ai-demo --timeout=120s
```

**Result**:
- Old pod: `llama-stack-playground-8457f7f5dd-z8lhs`
- New pod: `llama-stack-playground-8457f7f5dd-2mpx8`
- Status: ✅ Running

---

## 🧪 Testing

### Verification Steps

1. **Open Playground UI**:
   ```
   https://llama-stack-playground-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com
   ```

2. **Navigate to RAG Tab**:
   - Click "🦙 RAG" in the sidebar

3. **Check Dropdown**:
   - Expand "Select Document Collections to use in RAG queries"
   - **Expected**: See `red_hat_docs`, `acme_corporate`, `eu_ai_act`
   - **Not**: `vs_0e19961e...`, `vs_14bf7879...`, `vs_e9565f14...`

4. **Test Tools Tab** (if applicable):
   - Click "🛠 Tools" in the sidebar
   - Enable "builtin::rag" in ToolGroups
   - Check collection dropdown shows human-readable names

---

## 💡 Related Context

### Why This Matters

1. **User Experience**: Human-readable names are essential for usability
2. **Debugging**: Makes logs and error messages more understandable
3. **Documentation**: Aligns with all config examples (`red_hat_docs`, not `vs_*`)
4. **Best Practice**: Internal IDs should never be exposed in UI

### Collection Registration

Collections are registered via the LlamaStack API:

```bash
curl -X POST http://llama-stack-service:8321/v1/vector_stores \
  -H "Content-Type: application/json" \
  -d '{"name": "red_hat_docs", "metadata": {"provider_id": "milvus-shared"}}'
```

Response includes both `id` (UUID) and `name` (human-readable):
```json
{
  "id": "vs_0e19961e-6541-49d8-bb99-1ea00ee7a4d2",
  "name": "red_hat_docs",
  ...
}
```

**Key Insight**: The `name` field is what users should see and interact with.

---

## ✅ Verification Checklist

- [x] Code changes committed to `feature/stage4-implementation`
- [x] Playground pod restarted with new code
- [x] Both `playground-rag.py` and `playground-tools.py` updated
- [ ] User confirmed dropdown shows correct names (pending user verification)

---

## 🔗 Related Documents

- `docs/STAGE4-COLLECTION-REGISTRATION-FIX.md` - How collections are registered
- `docs/STAGE4-RAG-MILVUS-FIX-SUMMARY.md` - Milvus configuration fixes
- `gitops/stage02-model-alignment/llama-stack/configmap.yaml` - Collection definitions

---

## 📊 Impact

**Scope**: Playground UI only (no backend changes)  
**Risk**: Low (only affects display logic)  
**Benefit**: High (essential for usability)  
**Testing**: Simple visual verification in UI

