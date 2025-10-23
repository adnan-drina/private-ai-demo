# GPU Provisioning - GitOps Native

This directory contains **complete GPU infrastructure as code** for Stage 1: Sovereign AI deployment.

---

## 📋 Overview

This component provisions and configures GPU nodes for AI/ML workloads using **GitOps principles**:

- **MachineSets**: Define GPU node infrastructure (g6.4xlarge, g6.12xlarge)
- **MachineConfigs**: Configure OS-level GPU settings and optimizations
- **MachineConfigPool**: Separate configuration pool for GPU nodes

**Everything is declarative, version-controlled, and reproducible.**

---

## 🏗️ Architecture

```
GPU Infrastructure Stack
│
├── MachineConfigPool: worker-gpu
│   └── Manages GPU node configuration lifecycle
│
├── MachineSets (Infrastructure)
│   ├── g6.4xlarge (1x NVIDIA L4)
│   │   • 1 GPU, 24GB VRAM
│   │   • 16 vCPUs, 64GB RAM
│   │   • For: mistral-24b-quantized
│   │
│   └── g6.12xlarge (4x NVIDIA L4)
│       • 4 GPUs, 96GB total VRAM
│       • 48 vCPUs, 192GB RAM
│       • For: mistral-24b (tensor parallel)
│
└── MachineConfigs (OS Configuration)
    ├── Base (99-worker-gpu-base)
    │   • NVIDIA driver loading
    │   • GPU monitoring setup
    │   • System tuning
    │
    ├── g6.4xlarge specific (99-worker-gpu-g6-4xlarge)
    │   • Single-GPU optimizations
    │   • Resource limits
    │   • Performance tuning
    │
    └── g6.12xlarge specific (99-worker-gpu-g6-12xlarge)
        • Multi-GPU optimizations
        • NCCL configuration
        • Tensor parallelism support
```

---

## 📦 Files in This Directory

| File | Purpose | Required |
|------|---------|----------|
| `kustomization.yaml` | Kustomize component definition | ✅ |
| `machineconfig-pool-gpu.yaml` | GPU node configuration pool | ✅ |
| `machineconfig-gpu-base.yaml` | Base GPU configuration (all GPU nodes) | ✅ |
| `machineconfig-g6-4xlarge.yaml` | g6.4xlarge specific config | ✅ |
| `machineconfig-g6-12xlarge.yaml` | g6.12xlarge specific config | ✅ |
| `g6-4xlarge.yaml` | MachineSet for 1-GPU nodes | ✅ |
| `g6-12xlarge.yaml` | MachineSet for 4-GPU nodes | ✅ |
| `README.md` | This file | 📖 |

---

## 🚀 Deployment Methods

### Method 1: GitOps (Recommended)

**Complete, automated deployment via Kustomize:**

```bash
# 1. Set cluster-specific environment variables
export CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
export AWS_REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')
export AWS_ZONE=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.placement.availabilityZone}')
export AWS_AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')
export AWS_IAM_PROFILE=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.iamInstanceProfile.id}')

# 2. Apply MachineConfigPool and MachineConfigs first
oc apply -f machineconfig-pool-gpu.yaml
oc apply -f machineconfig-gpu-base.yaml
oc apply -f machineconfig-g6-4xlarge.yaml
oc apply -f machineconfig-g6-12xlarge.yaml

# 3. Wait for MachineConfigPool to be ready
oc wait --for=condition=Updated mcp/worker-gpu --timeout=300s

# 4. Provision GPU MachineSets
envsubst < g6-4xlarge.yaml | oc apply -f -
envsubst < g6-12xlarge.yaml | oc apply -f -

# 5. Monitor provisioning
watch oc get machines -n openshift-machine-api

# 6. Wait for nodes to be Ready (5-10 minutes)
oc wait --for=condition=Ready node -l node-role.kubernetes.io/worker-gpu --timeout=15m
```

---

### Method 2: Via deploy.sh Script

The `stage1-sovereign-ai/deploy.sh` script automates this:

```bash
cd stage1-sovereign-ai
./deploy.sh

# Answer "Yes" to GPU provisioning prompt
# Script will:
#  1. Apply MachineConfigs
#  2. Create MachineConfigPool
#  3. Provision MachineSets
#  4. Wait for nodes to be Ready
```

---

### Method 3: Manual Step-by-Step

For learning or troubleshooting:

```bash
# Step 1: Create GPU MachineConfigPool
oc apply -f gitops/components/gpu-provisioning/machineconfig-pool-gpu.yaml

# Step 2: Apply base GPU MachineConfig
oc apply -f gitops/components/gpu-provisioning/machineconfig-gpu-base.yaml

# Step 3: Apply instance-specific MachineConfigs
oc apply -f gitops/components/gpu-provisioning/machineconfig-g6-4xlarge.yaml
oc apply -f gitops/components/gpu-provisioning/machineconfig-g6-12xlarge.yaml

# Step 4: Wait for MachineConfigPool to be ready
oc get mcp worker-gpu -w
# Wait until UPDATED=True, DEGRADED=False

# Step 5: Get cluster info for MachineSets
CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
AWS_REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')
AWS_ZONE=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.placement.availabilityZone}')
AWS_AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')
AWS_IAM_PROFILE=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.iamInstanceProfile.id}')

# Step 6: Create MachineSets
envsubst < gitops/components/gpu-provisioning/g6-4xlarge.yaml | oc apply -f -
envsubst < gitops/components/gpu-provisioning/g6-12xlarge.yaml | oc apply -f -

# Step 7: Monitor machine creation
oc get machines -n openshift-machine-api -w

# Step 8: Wait for nodes to join and be Ready
oc get nodes -l node-role.kubernetes.io/worker-gpu -w
```

---

## ✅ Validation

### Check MachineConfigPool Status
```bash
oc get mcp worker-gpu

# Expected output:
# NAME         CONFIG            UPDATED  UPDATING  DEGRADED  MACHINECOUNT  READYMACHINECOUNT
# worker-gpu   rendered-worker-...  True     False     False     2             2
```

### Check MachineSets
```bash
oc get machineset -n openshift-machine-api | grep g6

# Expected output:
# g6-4xlarge-gpu     1    1    1    1    10m
# g6-12xlarge-gpu    1    1    1    1    10m
```

### Check GPU Nodes
```bash
oc get nodes -l node-role.kubernetes.io/worker-gpu

# Should show 2 nodes (1x g6.4xlarge, 1x g6.12xlarge)
```

### Verify GPU Availability
```bash
oc get nodes -l nvidia.com/gpu.present=true -o json | \
  jq '.items[] | {
    name: .metadata.name,
    instance: .metadata.labels."node.kubernetes.io/instance-type",
    gpus: .status.allocatable."nvidia.com/gpu"
  }'

# Expected output:
# {
#   "name": "ip-10-0-x-x...",
#   "instance": "g6.4xlarge",
#   "gpus": "1"
# }
# {
#   "name": "ip-10-0-x-x...",
#   "instance": "g6.12xlarge",
#   "gpus": "4"
# }
```

### Check MachineConfig Application
```bash
# Check if MachineConfigs are applied
oc get mc | grep gpu

# Check GPU node configuration
oc debug node/<gpu-node-name>
# Then inside the debug shell:
sh-4.4# cat /etc/gpu-instance-config.yaml
sh-4.4# cat /etc/sysctl.d/99-gpu-tuning.conf
sh-4.4# systemctl status nvidia-driver-load.service
```

---

## 🔄 Update Process

### Updating MachineConfigs

When you modify a MachineConfig:

1. **Apply the changes:**
   ```bash
   oc apply -f machineconfig-g6-4xlarge.yaml
   ```

2. **MachineConfigOperator automatically:**
   - Creates new rendered MachineConfig
   - Cordons affected nodes one-by-one
   - Drains workloads
   - Reboots node with new configuration
   - Uncordons node when ready

3. **Monitor the update:**
   ```bash
   oc get mcp worker-gpu -w
   ```

4. **Wait for completion** (UPDATED=True, UPDATING=False)

### Scaling GPU Nodes

To add more GPU capacity:

```bash
# Scale g6.12xlarge to 2 nodes
oc scale machineset g6-12xlarge-gpu -n openshift-machine-api --replicas=2

# Or edit the MachineSet
oc edit machineset g6-12xlarge-gpu -n openshift-machine-api
# Change spec.replicas
```

---

## 🐛 Troubleshooting

### MachineConfigPool Degraded

```bash
# Check MCP status
oc describe mcp worker-gpu

# Check machine-config-daemon logs
oc logs -n openshift-machine-config-operator -l k8s-app=machine-config-daemon --tail=100

# Check for configuration errors
oc get mc 99-worker-gpu-base -o yaml
```

### Machine Stuck in Provisioning

```bash
# Check machine status
oc describe machine <machine-name> -n openshift-machine-api

# Check AWS console for EC2 instance issues
# Common issues:
#  - Quota limits (check EC2 service quotas)
#  - AMI not available in region
#  - Subnet capacity
```

### GPU Not Detected

```bash
# Check NVIDIA GPU Operator
oc get pods -n nvidia-gpu-operator

# Check GPU operator logs
oc logs -n nvidia-gpu-operator -l app=nvidia-driver-daemonset

# Verify node labels
oc get node <gpu-node> --show-labels | grep nvidia

# Check device plugin
oc get pods -n nvidia-gpu-operator -l app=nvidia-device-plugin-daemonset
```

### MachineConfig Not Applied

```bash
# Check node's current config
oc get node <gpu-node> -o jsonpath='{.metadata.annotations.machineconfiguration\.openshift\.io/currentConfig}'

# Check desired config
oc get node <gpu-node> -o jsonpath='{.metadata.annotations.machineconfiguration\.openshift\.io/desiredConfig}'

# If they don't match, check machine-config-daemon
oc logs -n openshift-machine-config-operator \
  -l k8s-app=machine-config-daemon \
  --tail=50 | grep <gpu-node>
```

---

## 📊 Cost Considerations

### AWS Instance Pricing (us-east-2, approximate)

| Instance | GPUs | vCPUs | RAM | On-Demand | Spot (est.) | Monthly (On-Demand) |
|----------|------|-------|-----|-----------|-------------|---------------------|
| g6.4xlarge | 1 | 16 | 64 GB | $1.40/hr | ~$0.42/hr | ~$1,000 |
| g6.12xlarge | 4 | 48 | 192 GB | $4.20/hr | ~$1.26/hr | ~$3,000 |

**Total (both nodes)**: ~$4,000/month (On-Demand) or ~$1,200/month (Spot)

### Cost Optimization Tips

1. **Use Spot Instances** (not in current config, but possible)
2. **Auto-scaling**: Scale down during off-hours
3. **Right-sizing**: Start with quantized model only (g6.4xlarge)
4. **Reserved Instances**: For production workloads

---

## 🔒 Security Considerations

### MachineConfig Security

- All configurations are **read-only** (mode: 0644)
- Executable scripts are **restricted** (mode: 0755, root-only)
- No secrets or sensitive data in MachineConfigs
- GPU access **controlled via RBAC** and node taints

### Network Security

- GPU nodes **tainted by default** (nvidia.com/gpu=true:NoSchedule)
- Only pods with **tolerations** can schedule
- **Network policies** should restrict GPU node access
- **Monitoring enabled** for security auditing

---

## 📚 Additional Resources

### Documentation
- [OpenShift Machine Config Operator](https://docs.openshift.com/container-platform/latest/post_installation_configuration/machine-configuration-tasks.html)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
- [AWS EC2 G6 Instances](https://aws.amazon.com/ec2/instance-types/g6/)

### Related Files
- `stage1-sovereign-ai/deploy.sh` - Automated deployment script
- `gitops/base/vllm/` - vLLM InferenceService configurations
- `STAGE1-DEPLOYMENT-ISSUES.md` - Known issues and resolutions

---

## ✨ What Makes This GitOps-Native

1. ✅ **Declarative**: All configuration as YAML
2. ✅ **Version-controlled**: In Git repository
3. ✅ **Reproducible**: Same inputs → same outputs
4. ✅ **Auditable**: Full history of changes
5. ✅ **Automated**: Apply via `oc apply` or Kustomize
6. ✅ **Self-documenting**: Comments in configurations
7. ✅ **Idempotent**: Safe to re-apply

---

## 🎯 Next Steps

After GPU nodes are provisioned and configured:

1. ✅ GPU nodes are Ready
2. → Deploy Stage 1 models:
   ```bash
   cd ../../../stage1-sovereign-ai
   ./deploy.sh
   # Skip GPU provisioning (already done)
   ```

3. → Verify InferenceServices schedule on GPU nodes:
   ```bash
   oc get pods -n private-ai-demo -o wide
   ```

---

**Last Updated**: 2025-10-09  
**Maintained By**: Red Hat AI Demo Team  
**Status**: Production Ready

