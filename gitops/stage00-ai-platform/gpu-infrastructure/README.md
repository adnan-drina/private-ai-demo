# GPU Infrastructure - Dynamic MachineSet Generation

This directory contains GitOps manifests for deploying GPU infrastructure on OpenShift AWS clusters using **dynamic MachineSet generation**.

## Overview

Instead of hardcoded MachineSet YAMLs (which only work on specific clusters), we use a Kubernetes Job to dynamically generate GPU MachineSets by cloning existing worker MachineSets and modifying them for GPU workloads.

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    ArgoCD Sync or oc apply                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. RBAC Resources Created                                       │
│     - ServiceAccount: gpu-machineset-generator                   │
│     - ClusterRole: permissions to read/create MachineSets       │
│     - ClusterRoleBinding                                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. ConfigMap with Shell Script                                  │
│     - Contains MachineSet generation logic                       │
│     - Mounted into Job pod                                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Job Executes (ArgoCD Sync Hook)                             │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ a. Detect cluster infrastructure ID                 │    │
│     │    $ oc get infrastructure cluster                  │    │
│     │    → cluster-zpqdx-xxm9n                            │    │
│     ├─────────────────────────────────────────────────────┤    │
│     │ b. Find existing worker MachineSet                  │    │
│     │    $ oc get machineset | grep worker                │    │
│     │    → cluster-zpqdx-xxm9n-worker-us-east-2a          │    │
│     ├─────────────────────────────────────────────────────┤    │
│     │ c. Clone worker MachineSet                          │    │
│     │    $ oc get machineset <worker> -o yaml | ...       │    │
│     ├─────────────────────────────────────────────────────┤    │
│     │ d. Modify for GPU                                   │    │
│     │    - Change instanceType: g6.4xlarge / g6.12xlarge  │    │
│     │    - Add labels: nvidia.com/gpu.present=true        │    │
│     │    - Add taints: nvidia.com/gpu=true:NoSchedule     │    │
│     │    - Update name: ...-gpu-g6-4xlarge-us-east-2a     │    │
│     ├─────────────────────────────────────────────────────┤    │
│     │ e. Apply GPU MachineSet                             │    │
│     │    $ oc apply -f -                                  │    │
│     │    → cluster-zpqdx-xxm9n-gpu-g6-4xlarge-us-east-2a  │    │
│     │    → cluster-zpqdx-xxm9n-gpu-g6-12xlarge-us-east-2a │    │
│     └─────────────────────────────────────────────────────┘    │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. MachineSets Create GPU Machines                             │
│     - AWS provisions EC2 instances                              │
│     - Instances join cluster as GPU nodes                       │
│     - Nodes labeled: nvidia.com/gpu.present=true                │
│     - Nodes tainted: nvidia.com/gpu=true:NoSchedule             │
└─────────────────────────────────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `rbac-machineset-job.yaml` | ServiceAccount, ClusterRole, ClusterRoleBinding for Job |
| `configmap-machineset-script.yaml` | Shell script that generates GPU MachineSets |
| `job-generate-gpu-machineset.yaml` | Kubernetes Job definition (ArgoCD Sync hook) |
| `nodefeaturediscovery.yaml` | Node Feature Discovery Operator instance |
| `clusterpolicy.yaml` | NVIDIA GPU Operator ClusterPolicy |
| `kustomization.yaml` | Kustomize manifest that applies all resources |

## GPU Configurations

### g6.4xlarge (Single GPU)
- **GPU**: 1x NVIDIA L4 (24GB GDDR6)
- **vCPU**: 16
- **Memory**: 64 GB
- **Use Case**: Single model inference, development, testing

### g6.12xlarge (Multi-GPU)
- **GPU**: 4x NVIDIA L4 (96GB total GDDR6)
- **vCPU**: 48
- **Memory**: 192 GB
- **Use Case**: Multi-model serving, high throughput, production

## Deployment

### Prerequisites

1. OpenShift 4.14+ cluster on AWS
2. At least one worker MachineSet exists
3. AWS EC2 capacity for GPU instances in your region
4. OpenShift GitOps operator (for ArgoCD hooks)

### Apply Manually

```bash
oc apply -k gitops/stage00-ai-platform/gpu-infrastructure/
```

**Output:**
```
serviceaccount/gpu-machineset-generator created
clusterrole.rbac.authorization.k8s.io/gpu-machineset-generator created
clusterrolebinding.rbac.authorization.k8s.io/gpu-machineset-generator created
configmap/gpu-machineset-generator-script created
job.batch/gpu-machineset-generator created
nodefeaturediscovery.nfd.openshift.io/nfd-instance created
clusterpolicy.nvidia.com/gpu-cluster-policy created
```

### Monitor Job Progress

```bash
# Watch Job status
oc get job -n openshift-machine-api gpu-machineset-generator -w

# View Job logs
oc logs -n openshift-machine-api -l app.kubernetes.io/name=gpu-machineset-generator

# Check created MachineSets
oc get machineset -n openshift-machine-api | grep gpu
```

### Verify GPU Nodes

```bash
# Wait for machines to provision (10-15 minutes)
oc get machines -n openshift-machine-api | grep gpu

# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Verify NVIDIA GPU Operator
oc get pods -n nvidia-gpu-operator
```

## Benefits

### ✅ Fully Reproducible
- Works on **any** OpenShift AWS cluster
- No manual editing required
- No hardcoded cluster-specific values

### ✅ Inherits Cluster Configuration
Automatically inherits from worker MachineSets:
- Security groups
- IAM instance profiles
- Subnets
- AMI IDs
- Tags
- Availability zone

### ✅ GitOps Native
- ArgoCD Sync hook for automatic execution
- Idempotent (safe to re-run)
- Version controlled logic
- Declarative infrastructure

### ✅ Red Hat Aligned
Based on [Red Hat GitOps Catalog](https://github.com/redhat-cop/gitops-catalog/tree/main/gpu-operator-certified/instance/components/aws-gpu-machineset) best practices.

## Troubleshooting

### Job Fails: Permission Denied

**Symptom**: Job pod shows `Error: Unable to create machineset`

**Solution**: Verify RBAC is applied
```bash
oc get clusterrole gpu-machineset-generator
oc get clusterrolebinding gpu-machineset-generator
```

### MachineSets Not Created

**Symptom**: Job completes but no GPU MachineSets exist

**Solution**: Check Job logs for errors
```bash
oc logs -n openshift-machine-api -l app.kubernetes.io/name=gpu-machineset-generator
```

### Machines Stay in "Provisioning" State

**Symptom**: GPU machines don't become Ready

**Solution**: Check AWS EC2 instance status
```bash
oc describe machine <machine-name> -n openshift-machine-api
```

Common causes:
- AWS capacity limits for GPU instances
- Regional availability issues
- EC2 service quotas

### Machines Fail Immediately

**Symptom**: Machines go to "Failed" state

**Solution**: Describe the failed machine
```bash
oc describe machine <machine-name> -n openshift-machine-api
```

Look for:
- Security group errors
- Subnet issues
- IAM profile problems
- AMI availability

**If inherited values are incorrect**, the worker MachineSet may be misconfigured.

## Customization

### Change GPU Instance Types

Edit `configmap-machineset-script.yaml`:

```bash
# Change from g6.4xlarge to g4dn.4xlarge
create_gpu_machineset "g4dn.4xlarge" "1" "1"

# Add p4d.24xlarge for A100 GPUs
create_gpu_machineset "p4d.24xlarge" "8" "0"
```

Supported AWS GPU instances:
- **g6**: NVIDIA L4 (24GB) - Cost-effective inference
- **g4dn**: NVIDIA T4 (16GB) - Budget inference
- **p4d**: NVIDIA A100 (40GB) - Training & inference
- **p5**: NVIDIA H100 (80GB) - High-performance training

### Change Replicas

Default is `1` replica per MachineSet. To change:

```bash
create_gpu_machineset "g6.4xlarge" "1" "2"  # 2 nodes
```

### Add MachineAutoscaler

To enable autoscaling, add after MachineSet creation in script:

```bash
cat << YAML | oc apply -f -
apiVersion: "autoscaling.openshift.io/v1beta1"
kind: "MachineAutoscaler"
metadata:
  name: "${GPU_MS_NAME}"
  namespace: "openshift-machine-api"
spec:
  minReplicas: 0
  maxReplicas: 4
  scaleTargetRef:
    apiVersion: machine.openshift.io/v1beta1
    kind: MachineSet
    name: "${GPU_MS_NAME}"
YAML
```

## Comparison: Old vs New

### Old Approach (Hardcoded)

```yaml
# ❌ machineset-cluster-gmgrr-j2lhd-gpu-g6-4xlarge-us-east-2c.yaml
metadata:
  name: cluster-gmgrr-j2lhd-gpu-g6-4xlarge-us-east-2c
spec:
  providerSpec:
    value:
      securityGroups:
        - filters:
          - name: tag:Name
            values:
            - cluster-gmgrr-j2lhd-node  # ❌ Hardcoded!
```

**Problems**:
- Only works on cluster-gmgrr
- Fails on any other cluster
- Requires manual editing for each deployment
- Not reproducible

### New Approach (Dynamic)

```bash
# ✅ Job clones worker MachineSet at runtime
WORKER_MS=$(oc get machineset -n openshift-machine-api | grep worker | head -1)
oc get machineset "${WORKER_MS}" -o yaml | \
  sed "s/${WORKER_MS}/${GPU_MS_NAME}/g" | \
  sed "s/instanceType: .*/instanceType: g6.4xlarge/" | \
  oc apply -f -
```

**Benefits**:
- Works on ANY cluster
- Inherits all cluster-specific values
- Zero manual editing
- Fully reproducible

## Related Documentation

- [Stage 0 README](../README.md) - AI Platform deployment overview
- [GitOps Refactoring Validation](../../../docs/00-VALIDATION/GITOPS-REFACTORING-VALIDATION.md) - Test results
- [Red Hat GitOps Catalog - GPU MachineSet](https://github.com/redhat-cop/gitops-catalog/tree/main/gpu-operator-certified/instance/components/aws-gpu-machineset)

## Support

For issues or questions:
1. Check Job logs: `oc logs -n openshift-machine-api -l app.kubernetes.io/name=gpu-machineset-generator`
2. Review validation docs: `docs/00-VALIDATION/GITOPS-REFACTORING-VALIDATION.md`
3. Open GitHub issue: https://github.com/adnan-drina/private-ai-demo/issues

