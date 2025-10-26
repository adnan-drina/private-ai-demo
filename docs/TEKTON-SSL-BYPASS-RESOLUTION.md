# Tekton LM-Eval SSL Bypass - Complete Resolution

**Date:** October 26, 2025  
**Status:** ✅ **RESOLVED**  
**Branch:** `feature/pipeline-3-tasks`

---

## 🎯 Executive Summary

Successfully resolved the persistent SSL verification error in the Tekton `run-lm-eval` task that was preventing evaluation of models deployed behind self-signed OpenShift routes. The solution involved implementing a **three-layer SSL bypass strategy** with careful stdout management to avoid command pollution.

---

## 🔥 The Problem

### Initial Error
```
requests.exceptions.SSLError: 
CERTIFICATE_VERIFY_FAILED: self-signed certificate
```

**Where:** `lm_eval/models/api_models.py` → `model_call()` → `requests.post(...)`

**Why it happened:**
- OpenShift InferenceServices use self-signed SSL certificates by default
- `lm-eval` uses the `requests` library to call model endpoints
- `requests` → `urllib3` explicitly validates SSL certificates
- Standard environment variables (`PYTHONHTTPSVERIFY=0`, `SSL_CERT_FILE=""`) do NOT work for `requests`

---

## ❌ What Didn't Work

### Attempt 1: Environment Variables
```yaml
env:
  - name: PYTHONHTTPSVERIFY
    value: "0"
  - name: SSL_CERT_FILE
    value: ""
```
**Result:** ❌ Failed  
**Reason:** `requests` and `urllib3` ignore these variables

### Attempt 2: Basic `sitecustomize.py` with `ssl.create_default_context` override
```python
ssl.create_default_context = lambda *a, **k: insecure_context
```
**Result:** ❌ Failed  
**Reason:** `urllib3` uses its own `create_urllib3_context()` which bypasses the standard SSL context

### Attempt 3: `aiohttp` connector patching
```python
aiohttp.TCPConnector.__init__ = patched_init
```
**Result:** ❌ Failed  
**Reason:** `lm-eval` uses `requests`, not `aiohttp`

### Attempt 4: Switching to `local-chat-completions` backend
**Result:** ❌ Failed  
**Reason:** `NotImplementedError: Loglikelihood is not supported` for this backend

---

## ✅ The Solution

### Three-Layer SSL Bypass Strategy

Implemented in `/gitops/stage01-model-serving/serving/pipelines/01-tasks/task-run-lm-eval.yaml`:

```bash
# Layer 1: SSL Context Override
ssl._create_default_https_context = ssl._create_unverified_context
def _insecure_ctx(*args, **kwargs):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx
ssl.create_default_context = _insecure_ctx

# Layer 2: Urllib3 Warnings Suppression
import urllib3
urllib3.disable_warnings()

# Layer 3: Force requests to ALWAYS use verify=False (THE KEY FIX!)
import requests
_orig_request = requests.Session.request
def _insecure_request(self, *args, **kwargs):
    kwargs["verify"] = False  # ← THIS IS THE CRITICAL LINE
    return _orig_request(self, *args, **kwargs)
requests.Session.request = _insecure_request
```

**Why this works:**
- Layer 3 **monkeypatches `requests.Session.request`** to force `verify=False` at the exact layer where SSL validation occurs
- Even if `lm-eval` or any other code tries to pass `verify=True`, it's overridden
- This guarantees all HTTP requests bypass SSL verification

---

## 🐛 Additional Issues Resolved

### Issue 1: Model Name Mismatch
**Problem:**
```
404: The model `mistralai/Mistral-Small-24B-Instruct-2501` does not exist
```

**Cause:** vLLM serves models with internal names (e.g., `mistral-24b-quantized`), not HuggingFace IDs

**Solution:**
```bash
# Dynamically fetch model name from vLLM /v1/models endpoint
VLLM_MODEL_NAME=$(curl -ks "${MODEL_URL}/v1/models" | python3 -c "import sys, json; print(json.load(sys.stdin)['data'][0]['id'])")

# Use vLLM name for API, HuggingFace name for tokenizer
python3 -m lm_eval \
  --model local-completions \
  --model_args "model=${VLLM_MODEL_NAME},tokenizer=mistralai/Mistral-Small-24B-Instruct-2501,..."
```

### Issue 2: Print Statement Pollution
**Problem:**
```
The model `🔥 SSL verification disabled: ALL requests use verify=False\nmistral-24b-quantized` does not exist
```

**Cause:** A `print()` statement in `sitecustomize.py` was polluting `stdout`, which was captured by the `curl` command

**Solution:** Removed the `print()` statement from `sitecustomize.py`

---

## 📊 Performance Metrics

### vLLM Performance (Quantized Model - 1 GPU)
```
Avg Prompt Throughput:     320-560 tokens/s
Avg Generation Throughput: 9.6 tokens/s
GPU KV Cache Usage:        0.0% (idle between requests)
Concurrent Requests:       1 (sequential)
```

### LM-Eval Execution
```
Status:           Running (54% complete - 2171/3998 requests)
Evaluation Rate:  ~9.7 iterations/s
Estimated Time:   ~7-8 minutes total
Tasks:            hellaswag, arc_easy
Limit:            500 samples per task
```

---

## 🔄 Pattern for Future Use

### For ANY Python task calling self-signed HTTPS endpoints in Tekton:

```yaml
script: |
  #!/bin/bash
  set -e
  
  # Install dependencies
  pip install --quiet --no-cache-dir your-packages
  
  # Install sitecustomize.py AFTER pip install
  SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")
  echo 'import ssl, warnings' > $SITE_PACKAGES/sitecustomize.py
  echo 'warnings.filterwarnings("ignore")' >> $SITE_PACKAGES/sitecustomize.py
  echo 'ssl._create_default_https_context = ssl._create_unverified_context' >> $SITE_PACKAGES/sitecustomize.py
  echo 'def _insecure_ctx(*args, **kwargs):' >> $SITE_PACKAGES/sitecustomize.py
  echo '    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)' >> $SITE_PACKAGES/sitecustomize.py
  echo '    ctx.check_hostname = False' >> $SITE_PACKAGES/sitecustomize.py
  echo '    ctx.verify_mode = ssl.CERT_NONE' >> $SITE_PACKAGES/sitecustomize.py
  echo '    return ctx' >> $SITE_PACKAGES/sitecustomize.py
  echo 'ssl.create_default_context = _insecure_ctx' >> $SITE_PACKAGES/sitecustomize.py
  echo 'import urllib3' >> $SITE_PACKAGES/sitecustomize.py
  echo 'urllib3.disable_warnings()' >> $SITE_PACKAGES/sitecustomize.py
  echo 'import requests' >> $SITE_PACKAGES/sitecustomize.py
  echo '_orig_request = requests.Session.request' >> $SITE_PACKAGES/sitecustomize.py
  echo 'def _insecure_request(self, *args, **kwargs):' >> $SITE_PACKAGES/sitecustomize.py
  echo '    kwargs["verify"] = False' >> $SITE_PACKAGES/sitecustomize.py
  echo '    return _orig_request(self, *args, **kwargs)' >> $SITE_PACKAGES/sitecustomize.py
  echo 'requests.Session.request = _insecure_request' >> $SITE_PACKAGES/sitecustomize.py
  
  # Run your code (sitecustomize.py loads automatically)
  python3 your_script.py
```

**Key principles:**
1. Install `sitecustomize.py` **AFTER** `pip install` (to avoid breaking package installation)
2. Do NOT include `print()` statements in `sitecustomize.py` (they pollute stdout)
3. Monkeypatch `requests.Session.request` to force `verify=False`

---

## 🔒 Security Considerations

### ⚠️ THIS IS NOT FOR PRODUCTION

This SSL bypass is **ONLY** appropriate for:
- Demo clusters
- Airgapped labs
- CI/CD smoke tests
- Development environments

### For Production:
1. Extract the OpenShift router CA certificate
2. Mount it as a ConfigMap/Secret in the Tekton Task
3. Set `REQUESTS_CA_BUNDLE` and `SSL_CERT_FILE` to the certificate path
4. DO NOT use `sitecustomize.py` monkeypatching

Example:
```yaml
volumeMounts:
  - name: router-ca
    mountPath: /etc/ssl/certs/router-ca.crt
    subPath: ca.crt
env:
  - name: REQUESTS_CA_BUNDLE
    value: /etc/ssl/certs/router-ca.crt
  - name: SSL_CERT_FILE
    value: /etc/ssl/certs/router-ca.crt
```

---

## 📝 Commit History

1. **`02c935a`** - `fix: Complete SSL bypass - patch requests.Session.request`
   - Implemented the three-layer SSL bypass
   - Added `requests.Session.request` monkeypatch (the critical fix)

2. **`85bd4c5`** - `fix: Use correct vLLM model name for lm-eval`
   - Dynamically fetch model name from `/v1/models` endpoint
   - Separate vLLM name for API vs HuggingFace name for tokenizer

3. **`0ac7e6b`** - `fix: Remove sitecustomize.py print statement`
   - Removed interfering `print()` that was polluting stdout
   - Fixed model name extraction

---

## ✅ Validation

### Pipeline B Status
```bash
$ oc get pipelinerun test-mistral-quantized-7vpbs -n private-ai-demo
NAME                           STATUS    REASON
test-mistral-quantized-7vpbs   Unknown   Running
```

### Logs Confirmation
```
✅ Complete SSL bypass installed (no verification, no warnings)
📋 vLLM model name: mistral-24b-quantized
🚀 Starting evaluation...
Requesting API:  54%|█████▍    | 2171/3998 [04:01<03:07,  9.77it/s]
```

**No SSL errors!** 🎉

---

## 🎓 Key Learnings

1. **`requests` library is stubborn** - It doesn't respect standard SSL environment variables
2. **Monkeypatch at the call site** - Override `requests.Session.request` to force behavior
3. **`sitecustomize.py` is powerful** - But keep it silent (no print statements)
4. **vLLM model names matter** - Always fetch the actual model ID from `/v1/models`
5. **Tekton stdout is precious** - Any pollution will break downstream commands

---

## 🔗 References

- Red Hat `model-car-importer` project: Used similar `sitecustomize.py` pattern
- Tekton v1 API: Task-level timeouts, ServiceAccount handling
- vLLM API: `/v1/models` endpoint for model discovery
- lm-eval harness: `local-completions` backend documentation

---

## 👥 Contributors

- Analysis and resolution by the AI team
- Pattern inspired by Red Hat's `model-car-importer` project
- User feedback and testing: @adrina

---

**Status:** Pipeline B is now running successfully with SSL bypass fully operational! 🚀

