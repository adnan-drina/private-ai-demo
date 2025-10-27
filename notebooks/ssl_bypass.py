"""
SSL Certificate Bypass for Self-Signed Certificates
Usage in Jupyter notebooks:
    %run ssl_bypass.py
    # Then run your guidellm/lm_eval commands
"""
import ssl
import warnings
import os

# Suppress warnings
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

# 3. Patch requests.Session.request
try:
    import requests
    _orig_request = requests.Session.request
    def _insecure_request(self, *args, **kwargs):
        kwargs["verify"] = False
        return _orig_request(self, *args, **kwargs)
    requests.Session.request = _insecure_request
except ImportError:
    pass

# 4. Patch httpx (for guidellm)
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

# 5. Set environment variables for subprocesses
os.environ['PYTHONHTTPSVERIFY'] = '0'
os.environ['REQUESTS_CA_BUNDLE'] = ''
os.environ['SSL_CERT_FILE'] = ''
os.environ['CURL_CA_BUNDLE'] = ''

print("✅ Complete SSL bypass installed (ssl + urllib3 + requests + httpx)")
print("   Environment variables set for shell commands:")
print("   - PYTHONHTTPSVERIFY=0")
print("   - REQUESTS_CA_BUNDLE=''")
print("   - SSL_CERT_FILE=''")
print("   - CURL_CA_BUNDLE=''")

