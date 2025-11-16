# MCP Server Container Builds

This directory contains BuildConfigs and ImageStreams for building MCP server container images in OpenShift.

## Overview

The MCP servers are built using OpenShift's binary build strategy, which allows us to upload source code from our local workspace and build container images without requiring a Git repository hook.

## Built Images

### database-mcp
- **Purpose**: PostgreSQL database query interface for equipment metadata
- **Base Image**: `registry.access.redhat.com/ubi9/python-39:latest`
- **Tools**: `query_equipment`, `query_service_history`, `query_parts_inventory`
- **Port**: 8080
- **Output**: `image-registry.openshift-image-registry.svc:5000/private-ai-demo/database-mcp:latest`

### slack-mcp
- **Purpose**: Slack notification system for team alerts
- **Base Image**: `registry.access.redhat.com/ubi9/python-39:latest`
- **Tools**: `send_slack_message`, `send_equipment_alert`, `send_maintenance_plan`
- **Port**: 8080
- **Output**: `image-registry.openshift-image-registry.svc:5000/private-ai-demo/slack-mcp:latest`

## Prerequisites

1. OpenShift CLI (`oc`) installed and configured
2. Logged into OpenShift cluster with appropriate permissions
3. Source code in `stages/stage4-model-integration/mcp-servers/`

## Building Images

### Apply Build Resources

```bash
# Apply ImageStreams and BuildConfigs
oc apply -k gitops/stage04-model-integration/mcp-servers/builds/
```

### Build database-mcp

```bash
cd /path/to/private-ai-demo

oc start-build database-mcp \
  --from-dir=stages/stage4-model-integration/mcp-servers/database-mcp/ \
  --follow \
  -n private-ai-demo
```

### Build slack-mcp

```bash
cd /path/to/private-ai-demo

oc start-build slack-mcp \
  --from-dir=stages/stage4-model-integration/mcp-servers/slack-mcp/ \
  --follow \
  -n private-ai-demo
```

## Verifying Builds

### Check Build Status

```bash
# List recent builds
oc get builds -n private-ai-demo | grep mcp

# Check build logs
oc logs -f build/database-mcp-1 -n private-ai-demo
oc logs -f build/slack-mcp-1 -n private-ai-demo
```

### Verify Images in Registry

```bash
# Check ImageStreams
oc get imagestream database-mcp -n private-ai-demo
oc get imagestream slack-mcp -n private-ai-demo

# Get image references
oc get imagestream database-mcp -n private-ai-demo -o jsonpath='{.status.tags[0].items[0].dockerImageReference}'
oc get imagestream slack-mcp -n private-ai-demo -o jsonpath='{.status.tags[0].items[0].dockerImageReference}'
```

## Deployment

Once images are built, the MCP server deployments will automatically use them:

```bash
# database-mcp deployment references:
# image-registry.openshift-image-registry.svc:5000/private-ai-demo/database-mcp:latest

# slack-mcp deployment references:
# image-registry.openshift-image-registry.svc:5000/private-ai-demo/slack-mcp:latest
```

To deploy the MCP servers:

```bash
# Deploy database-mcp
oc apply -k gitops/stage04-model-integration/mcp-servers/database-mcp/

# Deploy slack-mcp
oc apply -k gitops/stage04-model-integration/mcp-servers/slack-mcp/

# Deploy openshift-mcp (uses pre-built image)
oc apply -k gitops/stage04-model-integration/mcp-servers/openshift-mcp/
```

## Rebuilding After Code Changes

If you modify the MCP server code in `stages/stage4-model-integration/mcp-servers/`, simply re-run the build:

```bash
# After changing database_mcp_server.py
oc start-build database-mcp \
  --from-dir=stages/stage4-model-integration/mcp-servers/database-mcp/ \
  --follow

# After changing slack_mcp_server.py
oc start-build slack-mcp \
  --from-dir=stages/stage4-model-integration/mcp-servers/slack-mcp/ \
  --follow
```

The deployment will automatically pick up the new `:latest` tag on the next pod restart or rollout.

## Troubleshooting

### Build Failures

```bash
# Check build logs
oc logs -f build/database-mcp-1

# Common issues:
# - Missing dependencies in requirements.txt
# - Dockerfile syntax errors
# - Network issues pulling base image
```

### Image Pull Errors

```bash
# Verify ImageStream exists
oc get is database-mcp -n private-ai-demo

# Check if image was pushed successfully
oc describe is database-mcp -n private-ai-demo

# Force image pull
oc delete pod -l app=database-mcp
```

### Deployment Issues

```bash
# Check pod status
oc get pods -l app=database-mcp
oc get pods -l app=slack-mcp

# Check logs
oc logs deployment/database-mcp
oc logs deployment/slack-mcp

# Common issues:
# - Missing secrets (postgresql-credentials, slack-webhook)
# - Network connectivity to PostgreSQL or Slack
# - Port conflicts
```

## Build Strategy

We use **binary builds** instead of Git-based builds because:

1. **Local Development**: Enables rapid iteration without committing every change
2. **No Git Hooks Required**: No need to configure webhooks or triggers
3. **Reproducible**: Build process is documented and can be scripted
4. **Security**: Source code is uploaded directly, not pulled from public Git

## Image Lifecycle

```
Source Code → Binary Upload → Docker Build → Push to Registry → Deploy
    ↓              ↓                ↓               ↓             ↓
database_mcp   start-build     BuildConfig    ImageStream   Deployment
.py                                                          references
                                                             :latest tag
```

## Next Steps

After building images:
1. Deploy MCP servers
2. Register tools with LlamaStack
3. Test tool invocation via API
4. Extend Playground UI for tool selection
5. Build end-to-end agentic demo

## References

- [OpenShift Binary Builds](https://docs.openshift.com/container-platform/4.13/cicd/builds/creating-build-inputs.html#builds-binary-source_creating-build-inputs)
- [BuildConfig Reference](https://docs.openshift.com/container-platform/4.13/rest_api/workloads_apis/buildconfig-build-openshift-io-v1.html)
- [ImageStream Reference](https://docs.openshift.com/container-platform/4.13/rest_api/image_apis/imagestream-image-openshift-io-v1.html)

