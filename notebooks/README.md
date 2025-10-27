# Notebook SSL Certificate Fix

## Problem
When running `guidellm` or `lm_eval` commands from notebooks against OpenShift routes with self-signed certificates, you'll get:
```
SSL: CERTIFICATE_VERIFY_FAILED
```

## Solution

### Option 1: Use the SSL Bypass Helper (Recommended)

Add this at the **top of your notebook**, before running any benchmarks:

```python
%run /opt/app-root/src/notebooks/ssl_bypass.py
```

Then run your guidellm/lm_eval commands normally:

```bash
%%bash
guidellm benchmark \
    --target "https://mistral-24b-quantized-private-ai-demo.apps.cluster-xxx.opentlc.com/v1" \
    --model "mistral-24b-quantized" \
    ...
```

### Option 2: Inline SSL Bypass

Add this code block at the top of your notebook:

```python
import ssl, warnings, os
warnings.filterwarnings('ignore')

# Kill SSL verification
ssl._create_default_https_context = ssl._create_unverified_context
def _insecure_ctx(*args, **kwargs):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx
ssl.create_default_context = _insecure_ctx

# Silence urllib3
import urllib3
urllib3.disable_warnings()

# Patch requests
import requests
_orig_request = requests.Session.request
def _insecure_request(self, *args, **kwargs):
    kwargs["verify"] = False
    return _orig_request(self, *args, **kwargs)
requests.Session.request = _insecure_request

# Patch httpx (for guidellm)
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

# Environment variables for shell commands
os.environ['PYTHONHTTPSVERIFY'] = '0'
os.environ['REQUESTS_CA_BUNDLE'] = ''
os.environ['SSL_CERT_FILE'] = ''

print("✅ SSL bypass installed")
```

### Option 3: For Shell Commands Only

If you're ONLY using `!command` or `%%bash`, add this before your commands:

```python
import os
os.environ['PYTHONHTTPSVERIFY'] = '0'
os.environ['REQUESTS_CA_BUNDLE'] = ''
os.environ['SSL_CERT_FILE'] = ''
os.environ['CURL_CA_BUNDLE'] = ''
```

Then:

```bash
%%bash
export PYTHONHTTPSVERIFY=0
export REQUESTS_CA_BUNDLE=""
export SSL_CERT_FILE=""

guidellm benchmark ...
```

## Files

- `ssl_bypass.py` - Reusable SSL bypass helper script
- This file will be automatically available in your workbench at `/opt/app-root/src/notebooks/ssl_bypass.py`

## Why This Works

The bypass operates at 4 layers:
1. **SSL socket layer** - Disables cert verification at the lowest level
2. **urllib3** - Silences insecure request warnings
3. **requests** - Forces `verify=False` on all HTTP requests
4. **httpx** - Forces `verify=False` (used by GuideLLM)
5. **Environment variables** - For subprocess/shell commands

## Testing

After adding the SSL bypass, test with:

```python
import requests
response = requests.get("https://mistral-24b-quantized-private-ai-demo.apps.cluster-xxx.opentlc.com/v1/models")
print(f"Status: {response.status_code}")  # Should be 200
```

## Production Note

⚠️ **This bypass should ONLY be used in development/demo environments with self-signed certificates.**

In production, use proper TLS certificates from a trusted CA.

