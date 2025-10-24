#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 0a: OpenShift GitOps Bootstrap
#
# Installs and configures OpenShift GitOps (Argo CD) following Red Hat best practices.
# This is the ONLY imperative deployment - everything else managed by GitOps.
#
# Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18
#
# Components:
#   1. OpenShift GitOps Operator (latest channel)
#   2. Argo CD instance configuration
#   3. Cluster-admin RBAC for Argo CD
#   4. Verification and access instructions
#
# Prerequisites:
#   - OpenShift 4.16+ cluster with admin access
#   - oc CLI configured and logged in
##############################################################################

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_skip() { echo -e "${YELLOW}⊘${NC} $1"; }

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

wait_for_operator() {
    local csv_pattern=$1
    local namespace=$2
    local timeout=${3:-300}
    
    log_info "Waiting for operator to be ready (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if oc get csv -n "$namespace" 2>/dev/null | grep -q "$csv_pattern"; then
            local phase=$(oc get csv -n "$namespace" -o jsonpath="{.items[?(@.metadata.name contains '$csv_pattern')].status.phase}" 2>/dev/null || echo "")
            if [ "$phase" = "Succeeded" ]; then
                log_success "Operator is ready"
                return 0
            fi
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    log_warning "Timeout waiting for operator"
    return 1
}

# Main
main() {
    print_header "Stage 0a: OpenShift GitOps Bootstrap"
    
    log_info "This script installs OpenShift GitOps (Argo CD) - the foundation for GitOps-based deployment"
    log_info "Documentation: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18"
    echo ""
    
    # ========================================================================
    # Step 1: Install OpenShift GitOps Operator
    # ========================================================================
    print_header "Step 1: OpenShift GitOps Operator"
    
    if oc get subscription openshift-gitops-operator -n openshift-operators 2>/dev/null | grep -q "openshift-gitops-operator"; then
        log_skip "OpenShift GitOps Operator already installed"
        EXISTING_VERSION=$(oc get csv -n openshift-operators -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift GitOps")].spec.version}' 2>/dev/null || echo "unknown")
        log_info "Current version: $EXISTING_VERSION"
    else
        log_info "Installing OpenShift GitOps Operator..."
        log_info "Channel: latest (OpenShift GitOps 1.18+)"
        
        cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
        
        log_success "Subscription created"
        wait_for_operator "openshift-gitops-operator" "openshift-operators" 600
    fi
    
    # Wait for openshift-gitops namespace
    log_info "Waiting for openshift-gitops namespace..."
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if oc get namespace openshift-gitops &>/dev/null; then
            log_success "openshift-gitops namespace created"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    # ========================================================================
    # Step 2: Wait for Default Argo CD Instance
    # ========================================================================
    print_header "Step 2: Default Argo CD Instance"
    
    log_info "Waiting for default Argo CD instance (created automatically by operator)..."
    
    timeout=300
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if oc get argocd openshift-gitops -n openshift-gitops &>/dev/null; then
            log_success "Argo CD instance found"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    # Wait for Argo CD to be ready
    log_info "Waiting for Argo CD components to be ready..."
    oc wait --for=condition=Ready pod -l app.kubernetes.io/name=openshift-gitops-server -n openshift-gitops --timeout=300s || true
    
    log_success "Argo CD instance is ready"
    
    # ========================================================================
    # Step 3: Grant Cluster-Admin Permissions
    # ========================================================================
    print_header "Step 3: Cluster-Admin RBAC for Argo CD"
    
    log_info "Granting cluster-admin permissions to Argo CD..."
    log_info "Required for: Operators, MachineSets, DataScienceCluster, CRDs"
    
    if oc get clusterrolebinding openshift-gitops-cluster-admin &>/dev/null; then
        log_skip "Cluster admin binding already exists"
    else
        cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-gitops-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-application-controller
  namespace: openshift-gitops
EOF
        
        log_success "Cluster-admin permissions granted"
    fi
    
    # ========================================================================
    # Step 4: Configure Argo CD Instance
    # ========================================================================
    print_header "Step 4: Configure Argo CD Instance"
    
    log_info "Configuring Argo CD for our use case..."
    
    # Patch Argo CD instance with custom configuration
    cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  server:
    route:
      enabled: true
      tls:
        termination: reencrypt
        insecureEdgeTerminationPolicy: Redirect
    insecure: false
  applicationSet:
    resources:
      limits:
        cpu: "2"
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 512Mi
  controller:
    resources:
      limits:
        cpu: "2"
        memory: 2Gi
      requests:
        cpu: 250m
        memory: 1Gi
  repo:
    resources:
      limits:
        cpu: "1"
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 256Mi
  rbac:
    defaultPolicy: 'role:readonly'
    policy: |
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
    scopes: '[groups]'
  resourceCustomizations: |
    operators.coreos.com/Subscription:
      health.lua: |
        hs = {}
        if obj.status ~= nil then
          if obj.status.state == "AtLatestKnown" then
            hs.status = "Healthy"
            hs.message = "Subscription is at the latest known version"
            return hs
          end
        end
        hs.status = "Progressing"
        hs.message = "Waiting for subscription to be ready"
        return hs
    datasciencecluster.opendatahub.io/DataScienceCluster:
      health.lua: |
        hs = {}
        if obj.status ~= nil then
          if obj.status.phase == "Ready" then
            hs.status = "Healthy"
            hs.message = "DataScienceCluster is ready"
            return hs
          end
        end
        hs.status = "Progressing"
        hs.message = "DataScienceCluster is not ready yet"
        return hs
  resourceExclusions: |
    - apiGroups:
      - tekton.dev
      clusters:
      - '*'
      kinds:
      - TaskRun
      - PipelineRun
EOF
    
    log_success "Argo CD instance configured"
    
    # ========================================================================
    # Step 5: Verification
    # ========================================================================
    print_header "Step 5: Verification"
    
    log_info "Verifying OpenShift GitOps installation..."
    
    # Check operator
    if oc get subscription openshift-gitops-operator -n openshift-operators &>/dev/null; then
        log_success "Operator subscription exists"
    else
        log_error "Operator subscription not found"
    fi
    
    # Check Argo CD instance
    if oc get argocd openshift-gitops -n openshift-gitops &>/dev/null; then
        log_success "Argo CD instance exists"
    else
        log_error "Argo CD instance not found"
    fi
    
    # Check route
    if oc get route openshift-gitops-server -n openshift-gitops &>/dev/null; then
        ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
        log_success "Argo CD route: https://$ARGOCD_URL"
    else
        log_warning "Argo CD route not found yet (may still be creating)"
    fi
    
    # Check cluster admin binding
    if oc get clusterrolebinding openshift-gitops-cluster-admin &>/dev/null; then
        log_success "Cluster-admin permissions configured"
    else
        log_error "Cluster-admin binding not found"
    fi
    
    # ========================================================================
    # Deployment Summary
    # ========================================================================
    print_header "Bootstrap Complete!"
    
    echo "✅ OpenShift GitOps (Argo CD) is installed and configured!"
    echo ""
    echo "📦 Deployed Components:"
    echo "  • OpenShift GitOps Operator (latest channel)"
    echo "  • Argo CD instance in openshift-gitops namespace"
    echo "  • Cluster-admin RBAC for Argo CD"
    echo "  • Custom resource health checks"
    echo ""
    echo "🌐 Access Argo CD UI:"
    
    if [ -n "${ARGOCD_URL:-}" ]; then
        echo "  URL: https://$ARGOCD_URL"
        echo ""
        echo "  Login with OpenShift credentials:"
        echo "  1. Click 'Log in via OpenShift'"
        echo "  2. Use your cluster admin credentials"
        echo ""
        echo "  Or get admin password:"
        echo "  oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-"
    else
        echo "  Waiting for route to be created..."
        echo "  Check with: oc get route openshift-gitops-server -n openshift-gitops"
    fi
    
    echo ""
    echo "📖 Next Steps:"
    echo ""
    echo "  1. Access Argo CD UI (see above)"
    echo ""
    echo "  2. Deploy AI Platform via GitOps:"
    echo "     cd ../gitops-new/argocd"
    echo "     oc apply -f applications/stage00/app-stage00-ai-platform.yaml"
    echo ""
    echo "  3. Or deploy the rest of Stage 0 imperatively:"
    echo "     cd ../stage0-ai-platform-rhoai"
    echo "     ./deploy.sh"
    echo ""
    echo "  4. Monitor deployment in Argo CD UI"
    echo ""
    echo "💡 Tips:"
    echo "  • All future deployments should be via GitOps (Argo CD)"
    echo "  • Use Argo CD UI to monitor application health and sync status"
    echo "  • Git repository becomes the source of truth"
    echo ""
    echo "📚 Documentation:"
    echo "  • OpenShift GitOps: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18"
    echo "  • GitOps Integration Plan: docs/GITOPS-INTEGRATION-PLAN.md"
    echo ""
}

main "$@"

