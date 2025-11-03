# Initial Model Mirror Job

This folder contains the Kubernetes Job used to initially mirror the Mistral 24B full-precision model from MinIO to the PVC.

## Usage

This Job was used **once** during initial deployment to populate the `mistral-24b-pvc` with the 83GB model from MinIO.

### When to use this Job:

1. **Initial deployment** - When setting up the full model for the first time
2. **Model updates** - When the model in MinIO has been updated and needs to be synced to the PVC
3. **PVC recreation** - If the PVC is deleted and needs to be repopulated

### How to run manually:

```bash
# Apply the PVC first (if it doesn't exist)
oc apply -f ../../../gitops/stage01-model-serving/serving/vllm/pvc-mistral-24b.yaml

# Wait for PVC to be created
oc -n private-ai-demo get pvc mistral-24b-pvc

# Run the mirror job
oc apply -f job-mirror-full-model.yaml

# Monitor progress
oc -n private-ai-demo logs -f job/mirror-full-model-to-pvc

# Clean up after completion
oc -n private-ai-demo delete job mirror-full-model-to-pvc
```

## Why not in GitOps?

The Job is **not** included in the main GitOps deployment because:

1. **One-time operation** - The model only needs to be mirrored once
2. **Resource efficiency** - No need to recreate the Job on every ArgoCD sync
3. **Stability** - The InferenceService can run indefinitely with the PVC-backed model

## Model Details

- **Source**: MinIO bucket `llm-models/Mistral-Small-24B-Instruct/full-fp16/`
- **Target**: PVC `mistral-24b-pvc` mounted at `/mnt/models`
- **Size**: 83GB (44GB consolidated + 45GB sharded files)
- **Transfer time**: ~11 minutes @ 125 MiB/s
- **Storage**: 120Gi PVC (gp3-csi, RWO)

## Job Configuration

- **Image**: `quay.io/minio/mc:latest`
- **Secret**: `minio-credentials` (keys: `accesskey`, `secretkey`)
- **Resources**: 500m CPU / 1Gi memory (requests), 2 CPU / 2Gi memory (limits)
- **Backoff limit**: 2 retries
- **TTL**: 3600 seconds after completion
