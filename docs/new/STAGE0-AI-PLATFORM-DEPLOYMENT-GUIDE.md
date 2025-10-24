# Stage 0: AI Platform - Red Hat OpenShift AI 2.25 Deployment Guide

**Document Purpose**: Complete reference for Stage 0 deployment. Use this to refresh context when returning to this demo segment.

**Deployment Date**: October 24, 2025  
**Cluster**: cluster-gmgrr.gmgrr.sandbox5294.opentlc.com  
**OpenShift Version**: 4.19.16  
**Kubernetes Version**: v1.32.9

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Deployment Method: Hybrid GitOps Approach](#deployment-method-hybrid-gitops-approach)
4. [Deployed Components](#deployed-components)
5. [Step-by-Step Deployment Process](#step-by-step-deployment-process)
6. [Issues Encountered & Solutions](#issues-encountered--solutions)
7. [Access Points & Credentials](#access-points--credentials)
8. [Validation & Verification](#validation--verification)
9. [Red Hat Documentation References](#red-hat-documentation-references)
10. [Next Steps](#next-steps)

---

## Executive Summary

Stage 0 establishes the **AI Platform foundation** for the Red Hat AI Demo. This stage deploys Red Hat OpenShift AI 2.25 with full GPU support, enabling Stages 1-4 (Model Serving, RAG, Monitoring, and MCP Integration).

### Key Achievements

✅ **OpenShift GitOps 1.18.1** - GitOps foundation with Argo CD  
✅ **Red Hat OpenShift AI 2.25.0** - Complete AI/ML platform  
✅ **GPU Infrastructure** - 2 GPU nodes (g6.4xlarge, g6.12xlarge) provisioned  
✅ **DataScienceCluster** - All 10 components ready (KServe, Model Registry, TrustyAI, Workbenches, Pipelines, etc.)  
✅ **Service Mesh 2.6.11** - For KServe ingress and traffic management  
✅ **Serverless 1.36.1** - For KServe serverless model serving  

### Deployment Time

- **GitOps Bootstrap**: 5 minutes
- **AI Platform Operators**: 10 minutes
- **DataScienceCluster**: 5 minutes
- **GPU Nodes Provisioning**: 25 minutes
- **Total**: ~45 minutes

### Deployment Method

**Hybrid GitOps Approach**:
- **Stage 0a (GitOps Bootstrap)**: Imperative deployment via `deploy-gitops-bootstrap.sh`
- **Stage 0b (AI Platform)**: Imperative deployment via manual commands
- **Stages 1-4 (Demo Apps)**: Declarative GitOps via Argo CD (future)

**Rationale**: Platform operators have complex dependencies and require troubleshooting during initial setup. Application-level resources in Stages 1-4 are ideal for pure GitOps management.

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    OpenShift 4.19 Cluster                            │
│                                                                       │
│  ┌────────────────────┐     ┌─────────────────────────────────┐    │
│  │ GitOps Layer       │     │ AI Platform Layer                │    │
│  │                    │     │                                   │    │
│  │ • Argo CD 1.18     │     │ • Red Hat OpenShift AI 2.25      │    │
│  │ • Cluster-admin    │     │ • DataScienceCluster (10 comps) │    │
│  │ • Custom health    │     │ • Model Registry                 │    │
│  │   checks           │     │ • KServe (Model Serving)        │    │
│  └────────────────────┘     │ • TrustyAI (Monitoring)         │    │
│                              │ • Tekton Pipelines               │    │
│                              │ • JupyterLab Workbenches        │    │
│                              └─────────────────────────────────┘    │
│                                                                       │
│  ┌────────────────────┐     ┌─────────────────────────────────┐    │
│  │ Service Mesh 2.6   │     │ Serverless 1.36                  │    │
│  │                    │     │                                   │    │
│  │ • Istio ingress    │     │ • Knative Serving                │    │
│  │ • Traffic mgmt     │     │ • Autoscaling                    │    │
│  └────────────────────┘     └─────────────────────────────────┘    │
│                                                                       │
│  ┌────────────────────┐     ┌─────────────────────────────────┐    │
│  │ GPU Infrastructure │     │ Node Feature Discovery 4.19      │    │
│  │                    │     │                                   │    │
│  │ • g6.4xlarge  (1   │     │ • Hardware detection             │    │
│  │   GPU)             │     │ • GPU labeling                   │    │
│  │ • g6.12xlarge (4   │     │                                   │    │
│  │   GPUs)            │     │ NVIDIA GPU Operator 25.3.4       │    │
│  │ • Taints &         │     │                                   │    │
│  │   tolerations      │     │ • Driver deployment              │    │
│  │                    │     │ • Device plugin                  │    │
│  └────────────────────┘     └─────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Dependencies

```
OpenShift GitOps (Stage 0a)
    ↓
Node Feature Discovery Operator
    ↓
NVIDIA GPU Operator
    ↓
Service Mesh Operator ────→ ServiceMeshControlPlane
    ↓
Serverless Operator ───────→ Knative Serving
    ↓
Red Hat OpenShift AI Operator
    ↓
DataScienceCluster
    ├→ KServe (requires Service Mesh + Serverless)
    ├→ Model Registry
    ├→ TrustyAI
    ├→ Workbenches
    ├→ Tekton Pipelines
    └→ Other components

GPU MachineSets
    ↓
GPU Machines (AWS EC2)
    ↓
GPU Nodes (joined to cluster)
    ↓
GPU ClusterPolicy
    ↓
GPU Operator Pods (on GPU nodes)
```

---

## Deployment Method: Hybrid GitOps Approach

### Why Hybrid?

**GitOps Best Practice** states that infrastructure should be managed declaratively. However, for initial platform setup:

| Aspect | Imperative (Our Choice) | Pure GitOps | Reasoning |
|--------|-------------------------|-------------|-----------|
| **Bootstrap Problem** | ✅ Use script | ❌ Can't GitOps GitOps | Can't use Argo CD to install itself |
| **Operator Dependencies** | ✅ Easier troubleshooting | ⚠️ Complex sync waves | ServiceMesh → Serverless → RHOAI requires careful ordering |
| **Cluster-Specific Config** | ✅ Detect at runtime | ⚠️ Templating needed | AWS security groups, subnets, zones vary by cluster |
| **Initial Setup** | ✅ Faster iteration | ⚠️ Slower debugging | Issues require git commits to test |
| **Demo Applications** | ⏭️ Next phase | ✅ Ideal use case | Application resources stable, benefit from GitOps |

### Implementation

**Stage 0a: GitOps Bootstrap** (Imperative)
- Script: `stage0-ai-platform-rhoai/deploy-gitops-bootstrap.sh`
- Duration: ~5 minutes
- Result: Argo CD ready for managing applications

**Stage 0b: AI Platform** (Imperative)
- Manual OpenShift commands (documented below)
- Duration: ~15 minutes (operators) + ~25 minutes (GPU nodes)
- Result: Full platform ready

**Stages 1-4: Demo Applications** (GitOps - Future)
- Argo CD Applications for each stage
- Declarative management
- Automatic sync and self-heal

---

## Deployed Components

### 1. OpenShift GitOps

| Component | Version | Namespace | Purpose |
|-----------|---------|-----------|---------|
| OpenShift GitOps Operator | 1.18.1 | openshift-operators | GitOps platform |
| Argo CD Instance | 1.18.1 | openshift-gitops | Declarative deployment engine |
| Argo CD Server (8 pods) | 1.18.1 | openshift-gitops | UI, API, controllers |

**Key Configurations**:
- Cluster-admin permissions for platform management
- Custom health checks for Subscriptions and DataScienceCluster
- Resource exclusions for Tekton TaskRuns/PipelineRuns
- OpenShift SSO integration

### 2. GPU Infrastructure

| Component | Specification | Purpose |
|-----------|--------------|---------|
| Node Feature Discovery | v4.19.0 | Detects GPU hardware, labels nodes |
| NVIDIA GPU Operator | v25.3.4 | Manages GPU drivers and device plugins |
| GPU MachineSet 1 | g6.4xlarge (1x NVIDIA L4 GPU) | Mistral 24B Quantized model |
| GPU MachineSet 2 | g6.12xlarge (4x NVIDIA L4 GPUs) | Mistral 24B Full Precision model |
| ClusterPolicy | gpu-cluster-policy | Activates GPU operator on GPU nodes |

**GPU Node Configuration**:
```yaml
Labels:
  nvidia.com/gpu.present: "true"
  node-role.kubernetes.io/gpu: ""
  
Taints:
  - key: nvidia.com/gpu
    value: "true"
    effect: NoSchedule
```

**Purpose**: Dedicated GPU nodes ensure AI workloads don't interfere with general workloads. Taints prevent non-GPU pods from scheduling on expensive GPU nodes.

### 3. Service Mesh & Serverless

| Component | Version | Purpose |
|-----------|---------|---------|
| Red Hat OpenShift Service Mesh | 2.6.11 | Istio-based service mesh for KServe |
| ServiceMeshControlPlane | v2.6 (istio-system) | Control plane for ingress gateway |
| Red Hat OpenShift Serverless | 1.36.1 | Knative for serverless deployments |
| Knative Serving | 1.36.1 | Autoscaling and serverless runtime |

**Required For**: KServe model serving platform

### 4. Red Hat OpenShift AI

| Component | Version | Management State | Purpose |
|-----------|---------|------------------|---------|
| RHOAI Operator | 2.25.0 | Managed | Platform operator |
| DataScienceCluster | 2.25.0 | Ready | Main AI platform resource |
| Dashboard | Managed | Ready | Web UI for data scientists |
| KServe | Managed | Ready | Model serving (serverless & raw) |
| Model Registry | Managed | Ready | Model metadata & versioning |
| Model Mesh Serving | Managed | Ready | Multi-model serving |
| TrustyAI | Managed | Ready | Model evaluation & monitoring |
| Tekton Pipelines | Managed | Ready | CI/CD for ML workflows |
| Workbenches | Managed | Ready | JupyterLab environments |
| Training Operator | Managed | Ready | Distributed training jobs |
| CodeFlare | Removed | - | Not needed for demo |
| Ray | Removed | - | Not needed for demo |

### Component Namespace Distribution

| Namespace | Purpose | Key Pods |
|-----------|---------|----------|
| `openshift-gitops` | GitOps | Argo CD server, controller, repo-server |
| `openshift-nfd` | GPU detection | NFD controller |
| `nvidia-gpu-operator` | GPU management | GPU operator, device plugins, drivers (on GPU nodes) |
| `istio-system` | Service Mesh | Istio control plane, ingress gateway |
| `knative-serving` | Serverless | Knative activator, autoscaler, controller |
| `redhat-ods-operator` | RHOAI operator | RHOAI operator pod |
| `redhat-ods-applications` | RHOAI components | Dashboard, model controller, pipelines operator |
| `rhoai-model-registries` | Model Registry | Model registry instances (per project) |
| `rhods-notebooks` | Workbenches | JupyterLab workbench pods (per user) |

---

## Step-by-Step Deployment Process

### Prerequisites

- OpenShift 4.16+ cluster with admin access
- `oc` CLI installed and configured
- AWS credentials for MachineSet provisioning (for AWS clusters)
- Cluster has internet access for operator downloads

### Phase 1: GitOps Bootstrap (~5 minutes)

```bash
cd stage0-ai-platform-rhoai
./deploy-gitops-bootstrap.sh
```

**What it does**:
1. Creates `openshift-gitops` namespace
2. Installs OpenShift GitOps Operator (latest channel)
3. Waits for Argo CD instance to be ready
4. Grants cluster-admin permissions to Argo CD
5. Configures custom health checks and resource exclusions
6. Displays Argo CD URL and admin password

**Verification**:
```bash
oc get pods -n openshift-gitops
# Should show 8 running pods

oc get route openshift-gitops-server -n openshift-gitops
# Returns Argo CD URL
```

### Phase 2: GPU Infrastructure (~15 minutes for operators, ~25 minutes for nodes)

#### Step 2.1: Node Feature Discovery Operator

```bash
oc create namespace openshift-nfd

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nfd-operator-group
  namespace: openshift-nfd
spec:
  targetNamespaces:
  - openshift-nfd
EOF

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: stable
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

**Wait for operator**:
```bash
oc get csv -n openshift-nfd | grep nfd
# Wait for "Succeeded"
```

#### Step 2.2: NVIDIA GPU Operator

```bash
oc create namespace nvidia-gpu-operator

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator-group
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
  - nvidia-gpu-operator
EOF

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: stable
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

**Wait for operator**:
```bash
oc get csv -n nvidia-gpu-operator | grep gpu-operator
# Wait for "Succeeded"
```

### Phase 3: Service Mesh & Serverless (~10 minutes)

#### Step 3.1: Service Mesh Operator

```bash
oc create namespace openshift-operators-redhat

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-operators-redhat
  namespace: openshift-operators-redhat
spec: {}
EOF

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

#### Step 3.2: Serverless Operator

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: serverless-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: serverless-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

**Wait for operators**:
```bash
oc get csv -n openshift-operators | grep -E "servicemesh|serverless"
# Wait for both to show "Succeeded"
```

#### Step 3.3: ServiceMeshControlPlane

```bash
oc create namespace istio-system

cat <<EOF | oc apply -f -
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: data-science-smcp
  namespace: istio-system
spec:
  version: v2.6
  tracing:
    type: None
  gateways:
    ingress:
      service:
        type: ClusterIP
    egress:
      service:
        type: ClusterIP
  policy:
    type: Istiod
  addons:
    grafana:
      enabled: false
    kiali:
      enabled: false
    prometheus:
      enabled: false
  telemetry:
    type: Istiod
EOF
```

**Wait for Service Mesh to be ready**:
```bash
oc get smcp data-science-smcp -n istio-system
# Wait for status to show components ready
```

### Phase 4: Red Hat OpenShift AI (~5 minutes)

```bash
oc create namespace redhat-ods-operator

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable-2.25
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

**Wait for RHOAI operator**:
```bash
oc get csv -n redhat-ods-operator | grep rhods
# Wait for "Succeeded"
```

### Phase 5: DataScienceCluster (~5 minutes)

```bash
cat <<EOF | oc apply -f -
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    codeflare:
      managementState: Removed
    dashboard:
      managementState: Managed
    datasciencepipelines:
      managementState: Managed
    kserve:
      managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: SelfSigned
        managementState: Managed
        name: knative-serving
    modelmeshserving:
      managementState: Managed
    modelregistry:
      managementState: Managed
      registriesNamespace: rhoai-model-registries
    ray:
      managementState: Removed
    trainingoperator:
      managementState: Managed
    trustyai:
      managementState: Managed
    workbenches:
      managementState: Managed
EOF
```

**Wait for DataScienceCluster**:
```bash
oc get datasciencecluster default-dsc
# Wait for READY=True
```

### Phase 6: GPU MachineSets (~25 minutes for node provisioning)

**Important**: Get cluster-specific values first:

```bash
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')
AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')

# Check existing worker MachineSet for correct zone, security groups, and subnet
EXISTING_WORKER_MS=$(oc get machinesets -n openshift-machine-api -o name | grep worker | head -1)
oc get $EXISTING_WORKER_MS -n openshift-machine-api -o yaml | grep -E "availabilityZone|securityGroups|subnet" -A 5

# Use the correct AZ from existing workers (e.g., us-east-2c)
AZ="us-east-2c"  # Replace with actual AZ from your cluster
```

**Create g6.4xlarge MachineSet** (1 GPU for quantized model):

See full YAML in `gitops-new/stage00-ai-platform/gpu-infrastructure/machineset-g6-4xlarge.yaml`

Key points:
- Instance type: `g6.4xlarge`
- Label: `nvidia.com/gpu.present=true`
- Taint: `nvidia.com/gpu=true:NoSchedule`
- Security groups: Use cluster-specific `-node` and `-lb` groups
- Subnet: Use cluster-specific private subnet in the correct AZ

**Create g6.12xlarge MachineSet** (4 GPUs for full model):

See full YAML in `gitops-new/stage00-ai-platform/gpu-infrastructure/machineset-g6-12xlarge.yaml`

Key points:
- Instance type: `g6.12xlarge`
- Label: `nvidia.com/gpu.count=4`
- Same taint and network config as g6.4xlarge

**Wait for nodes**:
```bash
watch -n 30 'oc get machines -n openshift-machine-api | grep gpu'
# Wait for "Provisioned" then "Running"

oc get nodes -l node-role.kubernetes.io/gpu
# Wait for nodes to be "Ready"
```

### Phase 7: GPU ClusterPolicy (~10 minutes)

```bash
cat <<EOF | oc apply -f -
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
    use_ocp_driver_toolkit: true
  mig:
    strategy: single
  dcgm:
    enabled: true
  gfd:
    enabled: true
  dcgmExporter:
    enabled: true
  driver:
    enabled: true
    version: latest
  devicePlugin:
    enabled: true
  daemonsets:
    updateStrategy: RollingUpdate
    rollingUpdate:
      maxUnavailable: "1"
  toolkit:
    enabled: true
  validator:
    plugin:
      env:
        - name: WITH_WORKLOAD
          value: "true"
  nodeStatusExporter:
    enabled: true
EOF
```

**Verify GPU operator pods on nodes**:
```bash
oc get pods -n nvidia-gpu-operator
# Should show driver, device-plugin pods on GPU nodes

oc describe node <gpu-node-name> | grep nvidia.com/gpu
# Should show GPU capacity (1 or 4)
```

---

## Issues Encountered & Solutions

### Issue 1: KServe Not Ready After DataScienceCluster Creation

**Symptom**:
```
DataScienceCluster status: Not Ready
KserveReady: False
Message: ServiceMesh operator must be installed for this component's configuration
         Serverless operator must be installed for this component's configuration
```

**Root Cause**: Service Mesh and Serverless operators are prerequisites for KServe but were not installed.

**Solution**: 
1. Install Service Mesh Operator
2. Install Serverless Operator
3. Create ServiceMeshControlPlane
4. DataScienceCluster automatically reconciles and KServe becomes ready

**Documentation**: [Red Hat OpenShift AI 2.25 - Serving models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/serving_models/index)

### Issue 2: GPU MachineSets Failed - "no security group found"

**Symptom**:
```
Machine status: Failed
Event: error getting security groups IDs: no security group found
```

**Root Cause**: MachineSets used incorrect security group names (`cluster-*-worker-sg`) instead of actual names (`cluster-*-node`, `cluster-*-lb`).

**Solution**: Inspected existing worker MachineSet to get correct security group filter:

```bash
oc get machineset <existing-worker-ms> -n openshift-machine-api -o yaml | grep -A 5 securityGroups
```

Updated MachineSet to use:
```yaml
securityGroups:
- filters:
  - name: tag:Name
    values:
    - cluster-gmgrr-j2lhd-node
- filters:
  - name: tag:Name
    values:
    - cluster-gmgrr-j2lhd-lb
```

**Learning**: Always derive cluster-specific config from existing resources, don't assume naming conventions.

### Issue 3: GPU MachineSets Failed - "no subnet IDs were found"

**Symptom**:
```
Machine status: Failed
Event: error getting subnet IDs: no subnet IDs were found
```

**Root Cause**: Used wrong availability zone (`us-east-2a`) when cluster workers were in `us-east-2c`.

**Solution**: 
1. Check existing worker MachineSets for correct AZ
2. Recreate GPU MachineSets in correct AZ with correct subnet name
3. Machines provisioned successfully

**Learning**: Always check actual cluster topology before creating MachineSets.

### Issue 4: GPU Resources Not Showing on Nodes

**Symptom**: GPU nodes joined but `oc describe node` shows 0 GPUs.

**Root Cause**: ClusterPolicy not created to activate GPU operator.

**Solution**: Create ClusterPolicy resource (Phase 7 above). GPU operator then deploys driver and device plugin pods to GPU nodes.

**Verification**:
```bash
oc get clusterpolicy
oc get pods -n nvidia-gpu-operator
oc describe node <gpu-node> | grep nvidia.com/gpu
```

---

## Access Points & Credentials

### Argo CD UI

**URL**: `https://openshift-gitops-server-openshift-gitops.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com`

**Login Options**:
1. **OpenShift SSO**: Click "Log in via OpenShift", use OpenShift admin credentials
2. **Admin User**: Username `admin`, password retrieved via:
   ```bash
   oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-
   ```
   Current password: `yrnxFiwhel9M1BQ4cvgOJRkmX2tWsa0K`

### OpenShift AI Dashboard

**URL**: `https://rhods-dashboard-redhat-ods-applications.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com`

**Login**: Use OpenShift SSO (same as console)

**Capabilities**:
- Create Data Science Projects
- Launch JupyterLab Workbenches
- Deploy models via KServe
- View Model Registry
- Run Data Science Pipelines
- Monitor TrustyAI evaluations

### Cluster Access

```bash
oc login https://api.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com:6443 \
  --username=<your-username> \
  --password=<your-password> \
  --insecure-skip-tls-verify
```

---

## Validation & Verification

### Quick Health Check

```bash
# Check DataScienceCluster
oc get datasciencecluster default-dsc
# Should show READY=True

# Check operators
oc get csv -A | grep -E "gitops|nfd|gpu|rhods|servicemesh|serverless" | grep Succeeded

# Check GPU nodes
oc get nodes -l node-role.kubernetes.io/gpu

# Check GPU resources
for node in $(oc get nodes -l node-role.kubernetes.io/gpu -o name); do
  echo "=== $node ==="
  oc describe $node | grep -A 5 "nvidia.com/gpu"
done

# Check key pods
oc get pods -n openshift-gitops
oc get pods -n redhat-ods-applications
oc get pods -n nvidia-gpu-operator

# Check routes
oc get route -n openshift-gitops
oc get route -n redhat-ods-applications
```

### Comprehensive Validation Script

Location: `stage0-ai-platform-rhoai/validate.sh`

Run:
```bash
cd stage0-ai-platform-rhoai
./validate.sh
```

Checks:
1. NFD Operator status
2. GPU Operator status
3. GPU MachineSets and Machines
4. GPU Nodes and GPU resources
5. OpenShift AI Operator version
6. DataScienceCluster status and component readiness
7. Model Registry deployment
8. Model Registry route accessibility
9. Scoring summary (Pass/Warn/Fail)

---

## Red Hat Documentation References

### Primary Documentation

1. **Red Hat OpenShift AI 2.25 - Main Documentation**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25

2. **Installing and Managing OpenShift AI**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/installing_and_managing_openshift_ai/index

3. **Serving Models**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/serving_models/index
   - KServe configuration
   - Model serving platforms
   - Inference endpoints

4. **Managing Model Registries**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/managing_model_registries/index
   - Creating model registries
   - Registering models
   - Model versioning

5. **Monitoring Data Science Models**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/monitoring_data_science_models/index
   - TrustyAI configuration
   - Model evaluation with LM-Eval
   - Metrics and observability

### OpenShift GitOps

6. **Red Hat OpenShift GitOps 1.18**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18

7. **Understanding OpenShift GitOps**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/understanding_openshift_gitops/index

8. **Installing GitOps**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/installing_gitops/index

9. **Managing Cluster Configuration**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/managing_cluster_configuration/index

10. **Argo CD Applications**  
    https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/argo_cd_applications/index

### Service Mesh & Serverless

11. **Red Hat OpenShift Service Mesh 2.6**  
    https://docs.redhat.com/en/documentation/openshift_service_mesh/2.6

12. **Installing Service Mesh**  
    https://docs.redhat.com/en/documentation/openshift_service_mesh/2.6/html/installing_service_mesh/index

13. **Red Hat OpenShift Serverless 1.36**  
    https://docs.redhat.com/en/documentation/red_hat_openshift_serverless/1.36

14. **Installing Serverless**  
    https://docs.redhat.com/en/documentation/red_hat_openshift_serverless/1.36/html/install/index

### GPU Support

15. **NVIDIA GPU Operator Documentation**  
    https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html

16. **OpenShift GPU Configuration**  
    https://docs.openshift.com/container-platform/4.19/architecture/nvidia-gpu-architecture-overview.html

17. **Node Feature Discovery**  
    https://docs.openshift.com/container-platform/4.19/hardware_enablement/psap-node-feature-discovery-operator.html

### Best Practices

18. **GitOps Best Practices**  
    https://developers.redhat.com/blog/2025/03/05/openshift-gitops-recommended-practices

19. **Git Workflows for GitOps**  
    https://developers.redhat.com/articles/2022/07/20/git-workflows-best-practices-gitops-deployments

### Community Resources

20. **Red Hat GitOps Catalog**  
    https://github.com/redhat-cop/gitops-catalog
    - Operator installation patterns
    - OpenShift AI examples

21. **Red Hat AI Services Examples**  
    https://github.com/rh-aiservices-bu
    - Reference implementations
    - Model registry examples
    - Llama Stack demos

22. **RHOAI MLOps Patterns**  
    https://github.com/rhoai-mlops
    - Deployment patterns
    - CI/CD examples

---

## Next Steps

### Immediate Actions (Complete)

✅ Platform deployed and validated  
✅ GPU nodes provisioned and ready  
✅ DataScienceCluster healthy  
✅ Argo CD accessible  
✅ OpenShift AI Dashboard accessible

### Stage 1: Model Serving with vLLM

**Purpose**: Deploy Mistral 24B models (quantized and full precision) using vLLM

**Key Components**:
- Download models to PVCs
- Deploy InferenceServices (KServe + vLLM)
- Run GuideLLM benchmarks
- Register models in Model Registry
- Create validation notebook

**GitOps**: Deploy via Argo CD Application

**Documentation**:
- `stage1-model-serving-with-vllm/README.md`
- `stage1-model-serving-with-vllm/deploy.sh`

### Stage 2: Model Alignment with RAG + Llama Stack

**Purpose**: Enhance models with private data using RAG

**Key Components**:
- Deploy Llama Stack distribution
- Deploy Milvus vector database
- Ingest documents via Tekton pipelines
- Create RAG-enabled notebooks
- Test retrieval-augmented generation

**GitOps**: Deploy via Argo CD Application

**Documentation**:
- `stage2-model-alignment-with-rag-llama-stack/README.md`
- `stage2-model-alignment-with-rag-llama-stack/deploy.sh`

### Stage 3: Model Monitoring with TrustyAI + OpenTelemetry

**Purpose**: Monitor model quality, bias, and performance

**Key Components**:
- Configure TrustyAI for LM-Eval
- Run model evaluations
- Deploy Grafana dashboards
- Monitor metrics via OpenTelemetry

**GitOps**: Deploy via Argo CD Application

**Documentation**:
- `stage3-model-monitoring-with-trustyai/README.md`
- `stage3-model-monitoring-with-trustyai/deploy.sh`

### Stage 4: Model Integration with MCP + Llama Stack

**Purpose**: Build agentic AI workflows with Model Context Protocol

**Key Components**:
- Deploy Quarkus agent application
- Configure MCP servers (Slack, Database, PostgreSQL)
- Integrate with Llama Stack for agent orchestration
- Test end-to-end business workflow

**GitOps**: Deploy via Argo CD Application

**Documentation**:
- `stage4-model-integration-with-mcp-llama-stack/README.md`
- `stage4-model-integration-with-mcp-llama-stack/deploy.sh`

---

## Appendix: Cluster-Specific Details

### Current Cluster

| Property | Value |
|----------|-------|
| **Name** | cluster-gmgrr |
| **Infrastructure ID** | cluster-gmgrr-j2lhd |
| **Domain** | cluster-gmgrr.gmgrr.sandbox5294.opentlc.com |
| **OpenShift Version** | 4.19.16 |
| **Kubernetes Version** | v1.32.9 |
| **Region** | us-east-2 (Ohio) |
| **Availability Zone** | us-east-2c |
| **Platform** | AWS |
| **Worker Nodes** | 3 (standard) + 2 (GPU) |

### GPU Nodes

| Node | Instance Type | GPUs | Purpose |
|------|---------------|------|---------|
| ip-10-0-94-132.us-east-2.compute.internal | g6.4xlarge | 1x NVIDIA L4 (24GB) | Mistral 24B Quantized |
| ip-10-0-101-197.us-east-2.compute.internal | g6.12xlarge | 4x NVIDIA L4 (96GB total) | Mistral 24B Full |

### Storage Classes

Default: `gp3-csi` (AWS EBS gp3)

### Network Configuration

- Security Groups: `cluster-gmgrr-j2lhd-node`, `cluster-gmgrr-j2lhd-lb`
- Subnet: `cluster-gmgrr-j2lhd-subnet-private-us-east-2c`
- Ingress: OpenShift Router (HAProxy)
- Service Mesh Ingress: Istio Gateway

---

## Document Maintenance

**Last Updated**: October 24, 2025  
**Author**: AI Assistant (Claude Sonnet 4.5)  
**Review Status**: Initial version, awaiting production validation  
**Next Review**: After Stage 1 deployment

**Change Log**:
- 2025-10-24: Initial document created after successful Stage 0 deployment

---

**End of Document**

