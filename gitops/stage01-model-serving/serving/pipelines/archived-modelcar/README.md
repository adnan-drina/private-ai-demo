# Archived: ModelCar Pipeline (v1-v3)

## Status: **ARCHIVED - NOT DEPLOYED**

This directory contains the legacy "ModelCar" pipeline implementation that **baked model weights into OCI container images**.

## Why Archived?

The ModelCar approach worked well for small/medium models (< 40GB) but hit fundamental limitations with large models:

### Problems with ModelCar for Large Models
- ❌ **90GB+ OCI images** (48GB weights + 40GB layers)
- ❌ **2-hour buildah commits** (serializing 90GB to disk)
- ❌ **15-minute image pulls** on GPU nodes
- ❌ **Node ephemeral storage exhaustion** → pod eviction
- ❌ **Required 500GB root disks** just for startup

### What Replaced It

**Unified MinIO-First Pipeline** (`../active/`)

All models (quantized and full) now use:
- ✅ **Weights in MinIO object storage** (s3://llm-models/{model}/{version}/)
- ✅ **Lightweight runtime images** (~5-10GB)
- ✅ **Init containers fetch at pod startup** from MinIO
- ✅ **No node ephemeral storage pressure**
- ✅ **Scales to any model size**

## Architecture Evolution

| Aspect | ModelCar (Archived) | MinIO-First (Active) |
|--------|---------------------|----------------------|
| Model Weights | Baked into image | Object storage |
| Image Size | 8GB (quantized) to 90GB+ (full) | 5-10GB (all models) |
| Build Time | 15min to 2+ hours | 15-20 minutes |
| Pull Time | 2min to 15+ minutes | 2-3 minutes |
| Node Storage | 60-500GB ephemeral required | 20-30GB sufficient |
| Scalability | Limited to < 40GB models | Unlimited |
| Pattern | Path A (monolithic) | Path B (separated concerns) |

## Files in This Archive

- `task-build-push-v2.yaml`: Built OCI image with weights using Buildah
- `task-mirror-to-internal.yaml`: Mirrored full image to internal registry

These tasks are **kept for:**
- Historical reference
- Compliance/audit trail
- Understanding evolution
- Potential rollback if needed

These tasks are **NOT applied** to the cluster because they're excluded from the active kustomization.

## Migration Path

If you need to understand how we migrated:

1. **Old Flow (ModelCar)**:
   ```
   download → build-push (90GB image) → mirror → register
   ```

2. **New Flow (MinIO-First)**:
   ```
   download → upload-to-minio → build-runtime (10GB) → register
   ```

The key insight: **separate model weights (data) from runtime (code)**.

## Red Hat Best Practice

This evolution aligns with Red Hat OpenShift AI's reference architecture for large LLM serving:
- Model weights as **persistent data** (object storage)
- Runtime as **stateless container** (lightweight image)
- Inference pods **mount or stream weights** at startup

Reference: [Red Hat OpenShift AI vLLM Serving Pattern](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)

## Date Archived

2025-10-29

## Superseded By

`../active/` - Unified MinIO-First Pipeline

