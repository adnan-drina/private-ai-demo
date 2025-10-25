# Image Pull Secret Configuration

## Overview

The `internal-registry-private-ai` secret is required for InferenceServices to pull ModelCar images from the OpenShift internal registry.

## Issue Discovered

**Problem**: The secret was initially created with an incorrect `dockerconfigjson` format missing the required `"auths"` wrapper, causing `ImagePullBackOff` errors.

**Incorrect Format**:
```json
{
  "image-registry.openshift-image-registry.svc:5000": {
    "auth": "..."
  }
}
```

**Correct Format**:
```json
{
  "auths": {
    "image-registry.openshift-image-registry.svc:5000": {
      "username": "<token>",
      "password": "sha256~...",
      "auth": "..."
    }
  }
}
```

## Solution

The secret must be created using the standard `oc create secret docker-registry` command, which automatically generates the correct format:

```bash
TOKEN=$(oc whoami -t)

oc create secret docker-registry internal-registry-private-ai \
  --docker-server=image-registry.openshift-image-registry.svc:5000 \
  --docker-username='<token>' \
  --docker-password="$TOKEN" \
  -n private-ai-demo

# Add required labels and annotations
oc label secret internal-registry-private-ai \
  opendatahub.io/dashboard=true \
  -n private-ai-demo

oc annotate secret internal-registry-private-ai \
  -n private-ai-demo \
  "openshift.io/display-name=Internal OpenShift Registry" \
  "openshift.io/description=Internal OpenShift Registry for ModelCar Images" \
  "opendatahub.io/connection-type-ref=oci-v1"
```

## Why Not in GitOps?

This secret contains a **dynamic service account token** that:
1. Is specific to the cluster
2. Changes with each deployment
3. Should not be stored in Git

Therefore, it must be created by the `deploy.sh` script during deployment.

## Verification

To verify the secret format is correct:

```bash
oc get secret internal-registry-private-ai -n private-ai-demo \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
```

Expected output should show:
```json
{
  "auths": {
    "image-registry.openshift-image-registry.svc:5000": {
      ...
    }
  }
}
```

## Related Files

- `connection-internal-registry.yaml` - Template/placeholder (managed by ArgoCD)
- `../pipelines/00-namespace-resources/serviceaccount.yaml` - Pipeline SA that builds images
- `../vllm/inferenceservice-*.yaml` - InferenceServices that pull images using this secret

