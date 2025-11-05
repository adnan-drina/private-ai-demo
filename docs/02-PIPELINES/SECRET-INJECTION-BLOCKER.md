# KFP v2 Secret Injection Blocker

## Issue
KFP v2/DSPA strips `valueFrom.secretKeyRef` from pipeline executor container environment variables, preventing proper Kubernetes Secret mounting following Red Hat best practices.

## What We Implemented (Correct Approach)
Following Red Hat guidance to never pass secrets as parameters:

1. **Removed secrets from pipeline parameters**
   - No `aws_access_key_id` or `aws_secret_access_key` parameters
   - All parameters are scalar strings

2. **Mirrored Secret to pipeline namespace**
   ```bash
   # Created minio-storage-credentials in private-ai-demo
   oc -n private-ai-demo get secret minio-storage-credentials
   ```

3. **Injected secretKeyRef in compiled YAML**
   ```yaml
   exec-download-from-s3:
     container:
       env:
       - name: AWS_ACCESS_KEY_ID
         valueFrom:
           secretKeyRef:
             key: accesskey
             name: minio-storage-credentials
       - name: AWS_SECRET_ACCESS_KEY
         valueFrom:
           secretKeyRef:
             key: secretkey
             name: minio-storage-credentials
   ```

4. **Component reads from environment**
   ```python
   aws_access_key_id = os.getenv("AWS_ACCESS_KEY_ID")
   aws_secret_access_key = os.getenv("AWS_SECRET_ACCESS_KEY")
   ```

## What Happens at Runtime

The pipeline YAML has correct `secretKeyRef` definitions, but when KFP creates the pod:

**Expected** (from our YAML):
```yaml
env:
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      key: accesskey
      name: minio-storage-credentials
```

**Actual** (in pod spec):
```json
"env":[
  {"name":"AWS_ACCESS_KEY_ID"},
  {"name":"AWS_SECRET_ACCESS_KEY"}
]
```

The `valueFrom.secretKeyRef` section is stripped, resulting in `null` values.

## Root Cause

KFP v2 (DSPA) processes the pipeline YAML and transforms it into Argo Workflow pod templates. During this transformation:

1. The `deploymentSpec.executors.exec-<task>.container.env` is read
2. Environment variables are extracted
3. But `valueFrom` references are **not** preserved in the final pod template
4. Only direct `value` fields or pre-defined KFP env vars are kept

This is a KFP v2 limitation/design decision for security isolation.

## Red Hat-Aligned Solutions

### Option 1: PodDefault (Kubeflow Feature) ✅ Preferred
Create a `PodDefault` that automatically injects secrets into pods with specific labels.

**Requires**: KFP PodDefault controller (may need DSPA configuration)

```yaml
apiVersion: kubeflow.org/v1alpha1
kind: PodDefault
metadata:
  name: minio-credentials
  namespace: private-ai-demo
spec:
  selector:
    matchLabels:
      inject-minio-creds: "true"
  env:
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: minio-storage-credentials
        key: accesskey
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: minio-storage-credentials
        key: secretkey
```

Then annotate the pipeline task to request injection.

### Option 2: ServiceAccount with Mounted Secret ✅ Kubernetes Native
Mount the secret as a volume and read from file:

1. Update `pipeline` ServiceAccount to mount `minio-storage-credentials`
2. Component reads from `/var/run/secrets/minio/accesskey` and `/var/run/secrets/minio/secretkey`

### Option 3: DSPA ObjectStorage Configuration ✅ Platform Level
If the DSPA is already configured with S3 credentials for artifact storage, those credentials might be available to pipeline pods automatically.

Check `dspa-minio-credentials` secret and ensure it's the correct one.

### Option 4: External Secrets Operator ✅ Enterprise
Use External Secrets Operator to sync secrets from Vault/AWS Secrets Manager and inject them at runtime.

## Current Workaround (NOT Recommended)
❌ **Base64-encode secrets as parameters** - Still passing secrets, just obfuscated
❌ **Use ConfigMap** - Secrets in plaintext
❌ **Hardcode in image** - Security violation

## Next Steps

1. **Verify DSPA Configuration**
   ```bash
   oc -n private-ai-demo get dspa -o yaml
   ```
   Check if `objectStorage.s3CredentialsSecret` provides automatic credential injection.

2. **Check for PodDefault Support**
   ```bash
   oc api-resources | grep poddefault
   ```

3. **Test ServiceAccount Volume Mount**
   Modify pipeline ServiceAccount to mount the secret as a volume.

4. **Contact Red Hat Support**
   If DSPA should support `secretKeyRef` in pipeline YAML, this may be a bug or missing feature.

## References
- [KFP v2 Security Model](https://www.kubeflow.org/docs/components/pipelines/v2/security/)
- [RHOAI Pipelines Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/working_with_data_science_pipelines/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## Code Status
✅ Pipeline code is correct
✅ Secret mirroring is correct  
✅ YAML injection is correct
❌ **Blocker**: KFP runtime strips secretKeyRef

**All code committed**: `feature/stage2-implementation` branch

