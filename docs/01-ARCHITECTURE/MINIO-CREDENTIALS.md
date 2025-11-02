# MinIO Credentials Management

## Overview

MinIO credentials must match the actual MinIO instance running in the `model-storage` namespace.

## Correct Credentials

The MinIO instance deployed in `model-storage` namespace uses:
- **Access Key:** `admin`
- **Secret Key:** Retrieved from cluster (32 characters, randomly generated)

## How to Get Credentials

### From Cluster

```bash
# Get MinIO access key
oc get secret minio-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d

# Get MinIO secret key
oc get secret minio-credentials -n model-storage -o jsonpath='{.data.secretkey}' | base64 -d
```

### Update .env File

1. Copy `env.template` to `.env`:
   ```bash
   cp env.template .env
   ```

2. Retrieve credentials from cluster (see above)

3. Update `.env` file:
   ```bash
   MINIO_ACCESS_KEY=admin
   MINIO_SECRET_KEY=<paste-secret-from-cluster>
   ```

## Common Issues

### Credential Mismatch Error

**Symptom:**
```
mc: <ERROR> Unable to initialize new alias from the provided credentials. 
The Access Key Id you provided does not exist in our records.
```

**Cause:**
- `.env` file has incorrect credentials
- Most common: using `minio-admin` instead of `admin`

**Fix:**
```bash
# Get correct credentials from cluster
MINIO_ACCESS=$(oc get secret minio-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d)
MINIO_SECRET=$(oc get secret minio-credentials -n model-storage -o jsonpath='{.data.secretkey}' | base64 -d)

# Update .env
sed -i "s/^MINIO_ACCESS_KEY=.*/MINIO_ACCESS_KEY=$MINIO_ACCESS/" .env
sed -i "s/^MINIO_SECRET_KEY=.*/MINIO_SECRET_KEY=$MINIO_SECRET/" .env

# Update secrets in private-ai-demo namespace
oc create secret generic minio-credentials \
  --from-literal=accesskey="$MINIO_ACCESS" \
  --from-literal=secretkey="$MINIO_SECRET" \
  -n private-ai-demo \
  --dry-run=client -o yaml | oc apply -f -
```

## Security Notes

1. ✅ `.env` files are in `.gitignore` - secrets never committed to git
2. ✅ `env.template` contains placeholders only
3. ✅ Credentials are managed imperatively via `deploy.sh` scripts
4. ✅ GitOps manifests reference secrets by name, not content

## Related Files

- `.env` - Local secrets (git-ignored)
- `env.template` - Template with placeholders
- `stages/*/deploy.sh` - Scripts that create secrets from `.env`
- `gitops/*/` - Manifests that reference secrets

