# Stage 0: AI Platform - RHOAI 2.25

## Overview

Stage 0 establishes the foundational AI platform infrastructure required for all subsequent demo stages. This implementation follows the official **[Red Hat OpenShift AI 2.25 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25)** and uses intelligent detection to work on both fresh OpenShift clusters and partially configured environments.

## Components

### Operators (Automatically Detected)
- **[Node Feature Discovery (NFD)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_accelerators/index)** - Detects hardware features for GPU scheduling
- **[NVIDIA GPU Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_accelerators/index#enabling-nvidia-gpus_accelerators)** - GPU drivers and container runtime
- **[Red Hat OpenShift AI Operator 2.25](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)** - Core AI/ML platform services

### Compute Resources
- **GPU MachineSets**
  - `g6.4xlarge` (1 GPU, 24GB VRAM) - For quantized models (W4A16)
  - `g6.12xlarge` (4 GPUs, 96GB VRAM total) - For full precision models (FP16)
- **GPU Node Configuration** - Taints and tolerations for dedicated GPU scheduling

### AI Platform Services
- **[DataScienceCluster](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-and-managing-red-hat-openshift-ai-components_install)** - Core RHOAI configuration with enabled components:
  - Dashboard - Web UI for data scientists
  - Workbenches - JupyterLab environments
  - Data Science Pipelines - Tekton-based workflows
  - KServe - Single-model serving platform
  - ModelMesh - Multi-model serving platform  
  - **[Model Registry](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/enabling_the_model_registry_component/index)** - Centralized model metadata repository
  - TrustyAI - Model quality and fairness evaluation
  - Training Operator - Distributed training

## Prerequisites

- **OpenShift Cluster**: 4.16+ with admin access (`cluster-admin` role)
- **Cloud Provider**: AWS (for GPU node provisioning)
- **oc CLI**: Configured and logged in
- **Internet Connectivity**: For pulling operator images and container images

## Key Features

### Intelligent Detection

The deployment script **automatically detects** existing components and skips installation if already present:

✅ **Detects if NFD Operator is installed**  
✅ **Detects if GPU Operator is installed**  
✅ **Detects if OpenShift AI Operator is installed**  
✅ **Detects if GPU MachineSets exist**  
✅ **Detects if DataScienceCluster is configured**  

This allows you to:
- Deploy on a **fresh OpenShift 4.19 cluster** (installs everything)
- Deploy on a **partially configured cluster** (skips existing components)
- Re-run the script safely (idempotent behavior)

### Red Hat Best Practices

Follows official Red Hat OpenShift AI 2.25 documentation:

📖 [Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)  
📖 [Managing OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/managing_openshift_ai/index)  
📖 [Working with Accelerators](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_accelerators/index)  
📖 [Enabling Model Registry](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/enabling_the_model_registry_component/index)  

## Deployment

### Quick Start

```bash
# Deploy all Stage 0 components
./deploy.sh

# Validate deployment
./validate.sh
```

### What the Script Does

1. **Checks for NFD Operator** → Installs if not present
2. **Checks for GPU Operator** → Installs if not present  
3. **Checks for GPU MachineSets** → Creates if not present
4. **Checks for OpenShift AI Operator** → Installs if not present (channel: `stable-2.25`)
5. **Checks for DataScienceCluster** → Creates if not present (with Model Registry enabled)
6. **Verifies Model Registry** → Confirms deployment and route

### Expected Timeline

- **Operator Installations**: 2-5 minutes each
- **GPU Node Provisioning**: 10-15 minutes
- **DataScienceCluster Initialization**: 5-10 minutes
- **Total**: ~20-30 minutes for fresh cluster

## Verification

### Automatic Validation

Run the validation script to check all components:

```bash
./validate.sh
```

The script checks:
- ✅ All operators installed and ready
- ✅ GPU MachineSets created
- ✅ GPU machines provisioned and running
- ✅ GPU nodes available with correct labels
- ✅ OpenShift AI 2.25 operator ready
- ✅ DataScienceCluster in "Ready" state
- ✅ All components available
- ✅ Model Registry deployed with route
- ✅ Dashboard accessible

### Manual Verification Commands

```bash
# Check operators
oc get subscription -A | grep -E "nfd|gpu-operator|rhods"

# Check GPU MachineSets
oc get machinesets -n openshift-machine-api | grep gpu

# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check OpenShift AI
oc get datasciencecluster default-dsc

# Check Model Registry
oc get deployment -n rhoai-model-registries
oc get route -n rhoai-model-registries

# Access dashboard
DASHBOARD_URL=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}')
echo "Dashboard: https://$DASHBOARD_URL"
```

## Component Details

### Node Feature Discovery (NFD)

- **Purpose**: Detects hardware features (GPUs, NICs, CPUs)
- **Namespace**: `openshift-nfd`
- **Channel**: `stable`
- **Source**: `redhat-operators`

### NVIDIA GPU Operator

- **Purpose**: Manages NVIDIA GPU drivers and container runtime
- **Namespace**: `nvidia-gpu-operator`
- **Channel**: `stable`
- **Source**: `certified-operators`
- **Manages**: Driver containers, device plugins, monitoring

### GPU MachineSets

#### g6.4xlarge (Quantized Model)
- **GPUs**: 1x NVIDIA L4 (24GB VRAM)
- **CPU**: 16 vCPUs
- **Memory**: 64 GB
- **Storage**: 120 GB gp3
- **Use Case**: Mistral 24B W4A16 quantized model
- **Labels**: `nvidia.com/gpu.present=true`, `node-role.kubernetes.io/gpu=""`
- **Taints**: `nvidia.com/gpu=true:NoSchedule`

#### g6.12xlarge (Full Precision Model)
- **GPUs**: 4x NVIDIA L4 (96GB VRAM total)
- **CPU**: 48 vCPUs
- **Memory**: 192 GB
- **Storage**: 120 GB gp3
- **Use Case**: Mistral 24B FP16 full precision model
- **Labels**: `nvidia.com/gpu.present=true`, `nvidia.com/gpu.count=4`, `node-role.kubernetes.io/gpu=""`
- **Taints**: `nvidia.com/gpu=true:NoSchedule`

### Red Hat OpenShift AI Operator 2.25

- **Namespace**: `redhat-ods-operator`
- **Channel**: `stable-2.25`
- **Source**: `redhat-operators`
- **Install Plan**: Automatic

### DataScienceCluster Configuration

```yaml
spec:
  components:
    dashboard: Managed         # Web UI
    workbenches: Managed       # JupyterLab
    datasciencepipelines: Managed  # Tekton pipelines
    kserve: Managed           # Single-model serving
    modelmeshserving: Managed # Multi-model serving
    modelregistry: Managed    # Model metadata (NEW in 2.25)
    trustyai: Managed         # Model evaluation
    trainingoperator: Managed # Distributed training
    codeflare: Removed        # Not needed for demo
    ray: Removed              # Not needed for demo
```

## Troubleshooting

### GPU Nodes Not Provisioning

**Symptom**: MachineSets created but no machines appear

**Check**:
```bash
oc get machinesets -n openshift-machine-api | grep gpu
oc get machines -n openshift-machine-api | grep gpu
oc describe machineset <gpu-machineset> -n openshift-machine-api
```

**Common Causes**:
- AWS capacity constraints for GPU instances
- Incorrect AMI ID
- Network/subnet configuration issues

**Solution**:
- Verify AWS capacity in your region for `g6.4xlarge` and `g6.12xlarge`
- Check machine events: `oc get events -n openshift-machine-api --sort-by='.lastTimestamp'`

### NVIDIA GPU Operator Not Ready

**Symptom**: Operator installed but pods not running

**Check**:
```bash
oc get pods -n nvidia-gpu-operator
oc logs -n nvidia-gpu-operator <operator-pod>
```

**Common Causes**:
- Node not ready
- Driver compilation issues
- Insufficient resources

**Solution**:
- Wait for GPU nodes to be fully ready
- Check node conditions: `oc describe node <gpu-node>`

### DataScienceCluster Not Ready

**Symptom**: DSC status not "Ready"

**Check**:
```bash
oc get datasciencecluster default-dsc -o yaml
oc get events -n redhat-ods-applications --sort-by='.lastTimestamp'
```

**Common Causes**:
- Component initialization in progress
- Image pull issues
- Resource constraints

**Solution**:
- Wait 5-10 minutes for all components to initialize
- Check individual component status: `./validate.sh`
- Review operator logs: `oc logs -n redhat-ods-operator <operator-pod>`

### Model Registry Not Accessible

**Symptom**: Route exists but dashboard shows error

**Check**:
```bash
oc get deployment -n rhoai-model-registries
oc get pods -n rhoai-model-registries
oc logs -n rhoai-model-registries <pod>
```

**Common Causes**:
- MySQL database not ready
- Certificate issues
- Service mesh configuration

**Solution**:
- Verify MySQL is running: `oc get deployment model-registry-db -n rhoai-model-registries`
- Check route: `oc get route -n rhoai-model-registries`
- Review Model Registry docs: [Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/managing_model_registries/index)

## Next Steps

Once Stage 0 is validated:

1. **Verify GPU nodes are ready**:
   ```bash
   oc get nodes -l nvidia.com/gpu.present=true
   ```

2. **Access OpenShift AI Dashboard**:
   ```bash
   oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'
   ```

3. **Proceed to Stage 1: Model Serving**:
   ```bash
   cd ../stage1-model-serving-with-vllm
   ```

## Documentation References

### Official Red Hat Docs (2.25)

- [OpenShift AI 2.25 Home](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25)
- [Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [Managing OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/managing_openshift_ai/index)
- [Working with Accelerators](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_accelerators/index)
- [Enabling Model Registry](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/enabling_the_model_registry_component/index)
- [Managing Resources](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/managing_resources/index)
- [Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/managing_model_registries/index)

### Component-Specific Docs

- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Node Feature Discovery](https://kubernetes-sigs.github.io/node-feature-discovery/)
- [OpenShift Machine API](https://docs.openshift.com/container-platform/latest/machine_management/index.html)

## Architecture

```
OpenShift Cluster 4.19+
├── Node Feature Discovery Operator
│   └── Detects GPU hardware features
│
├── NVIDIA GPU Operator
│   ├── GPU driver containers
│   ├── CUDA container runtime
│   ├── Device plugin
│   └── GPU monitoring
│
├── GPU MachineSets
│   ├── g6.4xlarge (1 GPU) → Quantized models
│   └── g6.12xlarge (4 GPUs) → Full precision models
│
├── Red Hat OpenShift AI Operator 2.25
│   └── DataScienceCluster
│       ├── Dashboard (Web UI)
│       ├── Workbenches (JupyterLab)
│       ├── Data Science Pipelines (Tekton)
│       ├── KServe (Single-model serving)
│       ├── ModelMesh (Multi-model serving)
│       ├── Model Registry ⭐ NEW
│       ├── TrustyAI (Evaluation)
│       └── Training Operator
│
└── Model Registry
    ├── MySQL database (rhoai-model-registries)
    ├── Model Registry service
    └── Dashboard integration
```

---

**Stage 0 is production-ready and follows Red Hat OpenShift AI 2.25 best practices** ✅
