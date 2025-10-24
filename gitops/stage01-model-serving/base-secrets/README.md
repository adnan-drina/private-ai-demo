# Secrets Management for Stage 1

## Overview

This folder is a **placeholder** for secret management documentation. Following Red Hat OpenShift GitOps best practices, **actual secrets are NOT stored in Git**.

## Current Approach (Interim Solution)

### How It Works

1. **Secrets Defined Locally**
   - Secrets are defined in `stages/stage1-model-serving/.env` (git-ignored)
   - Template provided: `stages/stage1-model-serving/env.template`

2. **Imperative Secret Creation**
   - `stages/stage1-model-serving/deploy.sh` loads secrets from `.env`
   - Creates Kubernetes Secrets imperatively using `oc create secret`
   - Uses `--dry-run=client -o yaml | oc apply -f -` pattern for idempotency

3. **GitOps Manifests Reference Secrets**
   - Manifests in `gitops/` reference secrets **by name only**
   - No actual secret values in Git
   - Example:
     ```yaml
     env:
     - name: HF_TOKEN
       valueFrom:
         secretKeyRef:
           name: huggingface-token
           key: HF_TOKEN
     ```

### Secrets Created

| Secret Name | Namespace | Keys | Purpose |
|-------------|-----------|------|---------|
| `huggingface-token` | `private-ai-demo` | `HF_TOKEN` | Model downloads from HuggingFace |
| `minio-credentials` | `private-ai-demo` | `accesskey`, `secretkey` | MinIO object storage authentication |

### Security Benefits

✅ **No Secrets in Git** - Secrets never committed to version control  
✅ **Local Management** - `.env` files are git-ignored  
✅ **Idempotent** - Can safely re-run deploy script  
✅ **Auditable** - Secret creation tracked in deploy script  

### Limitations

⚠️ **Manual Management** - Secrets must be created/updated manually  
⚠️ **Not Fully GitOps** - Secrets managed outside declarative workflow  
⚠️ **No Rotation** - Manual secret rotation required  
⚠️ **No Centralization** - Each environment needs separate `.env` files  

## Red Hat Recommended Approach (Production)

For production environments, Red Hat recommends using one of these solutions:

### Option 1: External Secrets Operator (ESO) ⭐ Recommended

**Benefits:**
- Integrates with external secret stores (Vault, AWS Secrets Manager, Azure Key Vault)
- Secrets synchronized automatically
- Centralized management
- Automated rotation
- Full GitOps compliance

**Implementation:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: huggingface-token
  namespace: private-ai-demo
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: huggingface-token
    creationPolicy: Owner
  data:
  - secretKey: HF_TOKEN
    remoteRef:
      key: private-ai-demo/huggingface
      property: token
```

**References:**
- [External Secrets Operator Documentation](https://external-secrets.io/)
- [Red Hat: Managing Secrets with ESO](https://ai-on-openshift.io/odh-rhoai/secret-management/)

### Option 2: Secrets Store CSI Driver

**Benefits:**
- Mounts secrets from external stores as volumes
- Native Kubernetes integration
- Supports multiple backends
- No custom CRDs required

**Implementation:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: model-downloader
spec:
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "vault-private-ai-demo"
  containers:
  - name: downloader
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets"
      readOnly: true
```

**References:**
- [Red Hat: Secrets Store CSI Driver with GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.17/html/security/managing-secrets-securely-using-sscsid-with-gitops)

### Option 3: Sealed Secrets

**Benefits:**
- Encrypted secrets in Git
- Full GitOps compliance
- No external dependencies
- Simple to use

**Implementation:**
```bash
# Create sealed secret
kubeseal --format yaml \
  < secret.yaml \
  > sealed-secret.yaml

# Commit to Git
git add sealed-secret.yaml
git commit -m "Add sealed secret"
```

**Limitations:**
- Requires key management
- Complex rotation process
- No centralized management

**References:**
- [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)

## Migration Path

To migrate from current approach to External Secrets Operator:

### Phase 1: Install ESO
```bash
# Deploy ESO operator
oc apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml

# Install operator
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace
```

### Phase 2: Configure Secret Store
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: private-ai-demo
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "private-ai-demo"
```

### Phase 3: Create ExternalSecret Resources
```yaml
# Add to gitops/stage01-model-serving/base-secrets/
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: huggingface-token
spec:
  # ... configuration
```

### Phase 4: Deploy & Validate
```bash
# Apply GitOps manifests
oc apply -k gitops/stage01-model-serving/

# Verify secrets created
oc get secret huggingface-token -n private-ai-demo

# Verify ESO status
oc get externalsecret -n private-ai-demo
```

### Phase 5: Remove Imperative Creation
```bash
# Update deploy.sh to skip secret creation
# Remove create_secrets() function call
```

## References

### Red Hat Documentation
- [OpenShift GitOps Security Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html-single/security/)
- [Managing Secrets Securely with SSCSID](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.17/html/security/managing-secrets-securely-using-sscsid-with-gitops)
- [How to Manage Kubernetes Secrets with Red Hat OpenShift](https://cloud.redhat.com/learn/how-manage-kubernetes-secrets-red-hat-openshift)

### Community Resources
- [Secure Way to Handle Secrets in OpenShift](https://developers.redhat.com/articles/2025/10/01/secure-way-handle-secrets-openshift)
- [AI on OpenShift: Secret Management](https://ai-on-openshift.io/odh-rhoai/secret-management/)

### Tools
- [External Secrets Operator](https://external-secrets.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)

---

**Last Updated:** October 24, 2025  
**Status:** Interim solution (imperative secret creation)  
**Target:** Migrate to External Secrets Operator (ESO)

