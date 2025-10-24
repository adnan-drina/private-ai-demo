# Stage 0: AI Platform - RHOAI

## Overview

Stage 0 establishes the foundational AI platform infrastructure required for all subsequent demo stages. This includes OpenShift AI (RHOAI) 2.24, GPU operator, GPU-enabled worker nodes, and the Model Registry.

## Components

### Platform Services
- **OpenShift AI Operator 2.24** - Core AI/ML platform services
- **DataScienceCluster** - Configured with Model Registry enabled
- **GPU Operator** - NVIDIA GPU support and drivers

### Compute Resources
- **GPU MachineSets**
  - `g6.4xlarge` (1 GPU) - For quantized models
  - `g6.12xlarge` (4 GPUs) - For full precision models
- **MachineConfigs** - GPU node taints and tolerations

### Model Management
- **Model Registry** - Central model metadata repository
- **MySQL Database** - Model Registry backend storage

## Prerequisites

- OpenShift cluster (4.16+)
- Admin access (`cluster-admin` role)
- AWS credentials for provisioning GPU nodes
- Internet connectivity for pulling operator images

## Deployment

```bash
# Deploy all Stage 0 components
./deploy.sh

# Validate deployment
./validate.sh
```

## Verification

After deployment, verify:

```bash
# Check OpenShift AI operator
oc get csv -n redhat-ods-operator | grep rhods-operator

# Check DataScienceCluster
oc get datasciencecluster

# Check GPU nodes
oc get nodes -l node.kubernetes.io/instance-type | grep g6

# Check Model Registry
oc get deployment model-registry-db -n rhoai-model-registries
```

## Next Steps

Once Stage 0 is deployed and validated:
1. Proceed to **Stage 1: Model Serving with vLLM**
2. Models will be deployed on the provisioned GPU nodes
3. Model metadata will be registered in the Model Registry

## Troubleshooting

### GPU Nodes Not Provisioning
- Check MachineSet status: `oc get machinesets -n openshift-machine-api`
- Check Machine status: `oc get machines -n openshift-machine-api | grep gpu`
- Verify AWS capacity for GPU instance types

### Model Registry Not Starting
- Check MySQL pod logs: `oc logs -n rhoai-model-registries deployment/model-registry-db`
- Verify PVC is bound: `oc get pvc -n rhoai-model-registries`

## GitOps Structure

```
gitops-new/stage00-ai-platform-rhoai/
├── operators/           # OpenShift AI & GPU operators
├── datasciencecluster/  # DSC configuration
├── gpu-machinesets/     # GPU node provisioning
├── gpu-machineconfigs/  # GPU node configuration
└── model-registry/      # Model Registry + MySQL
```

## Documentation

- [OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.24)
- [GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Model Registry Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.24/html/managing_model_registries/)
