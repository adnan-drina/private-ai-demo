# SSL Fix for Benchmark Notebooks

## Add This Cell at the Very Top of Your Notebook

**Cell 1: SSL Bypass (Run First!)**

```python
# ===================================================================
# SSL Certificate Bypass for Self-Signed Certificates
# Run this cell FIRST before any benchmark commands
# ===================================================================
import ssl
import warnings
import os
import sys

# Suppress all warnings
warnings.filterwarnings('ignore')

# 1. Kill SSL verification at socket layer
ssl._create_default_https_context = ssl._create_unverified_context

def _insecure_ctx(*args, **kwargs):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx

ssl.create_default_context = _insecure_ctx

# 2. Silence urllib3 warnings
try:
    import urllib3
    urllib3.disable_warnings()
except ImportError:
    pass

# 3. Patch requests.Session.request (for lm_eval)
try:
    import requests
    _orig_request = requests.Session.request
    def _insecure_request(self, *args, **kwargs):
        kwargs["verify"] = False
        return _orig_request(self, *args, **kwargs)
    requests.Session.request = _insecure_request
except ImportError:
    pass

# 4. Patch httpx Client and AsyncClient (for guidellm)
try:
    import httpx
    
    # Patch sync client
    _orig_httpx_client = httpx.Client
    def _insecure_httpx_client(*args, **kwargs):
        kwargs["verify"] = False
        return _orig_httpx_client(*args, **kwargs)
    httpx.Client = _insecure_httpx_client
    
    # Patch async client
    _orig_httpx_async = httpx.AsyncClient
    def _insecure_httpx_async(*args, **kwargs):
        kwargs["verify"] = False
        return _orig_httpx_async(*args, **kwargs)
    httpx.AsyncClient = _insecure_httpx_async
except ImportError:
    pass

# 5. Set environment variables for subprocess commands
os.environ['PYTHONHTTPSVERIFY'] = '0'
os.environ['REQUESTS_CA_BUNDLE'] = ''
os.environ['SSL_CERT_FILE'] = ''
os.environ['CURL_CA_BUNDLE'] = ''

# 6. Create sitecustomize.py for shell commands
import site
site_packages = site.getsitepackages()[0]
sitecustomize_path = os.path.join(site_packages, 'sitecustomize.py')

sitecustomize_content = '''
import ssl
import warnings

warnings.filterwarnings("ignore")

# SSL bypass
ssl._create_default_https_context = ssl._create_unverified_context

def _insecure_ctx(*args, **kwargs):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx

ssl.create_default_context = _insecure_ctx

# urllib3
try:
    import urllib3
    urllib3.disable_warnings()
except ImportError:
    pass

# requests
try:
    import requests
    _orig_request = requests.Session.request
    def _insecure_request(self, *args, **kwargs):
        kwargs["verify"] = False
        return _orig_request(self, *args, **kwargs)
    requests.Session.request = _insecure_request
except ImportError:
    pass

# httpx
try:
    import httpx
    _orig_httpx_client = httpx.Client
    def _insecure_httpx_client(*args, **kwargs):
        kwargs["verify"] = False
        return _orig_httpx_client(*args, **kwargs)
    httpx.Client = _insecure_httpx_client
    
    _orig_httpx_async = httpx.AsyncClient
    def _insecure_httpx_async(*args, **kwargs):
        kwargs["verify"] = False
        return _orig_httpx_async(*args, **kwargs)
    httpx.AsyncClient = _insecure_httpx_async
except ImportError:
    pass
'''

try:
    with open(sitecustomize_path, 'w') as f:
        f.write(sitecustomize_content)
    print(f"✅ Created {sitecustomize_path}")
except Exception as e:
    print(f"⚠️  Could not create sitecustomize.py: {e}")
    print("   (This is OK - other bypasses will still work)")

print("=" * 60)
print("✅ Complete SSL bypass installed!")
print("=" * 60)
print("Layers activated:")
print("  1. SSL socket layer (ssl.create_default_context)")
print("  2. urllib3 warnings disabled")
print("  3. requests.Session.request patched (verify=False)")
print("  4. httpx.Client/AsyncClient patched (verify=False)")
print("  5. Environment variables set for subprocesses")
print("  6. sitecustomize.py created for shell commands")
print("=" * 60)
print("You can now run guidellm and lm_eval commands!")
print("=" * 60)
```

## Then Update Your Benchmark Cells

### For GuideLLM Cells:

**Before (fails with SSL error):**
```python
!guidellm benchmark \
    --target "https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1" \
    --model "mistral-24b-quantized" \
    --data "prompt_tokens=512,output_tokens=512,samples=100" \
    --rate-type constant \
    --rate 1
```

**After (works!):**
```python
# Make sure you ran the SSL bypass cell first!
!guidellm benchmark \
    --target "https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1" \
    --model "mistral-24b-quantized" \
    --data "prompt_tokens=512,output_tokens=512,samples=100" \
    --rate-type constant \
    --rate 1
```

### For lm_eval Cells:

**Before (fails with SSL error):**
```python
!lm_eval \
    --model local-completions \
    --model_args "model=mistral-24b-quantized,base_url=https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1" \
    --tasks hellaswag,arc_easy \
    --limit 100
```

**After (works!):**
```python
# Make sure you ran the SSL bypass cell first!
!lm_eval \
    --model local-completions \
    --model_args "model=mistral-24b-quantized,tokenizer=mistralai/Mistral-Small-24B-Instruct-2501,base_url=https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1/completions" \
    --tasks hellaswag,arc_easy,truthfulqa_mc2 \
    --limit 100
```

## Complete Example Notebook Structure

```
Cell 1: [SSL Bypass Code] (from above)
Cell 2: Import libraries and setup
Cell 3: Define model URLs
Cell 4: Run GuideLLM benchmarks
Cell 5: Run lm_eval evaluation
Cell 6: Display results
```

## Testing the Fix

After adding the SSL bypass cell, test it with:

```python
import requests
import httpx

# Test with requests
try:
    r = requests.get("https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1/models")
    print(f"✅ requests test: {r.status_code}")
except Exception as e:
    print(f"❌ requests test failed: {e}")

# Test with httpx
try:
    client = httpx.Client()
    r = client.get("https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1/models")
    print(f"✅ httpx test: {r.status_code}")
except Exception as e:
    print(f"❌ httpx test failed: {e}")
```

## If It Still Fails

If you still see SSL errors after adding the bypass cell:

1. **Restart the kernel** and run the SSL bypass cell again
2. Check that the SSL bypass cell completed without errors
3. Make sure the SSL bypass cell is the **very first cell** that runs
4. Try running this diagnostic:

```python
import ssl
print(f"Default context: {ssl._create_default_https_context}")
print(f"Verify mode: {ssl.create_default_context().verify_mode}")

import httpx
client = httpx.Client()
print(f"httpx verify: {client._transport._pool._ssl_context.verify_mode if hasattr(client._transport._pool, '_ssl_context') else 'unknown'}")
```

## Alternative: Use %%bash with Environment Variables

If the Python approach doesn't work, use bash cells:

```bash
%%bash
export PYTHONHTTPSVERIFY=0
export REQUESTS_CA_BUNDLE=""
export SSL_CERT_FILE=""
export CURL_CA_BUNDLE=""

guidellm benchmark \
    --target "https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1" \
    --model "mistral-24b-quantized" \
    --data "prompt_tokens=512,output_tokens=512,samples=100" \
    --rate-type constant \
    --rate 1
```

