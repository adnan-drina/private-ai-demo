#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 0: AI Platform - RHOAI 2.25 Deployment
#
# Deploys OpenShift AI 2.25 following official Red Hat documentation:
# https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25
#
# Components (with intelligent checks):
#   1. Node Feature Discovery Operator (if not present)
#   2. NVIDIA GPU Operator (if not present)
#   3. GPU MachineSets (g6.4xlarge, g6.12xlarge)
#   4. Red Hat OpenShift AI Operator 2.25 (if not present)
#   5. DataScienceCluster with Model Registry enabled
#   6. Model Registry verification
#
# Prerequisites:
#   - OpenShift 4.16+ cluster with admin access
#   - AWS cloud provider (for GPU nodes)
#   - oc CLI configured and logged in
##############################################################################

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_skip() { echo -e "${YELLOW}⊘${NC} $1"; }

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

wait_for_operator() {
    local csv_name=$1
    local namespace=$2
    local timeout=${3:-300}
    
    log_info "Waiting for operator $csv_name to be ready (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if oc get csv -n "$namespace" 2>/dev/null | grep -q "$csv_name"; then
            local phase=$(oc get csv -n "$namespace" -o jsonpath="{.items[?(@.metadata.name=='$csv_name')].status.phase}" 2>/dev/null || echo "")
            if [ "$phase" = "Succeeded" ]; then
                log_success "Operator $csv_name is ready"
                return 0
            fi
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    log_warning "Timeout waiting for operator $csv_name"
    return 1
}

# Main deployment
main() {
    print_header "Stage 0: AI Platform - RHOAI 2.25 Deployment"
    
    log_info "Starting deployment following Red Hat OpenShift AI 2.25 documentation"
    log_info "Documentation: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25"
    echo ""
    
    # ========================================================================
    # Step 1: Node Feature Discovery Operator
    # ========================================================================
    print_header "Step 1: Node Feature Discovery Operator"
    
    if oc get subscription nfd -n openshift-nfd 2>/dev/null | grep -q "nfd"; then
        log_skip "Node Feature Discovery Operator already installed"
    else
        log_info "Installing Node Feature Discovery Operator..."
        
        # Create namespace
        oc create namespace openshift-nfd 2>/dev/null || true
        
        # Create operator group
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
        
        # Create subscription
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
        
        wait_for_operator "nfd" "openshift-nfd"
        log_success "Node Feature Discovery Operator installed"
    fi
    
    # ========================================================================
    # Step 2: NVIDIA GPU Operator
    # ========================================================================
    print_header "Step 2: NVIDIA GPU Operator"
    
    if oc get subscription gpu-operator-certified -n nvidia-gpu-operator 2>/dev/null | grep -q "gpu-operator-certified"; then
        log_skip "NVIDIA GPU Operator already installed"
    else
        log_info "Installing NVIDIA GPU Operator..."
        log_info "Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/working_with_accelerators/index"
        
        # Create namespace
        oc create namespace nvidia-gpu-operator 2>/dev/null || true
        
        # Create operator group
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
        
        # Create subscription
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
        
        wait_for_operator "gpu-operator-certified" "nvidia-gpu-operator"
        log_success "NVIDIA GPU Operator installed"
    fi
    
    # ========================================================================
    # Step 3: GPU MachineSets
    # ========================================================================
    print_header "Step 3: GPU MachineSets"
    
    log_info "Checking for GPU MachineSets..."
    
    # Get cluster infrastructure details
    CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
    REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')
    AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')
    
    log_info "Cluster ID: $CLUSTER_ID"
    log_info "Region: $REGION"
    log_info "AMI ID: $AMI_ID"
    
    # Check for g6.4xlarge (1 GPU)
    if oc get machineset -n openshift-machine-api | grep -q "g6-4xlarge"; then
        log_skip "g6.4xlarge MachineSet already exists"
    else
        log_info "Creating g6.4xlarge MachineSet (1 GPU for quantized model)..."
        
        cat <<EOF | oc apply -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  name: ${CLUSTER_ID}-gpu-g6-4xlarge-${REGION}a
  namespace: openshift-machine-api
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-gpu-g6-4xlarge-${REGION}a
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-gpu-g6-4xlarge-${REGION}a
        node-role.kubernetes.io/gpu: ""
    spec:
      metadata:
        labels:
          nvidia.com/gpu.present: "true"
          node-role.kubernetes.io/gpu: ""
      taints:
      - effect: NoSchedule
        key: nvidia.com/gpu
        value: "true"
      providerSpec:
        value:
          ami:
            id: ${AMI_ID}
          apiVersion: machine.openshift.io/v1beta1
          blockDevices:
          - ebs:
              volumeSize: 120
              volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: g6.4xlarge
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ${REGION}a
            region: ${REGION}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-worker-sg
          subnet:
            filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-private-${REGION}a
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
        
        log_success "g6.4xlarge MachineSet created"
    fi
    
    # Check for g6.12xlarge (4 GPUs)
    if oc get machineset -n openshift-machine-api | grep -q "g6-12xlarge"; then
        log_skip "g6.12xlarge MachineSet already exists"
    else
        log_info "Creating g6.12xlarge MachineSet (4 GPUs for full precision model)..."
        
        cat <<EOF | oc apply -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  name: ${CLUSTER_ID}-gpu-g6-12xlarge-${REGION}a
  namespace: openshift-machine-api
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-gpu-g6-12xlarge-${REGION}a
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-gpu-g6-12xlarge-${REGION}a
        node-role.kubernetes.io/gpu: ""
    spec:
      metadata:
        labels:
          nvidia.com/gpu.present: "true"
          nvidia.com/gpu.count: "4"
          node-role.kubernetes.io/gpu: ""
      taints:
      - effect: NoSchedule
        key: nvidia.com/gpu
        value: "true"
      providerSpec:
        value:
          ami:
            id: ${AMI_ID}
          apiVersion: machine.openshift.io/v1beta1
          blockDevices:
          - ebs:
              volumeSize: 120
              volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: g6.12xlarge
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ${REGION}a
            region: ${REGION}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-worker-sg
          subnet:
            filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-private-${REGION}a
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
        
        log_success "g6.12xlarge MachineSet created"
    fi
    
    log_info "Waiting for GPU nodes to provision (this may take 10-15 minutes)..."
    log_info "Monitor with: watch -n 30 'oc get machines -n openshift-machine-api | grep gpu'"
    
    # ========================================================================
    # Step 4: Red Hat OpenShift AI Operator 2.25
    # ========================================================================
    print_header "Step 4: Red Hat OpenShift AI Operator 2.25"
    
    if oc get subscription rhods-operator -n redhat-ods-operator 2>/dev/null | grep -q "rhods-operator"; then
        log_skip "Red Hat OpenShift AI Operator already installed"
        EXISTING_VERSION=$(oc get csv -n redhat-ods-operator -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift AI")].spec.version}' 2>/dev/null || echo "unknown")
        log_info "Current version: $EXISTING_VERSION"
    else
        log_info "Installing Red Hat OpenShift AI Operator 2.25..."
        log_info "Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/installing_and_uninstalling_openshift_ai_self-managed/index"
        
        # Create namespace
        oc create namespace redhat-ods-operator 2>/dev/null || true
        
        # Create operator group
        cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec: {}
EOF
        
        # Create subscription
        cat <<EOF | oc apply -f -
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
        
        wait_for_operator "rhods-operator" "redhat-ods-operator" 600
        log_success "Red Hat OpenShift AI Operator 2.25 installed"
    fi
    
    # ========================================================================
    # Step 5: DataScienceCluster with Model Registry
    # ========================================================================
    print_header "Step 5: DataScienceCluster with Model Registry"
    
    if oc get datasciencecluster default-dsc 2>/dev/null | grep -q "default-dsc"; then
        log_skip "DataScienceCluster already exists"
        log_info "Current status: $(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo 'unknown')"
    else
        log_info "Creating DataScienceCluster with Model Registry enabled..."
        log_info "Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html-single/enabling_the_model_registry_component/index"
        
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
        
        log_success "DataScienceCluster created"
        log_info "Waiting for DataScienceCluster to be ready (this may take 5-10 minutes)..."
        
        # Wait for DSC to be ready
        local timeout=600
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            local phase=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$phase" = "Ready" ]; then
                log_success "DataScienceCluster is ready"
                break
            fi
            sleep 15
            elapsed=$((elapsed + 15))
            log_info "Waiting... (${elapsed}s/${timeout}s) Current phase: $phase"
        done
    fi
    
    # ========================================================================
    # Step 6: Verify Model Registry
    # ========================================================================
    print_header "Step 6: Model Registry Verification"
    
    log_info "Checking Model Registry deployment..."
    
    if oc get project rhoai-model-registries 2>/dev/null | grep -q "rhoai-model-registries"; then
        log_success "Model Registry namespace exists"
        
        # Check for Model Registry deployment
        if oc get deployment -n rhoai-model-registries 2>/dev/null | grep -q "model-registry"; then
            log_success "Model Registry deployment found"
            
            # Check route
            if oc get route -n rhoai-model-registries 2>/dev/null | grep -q "model-registry"; then
                REGISTRY_URL=$(oc get route -n rhoai-model-registries -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "not-found")
                log_success "Model Registry route: https://$REGISTRY_URL"
            else
                log_warning "Model Registry route not found"
            fi
        else
            log_warning "Model Registry deployment not found yet (may still be initializing)"
        fi
    else
        log_warning "Model Registry namespace not created yet (DataScienceCluster may still be initializing)"
    fi
    
    # ========================================================================
    # Deployment Summary
    # ========================================================================
    print_header "Deployment Summary"
    
    echo "✅ Stage 0 deployment complete!"
    echo ""
    echo "📦 Deployed Components:"
    echo "  • Node Feature Discovery Operator"
    echo "  • NVIDIA GPU Operator"
    echo "  • GPU MachineSets (g6.4xlarge, g6.12xlarge)"
    echo "  • Red Hat OpenShift AI Operator 2.25"
    echo "  • DataScienceCluster with Model Registry"
    echo ""
    echo "⏳ Post-Deployment Tasks:"
    echo "  1. Wait for GPU nodes to be ready (10-15 minutes)"
    echo "     Monitor: oc get machines -n openshift-machine-api | grep gpu"
    echo ""
    echo "  2. Verify GPU nodes are ready:"
    echo "     oc get nodes -l nvidia.com/gpu.present=true"
    echo ""
    echo "  3. Run validation:"
    echo "     ./validate.sh"
    echo ""
    echo "  4. Access OpenShift AI dashboard:"
    echo "     oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'"
    echo ""
    echo "📖 Next Steps:"
    echo "  • Once GPU nodes are ready, proceed to Stage 1: Model Serving"
    echo "  • cd ../stage1-model-serving-with-vllm"
    echo ""
}

main "$@"
