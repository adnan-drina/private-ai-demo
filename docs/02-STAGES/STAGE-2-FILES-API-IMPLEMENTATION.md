# LlamaStack Files API Implementation - MinIO Backend

**Date:** November 3, 2025  
**Status:** ✅ Configured (Ready to Apply)

---

## Overview

Implemented operator-aligned Files API configuration for LlamaStack, backed by MinIO object storage. This enables RAG document storage and management while keeping the LlamaStackDistribution CR pattern.

**Key Design Decisions:**
- ✅ Keep LlamaStackDistribution CR (operator-managed)
- ✅ Use MinIO S3-compatible API for Files backend
- ✅ External HTTPS routes for vLLM (bypass Service Mesh issue)
- ✅ Internal gRPC for Milvus (unchanged)
- ✅ Secrets created imperatively (not in Git)

---

## 📋 Changes Implemented

### 1. **MinIO Bootstrap Job** ✅
**File:** `gitops/stage00-ai-platform/minio/job-bootstrap-buckets.yaml`

Added `llama-files` bucket creation:
```bash
# Bucket for LlamaStack Files API
if mc mb minio/llama-files --ignore-existing --insecure; then
  echo "✅ Created bucket: llama-files"
else
  echo "ℹ️  Bucket llama-files already exists"
fi

# Enable versioning
mc version enable minio/llama-files
echo "✅ Versioning enabled for llama-files"
```

**Purpose:** Dedicated bucket for RAG document storage, separate from model weights.

---

### 2. **Secret Template** ✅
**File:** `gitops/stage02-model-alignment/llama-stack/secret-llama-files.yaml.template`

Template for MinIO credentials (NOT applied directly):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: llama-files-credentials
  namespace: private-ai-demo
type: Opaque
stringData:
  accesskey: "<MINIO_ACCESS_KEY>"
  secretkey: "<MINIO_SECRET_KEY>"
```

**Important:** 
- ❌ NOT included in kustomization.yaml
- ✅ Created imperatively by deploy.sh
- ✅ Never committed to Git history

---

### 3. **Deploy Script** ✅
**File:** `stages/stage2-model-alignment/deploy.sh`

Added secret creation logic:
```bash
# Copy credentials from model-storage namespace (source of truth)
ACCESS=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d)
SECRET=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d)

oc -n private-ai-demo create secret generic llama-files-credentials \
  --from-literal=accesskey="$ACCESS" \
  --from-literal=secretkey="$SECRET" \
  --dry-run=client -o yaml | oc apply -f -
```

**Pattern:** Same as Stage 1/2 secret management (consistent, reproducible).

---

### 4. **LlamaStackDistribution** ✅
**File:** `gitops/stage02-model-alignment/llama-stack/llamastack-distribution.yaml`

Added FILES_S3_* environment variables:
```yaml
env:
  # Files API configuration (S3/MinIO backend)
  - name: FILES_S3_ENDPOINT
    value: "http://minio.model-storage.svc:9000"
  - name: FILES_S3_BUCKET
    value: "llama-files"
  - name: FILES_S3_REGION
    value: "us-east-1"
  - name: FILES_S3_TLS_VERIFY
    value: "false"
  - name: FILES_S3_FORCE_PATH_STYLE
    value: "true"
  - name: FILES_S3_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: llama-files-credentials
        key: accesskey
  - name: FILES_S3_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: llama-files-credentials
        key: secretkey
```

**Pattern:** 
- Credentials injected from secret (not hardcoded)
- Environment variables passed to container
- ConfigMap reads from env vars (no secrets in ConfigMap)

---

### 5. **ConfigMap (run.yaml)** ✅
**File:** `gitops/stage02-model-alignment/llama-stack/configmap.yaml`

Added Files API and provider:
```yaml
apis:
  - inference
  - agents
  - safety
  - telemetry
  - tool_runtime
  - vector_io
  - files  # NEW: Files API

providers:
  files:
    # S3/MinIO files provider for RAG document storage
    - provider_id: s3-files
      provider_type: remote::s3-files
      config:
        endpoint_url: "http://minio.model-storage.svc:9000"
        bucket: "llama-files"
        region: "us-east-1"
        tls_verify: false
        s3_force_path_style: true
        # Credentials read from environment variables
        credentials:
          access_key_id_from_env: "FILES_S3_ACCESS_KEY_ID"
          secret_access_key_from_env: "FILES_S3_SECRET_ACCESS_KEY"
```

**Pattern:**
- Provider reads credentials from process env
- No secrets in ConfigMap (secure)
- Operator injects env vars into pod

---

### 6. **Kustomization** ✅
**File:** `gitops/stage02-model-alignment/llama-stack/kustomization.yaml`

Verified resources:
```yaml
resources:
  - serviceaccount.yaml
  - configmap.yaml  # ✅ Includes Files config
  - pvc.yaml
  - llamastack-distribution.yaml  # ✅ Includes FILES_S3_* env
  - service.yaml
  - route.yaml
  - servicemonitor.yaml
  # ❌ NOT including secret-llama-files.yaml.template (correct)
```

---

## 📊 Configuration Summary

### **Files API**
| Setting | Value |
|---------|-------|
| **Provider Type** | `remote::s3-files` |
| **Endpoint** | `http://minio.model-storage.svc:9000` |
| **Bucket** | `llama-files` |
| **Region** | `us-east-1` |
| **TLS Verify** | `false` |
| **Path Style** | `true` (S3-compatible) |
| **Auth Method** | Environment variables from secret |

### **vLLM Providers** (Unchanged)
| Model | URL | TLS Verify |
|-------|-----|------------|
| **Quantized** | `https://mistral-24b-quantized-private-ai-demo.apps...com/v1` | `false` |
| **Full** | `https://mistral-24b-private-ai-demo.apps...com/v1` | `false` |

### **Vector IO** (Unchanged)
| Database | URI |
|----------|-----|
| **Milvus** | `tcp://milvus-standalone.private-ai-demo.svc.cluster.local:19530` |

---

## 🚀 Deployment Instructions

### **Prerequisites**
1. ✅ Project root `.env` file with MinIO credentials
2. ✅ Stage 0 deployed (MinIO running)
3. ✅ Stage 1 deployed (vLLM models running)

### **Step 1: Update MinIO Bootstrap**
```bash
cd gitops/stage00-ai-platform
oc apply -k .

# Verify bucket creation
oc logs -n model-storage -l app.kubernetes.io/name=minio-bootstrap --tail=50

# Should see:
# ✅ Created bucket: llama-files
# ✅ Versioning enabled for llama-files
```

**Alternative:** If bootstrap already ran, create bucket manually:
```bash
# Get credentials from secret
ACCESS=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d)
SECRET=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d)

# Create bucket using mc in a pod
oc run -n model-storage minio-create-bucket --image=quay.io/minio/mc:latest --rm -i --restart=Never -- \
  sh -c "export HOME=/tmp && \
  mc alias set minio http://minio.model-storage.svc:9000 $ACCESS $SECRET && \
  mc mb minio/llama-files --ignore-existing && \
  mc version enable minio/llama-files && \
  mc ls minio/"
```

### **Step 2: Deploy Stage 2**
```bash
cd stages/stage2-model-alignment
./deploy.sh

# This will:
# ✅ Create llama-files-credentials secret
# ✅ Configure SCC permissions
# ✅ Enable Service Mesh sidecar injection
# ✅ Apply all GitOps resources (including Files config)
```

### **Step 3: Verify Deployment**
```bash
# Check LlamaStackDistribution
oc get llamastackdistribution llama-stack -n private-ai-demo

# Check pod status
oc get pods -l app=llama-stack -n private-ai-demo

# Should see: 2/2 Running (if sidecar injection works)
# Or: 1/1 Running (if sidecar doesn't inject, but Files API should still work)

# Check logs
oc logs -l app=llama-stack -c llamastack -n private-ai-demo --tail=100

# Should see:
# INFO ... Files API initialized
# INFO ... Connected to S3 endpoint: http://minio.model-storage.svc:9000
# INFO ... Bucket: llama-files
```

### **Step 4: Test Files API**
```bash
# Verify environment variables in pod
oc exec -n private-ai-demo $(oc get pod -l app=llama-stack -o name | head -1) -c llamastack -- \
  env | grep FILES_S3

# Expected output:
# FILES_S3_ENDPOINT=http://minio.model-storage.svc:9000
# FILES_S3_BUCKET=llama-files
# FILES_S3_REGION=us-east-1
# FILES_S3_TLS_VERIFY=false
# FILES_S3_FORCE_PATH_STYLE=true
# FILES_S3_ACCESS_KEY_ID=admin
# FILES_S3_SECRET_ACCESS_KEY=<secret>

# Verify bucket access from MinIO
mc alias set minio http://minio.model-storage.svc:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
mc ls minio/llama-files

# Test Files API endpoint (if LlamaStack is running)
LLAMA_URL=$(oc get route llamastack -n private-ai-demo -o jsonpath='{.spec.host}')
curl -k https://$LLAMA_URL/alpha/files/list
```

---

## 🔍 Troubleshooting

### **Issue: Bucket not found**
```bash
# Check if bucket exists
mc alias set minio http://minio.model-storage.svc:9000 $ACCESS $SECRET
mc ls minio/ | grep llama-files

# If not found, create manually (see Step 1 Alternative above)
```

### **Issue: Secret not found**
```bash
# Check if secret exists
oc get secret llama-files-credentials -n private-ai-demo

# If not found, create manually:
ACCESS=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d)
SECRET=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d)

oc -n private-ai-demo create secret generic llama-files-credentials \
  --from-literal=accesskey="$ACCESS" \
  --from-literal=secretkey="$SECRET"
```

### **Issue: Pod crash with "Provider not available"**
```bash
# Check logs for provider type
oc logs -l app=llama-stack -c llamastack -n private-ai-demo --tail=200 | grep -A5 "Provider"

# If "remote::s3-files" not available, the rh-dev distribution may not support it
# Check Red Hat docs or try "remote::s3" instead
```

### **Issue: Permission denied accessing bucket**
```bash
# Verify credentials match
oc get secret llama-files-credentials -n private-ai-demo -o jsonpath='{.data.accesskey}' | base64 -d
oc get secret minio-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d

# They should match. If not, recreate llama-files-credentials
```

---

## 📚 References

### **Red Hat Documentation**
- **RHOAI 2.25 - Llama Stack:** https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_llama_stack/index
- **Section 3.7:** Deploying a LlamaStackDistribution instance
- **Section 3.10:** Preparing documents with Docling for Llama Stack retrieval

### **MinIO Documentation**
- **S3 API Compatibility:** https://min.io/docs/minio/linux/integrations/aws-cli-with-minio.html
- **Bucket Versioning:** https://min.io/docs/minio/linux/administration/object-management/object-versioning.html

### **Git Commits**
- **Latest:** `712cd84` - Add LlamaStack Files API backed by MinIO
- **Previous:** `7ce8297` - Configure LlamaStack with external HTTPS routes

---

## ✅ What's Working

- ✅ MinIO bootstrap job updated to create llama-files bucket
- ✅ Secret management pattern established (imperative, not in Git)
- ✅ LlamaStackDistribution configured with FILES_S3_* env vars
- ✅ ConfigMap (run.yaml) includes Files API and provider
- ✅ External HTTPS routes for vLLM (bypass Service Mesh)
- ✅ Internal gRPC for Milvus (no change)
- ✅ All configuration aligned with operator pattern
- ✅ All secrets managed outside Git history

---

## 🎯 Next Steps

1. **Apply Stage 0 MinIO bootstrap** (creates llama-files bucket)
2. **Run Stage 2 deploy.sh** (creates secret, applies config)
3. **Verify LlamaStack startup** (check logs for Files API init)
4. **Test Files API** (upload/download documents)
5. **Integrate with KFP pipelines** (document ingestion)
6. **Create ArgoCD Application** for Stage 2 (GitOps management)

---

## 📝 Notes

### **Why External HTTPS Routes for vLLM?**
LlamaStack Operator doesn't support Istio sidecar injection (no pod template annotations support). Using external HTTPS routes bypasses the Service Mesh requirement while maintaining functionality.

### **Why Internal gRPC for Milvus?**
Milvus doesn't use Knative/Service Mesh, so internal cluster DNS works fine. No external route needed.

### **Why Imperative Secret Creation?**
Following Stage 1/2 pattern: secrets contain sensitive credentials and should never be committed to Git. Creating them imperatively from .env or copying from model-storage namespace maintains security and reproducibility.

### **Provider Type: remote::s3-files**
This is the expected provider type for rh-dev distribution. If it doesn't work, alternatives to try:
- `remote::s3`
- `inline::files` (if supported)
- Contact Red Hat support for correct provider type

---

## ✅ Summary

**Status:** Configuration complete and ready to deploy

**Changes Made:**
1. MinIO bootstrap job (llama-files bucket)
2. Secret template (not in Git)
3. Deploy script (imperative secret creation)
4. LlamaStackDistribution (FILES_S3_* env vars)
5. ConfigMap (Files API and provider)

**Pattern:** Operator-aligned, secrets outside Git, reproducible deployment

**Ready to Apply:** Follow deployment instructions above


