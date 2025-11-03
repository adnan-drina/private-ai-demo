# LlamaStack Deployment Status - RHOAI 2.25

**Date:** November 3, 2025  
**Status:** ⚠️ Partially Working - Service Mesh Connectivity Issue

---

## ✅ Successfully Fixed Issues

### 1. **Image Access** ✅
**Problem:** Could not pull `quay.io/redhat-et/llama-stack:latest` (unauthorized)

**Solution:** 
- Changed to official Red Hat registry: `registry.redhat.io/rhoai/odh-llama-stack-core-rhel9@sha256:86f8d82...`
- Added Red Hat pull secret (`adrina-privateai-pull-secret`) to `rag-workload-sa` ServiceAccount
- Image now pulls successfully (6.2GB)

**Aligned with:** RHOAI 2.25 - Section 2: Activating the Llama Stack Operator

---

### 2. **SCC Permissions** ✅
**Problem:** `fsGroup: 0` rejected by OpenShift restricted-v2 SCC

**Solution:**
- Granted `anyuid` SCC to `rag-workload-sa` ServiceAccount
- Operator automatically sets `fsGroup: 0` (cannot be overridden in LlamaStackDistribution CR)
- Pods now create successfully

**Command:**
```bash
oc adm policy add-scc-to-user anyuid -z rag-workload-sa -n private-ai-demo
```

---

### 3. **Distribution Configuration** ✅
**Problem:** ConfigMap approach for `run.yaml` doesn't work

**Root Cause:** 
- Operator design expects `run.yaml` to be embedded in the distribution image at `/opt/app-root/run.yaml`
- Cannot mount external ConfigMaps for configuration
- Must use pre-built distributions or environment variables

**Solution:**
- Use `distribution.name: "rh-dev"` (pre-configured Red Hat distribution)
- Provide required environment variables: `INFERENCE_MODEL`, `VLLM_URL`, `MILVUS_URI`, etc.
- Operator uses `RELATED_IMAGE_RH_DISTRIBUTION` from its environment

**Aligned with:** RHOAI 2.25 - Section 3.7: Deploying a LlamaStackDistribution instance

---

### 4. **Docling Deployment** ✅
**Problem:** CrashLoopBackOff due to 2GB+ CUDA/PyTorch downloads timing out

**Solution:**
- Increased `readinessProbe.initialDelaySeconds` to 600s (10 minutes)
- Increased `livenessProbe.initialDelaySeconds` to 900s (15 minutes)
- Allows container to complete pip installations before health checks

**Status:** Deployment created, waiting for initial startup to complete

**Aligned with:** RHOAI 2.25 - Section 3.10: Preparing documents with Docling for Llama Stack retrieval

---

## ❌ Remaining Issue: Service Mesh Connectivity

### **Problem**
LlamaStack container crashes with:
```
ValueError: Failed to connect to vLLM at 
  http://mistral-24b-quantized-predictor.private-ai-demo.svc.cluster.local/v1
```

### **Root Cause**

The vLLM InferenceService is a **Knative Service** behind **OpenShift Service Mesh** with **PERMISSIVE mTLS**.

**Service details:**
```yaml
NAME: mistral-24b-quantized-predictor
TYPE: ExternalName
EXTERNAL-IP: knative-local-gateway.istio-system.svc.cluster.local
```

**Test result:**
```bash
curl http://mistral-24b-quantized-predictor.private-ai-demo.svc.cluster.local/v1/models
# Result: Connection reset by peer
```

This is a **Service Mesh access control issue**, not a networking issue.

### **Why It Happens**

1. vLLM InferenceServices use Knative Serving
2. Knative Serving is integrated with OpenShift Service Mesh
3. Service Mesh requires either:
   - **mTLS with sidecars** (client has istio-proxy sidecar)
   - **PERMISSIVE mode + explicit allow policies**
4. LlamaStack pods **do not have istio sidecar** injection enabled
5. Service Mesh **rejects** connections from non-mesh clients even in PERMISSIVE mode

### **This is the SAME issue** we encountered with:
- Tekton testing pipelines (had to use external HTTPS routes)
- Internal cluster-local URLs not working from non-mesh pods

---

## 🔧 Solutions (Ordered by Red Hat Best Practice)

### **Option A: Enable Istio Sidecar Injection** ✅ RECOMMENDED

**Why:** Aligns with Service Mesh architecture, proper mTLS

**How:**
1. Add namespace label for sidecar injection:
```bash
oc label namespace private-ai-demo istio.io/rev=data-science-smcp --overwrite
```

2. Add pod annotation in LlamaStackDistribution (if operator supports it):
```yaml
spec:
  server:
    podOverrides:
      annotations:
        sidecar.istio.io/inject: "true"
        proxy.istio.io/config: '{ "holdApplicationUntilProxyStarts": true }'
```

3. Restart deployment to get sidecar injected

**Challenge:** 
- LlamaStackDistribution operator may not support `podOverrides.annotations`
- Warning seen: `unknown field "spec.server.podOverrides.securityContext"`
- Need to verify if operator supports pod-level annotations

---

### **Option B: Use External HTTPS Route** ⚠️ WORKAROUND

**Why:** Bypasses Service Mesh internal routing

**How:**
```yaml
env:
  - name: VLLM_URL
    value: "https://mistral-24b-quantized-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com/v1"
```

**Pros:**
- Works immediately
- No Service Mesh configuration needed

**Cons:**
- External traffic routing (higher latency)
- Bypasses Service Mesh observability
- Requires cluster CA trust or TLS verification disabled

---

### **Option C: Configure Service Mesh Policies** 🔧 ADVANCED

**Why:** Allow non-mesh pods to access mesh services

**How:**
1. Create PeerAuthentication to allow plaintext:
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: allow-llamastack
  namespace: private-ai-demo
spec:
  selector:
    matchLabels:
      app: mistral-24b-quantized
  mtls:
    mode: PERMISSIVE
```

2. Create AuthorizationPolicy to allow access:
```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-from-llamastack
  namespace: private-ai-demo
spec:
  selector:
    matchLabels:
      app: mistral-24b-quantized
  action: ALLOW
  rules:
  - from:
    - source:
        namespaces: ["private-ai-demo"]
```

**Challenge:**
- May not work if Knative gateway enforces stricter policies
- Requires understanding of current Service Mesh configuration

---

## 📊 Current Status Summary

| Component | Status | Details |
|-----------|--------|---------|
| **Image Pull** | ✅ Working | Using registry.redhat.io with pull secret |
| **SCC Permissions** | ✅ Working | anyuid granted to rag-workload-sa |
| **Pod Creation** | ✅ Working | Pods start successfully |
| **Container Startup** | ⚠️ Partial | Starts but crashes on vLLM connection |
| **Service Mesh Access** | ❌ Blocked | Cannot reach Knative services |
| **Docling** | 🕐 Pending | Waiting for 10min startup |

---

## 🎯 Recommended Next Steps

### **Immediate (Unblock development):**
1. **Try Option B** (External HTTPS route) to test if LlamaStack works functionally
2. **Verify Docling** status after 10 minutes

### **Long-term (Production-ready):**
1. **Implement Option A** (Istio sidecar injection) - verify operator support
2. **Test end-to-end RAG** workflow once connectivity is established
3. **Create KFP pipelines** to replace Tekton (per user request)

---

## 📝 References

### Red Hat Documentation
- **Main Guide:** https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_llama_stack/index
- **Section 2:** Activating the Llama Stack Operator ✅
- **Section 3.7:** Deploying a LlamaStackDistribution instance ✅  
- **Section 3.10:** Preparing documents with Docling for Llama Stack retrieval ✅

### Git Commits
- **Fix commit:** `eb317b1` - Align LlamaStack with RHOAI 2.25 and fix image access
- **Previous implementation:** `ac67bde` - Activate Llama Stack operator

### Related Issues
- **Service Mesh connectivity** - Same issue in Tekton testing pipelines
- **Knative internal URLs** - require mesh membership or external routes

---

## 🔍 Debugging Commands

```bash
# Check LlamaStack status
oc get llamastackdistribution llama-stack -n private-ai-demo
oc get pods -l app=llama-stack -n private-ai-demo
oc logs -l app=llama-stack -c llamastack -n private-ai-demo --tail=50

# Check vLLM connectivity
oc run test-vllm --image=curlimages/curl --rm -i --restart=Never -- \
  curl -sS http://mistral-24b-quantized-predictor.private-ai-demo.svc.cluster.local/v1/models

# Check Service Mesh membership
oc get servicemeshmember -n private-ai-demo
oc get ns private-ai-demo --show-labels | grep istio

# Check if sidecar injection is enabled
oc get pod -l app=llama-stack -n private-ai-demo -o jsonpath='{.items[0].spec.containers[*].name}'
# Expected with sidecar: llamastack istio-proxy

# Check PeerAuthentication
oc get peerauthentication -n private-ai-demo
oc get peerauthentication -n istio-system
```

---

## ✅ What's Working

- ✅ Llama Stack Operator activated and running
- ✅ LlamaStackDistribution CR accepted and processed
- ✅ Image pulls successfully from registry.redhat.io
- ✅ Pods create and start (no longer SCC forbidden)
- ✅ Environment variables configured correctly
- ✅ PVC attached successfully
- ✅ Milvus vector database running (1/1 Ready)
- ✅ DSPA (KFP) all 6 pods running
- ✅ Stage 1 InferenceServices both Ready

## ❌ What's Not Working

- ❌ LlamaStack → vLLM connectivity (Service Mesh)
- ❌ Docling (still in initial startup phase)


