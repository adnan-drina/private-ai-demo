# Stage 0: AI Platform - RHOAI 2.25

This directory contains GitOps manifests for Stage 0 deployment, exported from the live cluster for visibility in Argo CD.

## ⚠️ Important Notes

1. **Deployment Method**: Stage 0 was deployed IMPERATIVELY using `stage0-ai-platform-rhoai/deploy.sh` and manual commands
2. **Purpose of These Manifests**: 
   - Provide visibility in Argo CD UI
   - Document current configuration as code
   - Enable drift detection
3. **Not for Deployment**: These manifests are for TRACKING only, not for initial deployment
4. **Cluster-Specific Values**: Contains cluster-specific IDs, zones, and URLs that need adjustment for other clusters

## Deployment Script

Use the deployment script instead:
```bash
cd stage0-ai-platform-rhoai
./deploy-gitops-bootstrap.sh  # Install GitOps
./deploy.sh                    # Deploy AI Platform
```

## Components Tracked

- **operators/**: Operator Subscriptions (NFD, GPU, RHOAI, ServiceMesh, Serverless)
- **gpu-infrastructure/**: GPU MachineSets and ClusterPolicy  
- **datasciencecluster/**: DataScienceCluster and ServiceMeshControlPlane
