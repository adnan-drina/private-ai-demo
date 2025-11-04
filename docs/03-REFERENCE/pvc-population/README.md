# PVC Population for Large Models

## Overview

For large models (>20GB) that exceed node ephemeral storage capacity, we use a **PVC-backed storage pattern** instead of the S3 storage-initializer pattern.

This requires a **one-time setup** to populate the PVC with model weights before deploying the InferenceService.

---

## Architecture Comparison

| Pattern | Use Case | How It Works | Pros | Cons |
|---------|----------|--------------|------|------|
| **S3 (storage-initializer)** | Small models (<20GB) | storage-initializer downloads model to EmptyDir on pod startup | Fast startup, portable, no permanent storage | Uses node ephemeral storage, can cause DiskPressure |
| **PVC-backed** | Large models (>20GB) | Model pre-populated in PVC, mounted read-only by pod | Avoids node storage exhaustion, sustainable | Requires one-time setup, PVC management |

---

## Full Model Setup Process

### 1. Prerequisites

```bash
# Verify MinIO has the full model
oc exec -n model-storage deploy/minio -- \
  mc ls minio/llm-models/Mistral-Small-24B-Instruct/full-fp16/

# Verify PVC exists and is Bound
oc get pvc mistral-24b-pvc -n private-ai-demo
```

### 2. Run Mirror Job (One-Time)

```bash
# Apply the mirror job
oc apply -f gitops/stage01-model-serving/serving/vllm/job-mirror-full-model.yaml

# Monitor progress (takes ~10-15 minutes for 48GB)
oc logs -f -n private-ai-demo job/mirror-full-model-to-pvc

# Check job status
oc get job mirror-full-model-to-pvc -n private-ai-demo
```

### 3. Verify PVC Contents

```bash
# Create a temporary pod to inspect PVC
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pvc-inspector
  namespace: private-ai-demo
spec:
  containers:
  - name: inspector
    image: registry.access.redhat.com/ubi9/ubi-minimal:9.4
    command: ["/bin/sh", "-c", "sleep 600"]
    volumeMounts:
    - name: model-storage
      mountPath: /mnt/models
  volumes:
  - name: model-storage
    persistentVolumeClaim:
      claimName: mistral-24b-pvc
  restartPolicy: Never
EOF

# Check contents
oc exec -n private-ai-demo pvc-inspector -- ls -lh /mnt/models/
oc exec -n private-ai-demo pvc-inspector -- du -sh /mnt/models/

# Verify critical files exist
oc exec -n private-ai-demo pvc-inspector -- sh -c '
  for file in config.json model-00001-of-00009.safetensors model.safetensors.index.json tokenizer.json; do
    if [ -f /mnt/models/$file ]; then
      echo "✅ $file"
    else
      echo "❌ MISSING: $file"
    fi
  done
'

# Clean up inspector pod
oc delete pod pvc-inspector -n private-ai-demo
```

### 4. Deploy InferenceService

Once the PVC is populated, the InferenceService can be deployed:

```bash
# InferenceService will mount the pre-populated PVC
oc apply -f gitops/stage01-model-serving/serving/vllm/inferenceservice-mistral-24b.yaml

# Monitor deployment
oc get inferenceservice mistral-24b -n private-ai-demo -w
```

---

## Troubleshooting

### Job Fails: "Source model not found"

**Cause:** Model not present in MinIO at expected path.

**Solution:**
```bash
# Check MinIO contents
oc exec -n model-storage deploy/minio -- \
  mc ls minio/llm-models/Mistral-Small-24B-Instruct/

# If missing, run model import pipeline first
cd stages/stage1-model-serving
./run-model-import.sh full
```

### Job Fails: "Multi-Attach error"

**Cause:** PVC is already mounted by another pod (RWO - ReadWriteOnce).

**Solution:**
```bash
# Delete any pods using the PVC
oc delete inferenceservice mistral-24b -n private-ai-demo

# Wait for pod termination, then retry job
oc delete job mirror-full-model-to-pvc -n private-ai-demo
oc apply -f gitops/stage01-model-serving/serving/vllm/job-mirror-full-model.yaml
```

### Job Fails: "Permission denied" (.mc directory)

**Cause:** Missing fsGroup in Job spec.

**Solution:** Ensure Job has:
```yaml
spec:
  template:
    spec:
      securityContext:
        fsGroup: 1001130000  # Your namespace's fsGroup
```

### InferenceService Pod CrashLoopBackOff

**Cause:** PVC is empty or incomplete.

**Solution:**
```bash
# Verify PVC contents (see section 3 above)
# If empty, delete and rerun mirror job
oc delete job mirror-full-model-to-pvc -n private-ai-demo
oc apply -f gitops/stage01-model-serving/serving/vllm/job-mirror-full-model.yaml
```

---

## Maintenance

### Updating Model Weights

To update the model in the PVC:

```bash
# 1. Delete InferenceService (releases PVC)
oc delete inferenceservice mistral-24b -n private-ai-demo

# 2. Delete old mirror job
oc delete job mirror-full-model-to-pvc -n private-ai-demo

# 3. Run new mirror job (will use --overwrite flag)
oc apply -f gitops/stage01-model-serving/serving/vllm/job-mirror-full-model.yaml

# 4. Wait for completion
oc wait --for=condition=complete --timeout=20m job/mirror-full-model-to-pvc -n private-ai-demo

# 5. Redeploy InferenceService
oc apply -f gitops/stage01-model-serving/serving/vllm/inferenceservice-mistral-24b.yaml
```

### Cleaning Up

```bash
# Delete completed mirror job (after 24h TTL)
oc delete job mirror-full-model-to-pvc -n private-ai-demo

# PVC is persistent and will remain for InferenceService use
# Only delete if completely removing the full model deployment
```

---

## Why Not Use ArgoCD for the Mirror Job?

The mirror job is a **one-time initialization task**, not a continuous GitOps-managed resource. Reasons it's excluded from ArgoCD management:

1. **One-time execution:** Job should run once, not every sync
2. **Manual trigger:** Operator decides when to populate/refresh PVC
3. **Long-running:** 10-15 minutes, would block ArgoCD sync
4. **State-dependent:** Requires MinIO to have model first

**Best Practice:** Keep Job manifest in GitOps for **reproducibility**, but apply **manually** when needed.

---

## Integration with deploy.sh

The `deploy.sh` script handles secrets and ArgoCD sync, but **not** the mirror job.

To populate PVC after running `deploy.sh`:

```bash
# 1. Run deploy.sh (creates secrets, syncs ArgoCD)
cd stages/stage1-model-serving
./deploy.sh

# 2. Ensure model is in MinIO (run import pipeline if needed)
./run-model-import.sh full

# 3. Populate PVC manually
oc apply -f ../../gitops/stage01-model-serving/serving/vllm/job-mirror-full-model.yaml

# 4. Monitor until complete
oc logs -f -n private-ai-demo job/mirror-full-model-to-pvc
```

---

## References

- [KServe Storage Initializer](https://kserve.github.io/website/modelserving/storage/storagecontainers/)
- [Red Hat OpenShift AI - Large Model Storage](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai)
- [PVC vs EmptyDir Performance](https://kubernetes.io/docs/concepts/storage/volumes/)


