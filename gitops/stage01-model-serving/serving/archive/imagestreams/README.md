# Archived: ImageStreams (Nov 3, 2025)

## Why Archived

These ImageStreams were created for the initial pipeline design that pushed ModelCar images to the OpenShift internal registry. 

**Current Architecture:**
- Pipelines push runtime images directly to **Quay.io** (`quay.io/${QUAY_ORG}/${QUAY_REPO}`)
- InferenceServices pull from:
  - **Quantized model**: MinIO S3 (`s3://llm-models/`)
  - **Full model**: PVC (`pvc://mistral-24b-pvc/`)
- No internal registry integration needed

## Files Archived

- `imagestream-mistral-full.yaml` - Empty ImageStream, never populated
- `imagestream-mistral-quantized.yaml` - Empty ImageStream, never populated  
- `kustomization.yaml` - ImageStream kustomization

## Related Changes

- Removed from `serving/kustomization.yaml`
- Internal registry connection moved to `docs/03-REFERENCE/secrets/`
- `deploy.sh` updated to remove internal-registry-private-ai secret creation

## If You Need to Restore

These manifests are kept for reference. To use internal registry:

1. Update `task-build-runtime.yaml` to push to internal registry instead of Quay
2. Restore ImageStreams from this archive
3. Update InferenceServices to use `image:` instead of `storageUri:`
4. Re-enable internal-registry secret creation in `deploy.sh`
