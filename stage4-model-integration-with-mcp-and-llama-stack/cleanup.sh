#!/bin/bash

#============================================================================
# Stage 3: ACME LithoOps Agent - Cleanup Script
# This script removes all Stage 3 resources while preserving Stage 1 & 2
#============================================================================

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Stage 3: ACME LithoOps Agent - Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Configuration ---
PROJECT_PRIVATE_AI="${PROJECT_PRIVATE_AI:-private-ai-demo}"
PROJECT_ACME_AGENT="${PROJECT_ACME_AGENT:-acme-calibration-ops}"

# --- Helper Functions ---

log_info() {
    echo "ℹ️  [$(date +%T)] $*"
}

log_success() {
    echo "✅ [$(date +%T)] $*"
}

log_warn() {
    echo "⚠️  [$(date +%T)] $*"
}

# Function to remove finalizers from a resource
remove_finalizers() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-$PROJECT_PRIVATE_AI}
    
    log_info "Removing finalizers from $resource_type/$resource_name in $namespace..."
    if oc get "$resource_type" "$resource_name" -n "$namespace" -o jsonpath='{.metadata.finalizers}' &> /dev/null; then
        oc patch "$resource_type" "$resource_name" -n "$namespace" \
            --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
        log_success "Finalizers removed from $resource_type/$resource_name"
    fi
}

# Function to force delete a namespace if stuck
force_namespace_deletion() {
    local ns_name=$1
    local timeout=${2:-300}  # 5 minutes
    local start_time=$(date +%s)
    
    log_info "Monitoring namespace $ns_name deletion..."
    
    while oc get namespace "$ns_name" &> /dev/null; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        
        if [ "$elapsed_time" -gt "$timeout" ]; then
            log_warn "Timeout ($timeout s) waiting for namespace $ns_name to terminate. Forcing deletion."
            
            # Remove finalizers from remaining resources
            log_info "Identifying and removing finalizers from resources in $ns_name..."
            
            # Force delete deployments
            for deploy in $(oc get deployment -n "$ns_name" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
                remove_finalizers "deployment" "$deploy" "$ns_name"
            done
            
            # Force delete pods
            for pod in $(oc get pod -n "$ns_name" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
                oc delete pod "$pod" -n "$ns_name" --force --grace-period=0 2>/dev/null || true
            done
            
            # Remove namespace finalizers
            log_info "Removing finalizers from namespace $ns_name..."
            oc get namespace "$ns_name" -o json | \
                jq 'del(.spec.finalizers[] | select(. == "kubernetes"))' | \
                oc replace --raw "/api/v1/namespaces/$ns_name/finalize" -f - 2>/dev/null || true
            
            log_success "Namespace $ns_name deletion forced"
            return 0
        fi
        
        log_info "Namespace $ns_name still terminating... (${elapsed_time}s / ${timeout}s)"
        sleep 10
    done
    
    log_success "Namespace $ns_name is gone"
}

# --- Main Cleanup Logic ---

main() {
    log_info "Starting Stage 3 cleanup..."
    echo ""
    
    # Step 1: Delete ACME Agent resources
    echo "🗑️  Step 1: Cleaning up ACME Agent"
    echo "────────────────────────────────────────────────────────────"
    
    if oc get namespace "$PROJECT_ACME_AGENT" &>/dev/null; then
        log_info "Deleting ACME Agent resources..."
        
        # Delete BuildConfig
        oc delete bc acme-agent -n "$PROJECT_ACME_AGENT" --ignore-not-found || true
        
        # Delete application resources
        oc delete route acme-agent -n "$PROJECT_ACME_AGENT" --ignore-not-found || true
        oc delete service acme-agent -n "$PROJECT_ACME_AGENT" --ignore-not-found || true
        oc delete deployment acme-agent -n "$PROJECT_ACME_AGENT" --ignore-not-found || true
        
        # Delete RBAC
        oc delete rolebinding acme-agent-rolebinding -n "$PROJECT_ACME_AGENT" --ignore-not-found || true
        oc delete role acme-agent-role -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
        oc delete serviceaccount acme-agent-sa -n "$PROJECT_ACME_AGENT" --ignore-not-found || true
        
        log_success "ACME Agent resources deleted"
        
        # Delete namespace
        log_info "Deleting namespace $PROJECT_ACME_AGENT..."
        oc delete namespace "$PROJECT_ACME_AGENT" --wait=false --ignore-not-found || true
        
        # Force deletion if stuck
        if oc get namespace "$PROJECT_ACME_AGENT" &>/dev/null; then
            force_namespace_deletion "$PROJECT_ACME_AGENT"
        fi
    else
        log_success "Namespace $PROJECT_ACME_AGENT does not exist, skipping"
    fi
    
    echo ""
    
    # Step 2: Delete MCP Servers
    echo "🗑️  Step 2: Cleaning up MCP Servers"
    echo "────────────────────────────────────────────────────────────"
    
    if oc get namespace "$PROJECT_PRIVATE_AI" &>/dev/null; then
        log_info "Deleting MCP server resources..."
        
        # Delete Slack MCP
        oc delete service slack-mcp -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
        oc delete deployment slack-mcp -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
        oc delete bc slack-mcp -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
        oc delete secret slack-webhook -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
        
        # Delete Database MCP
        oc delete service database-mcp -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
        oc delete deployment database-mcp -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
        oc delete bc database-mcp -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
        
        log_success "MCP servers deleted"
    else
        log_warn "Namespace $PROJECT_PRIVATE_AI does not exist"
    fi
    
    echo ""
    
    # Step 3: Delete PostgreSQL (optional - user choice)
    echo "🗑️  Step 3: Cleaning up PostgreSQL"
    echo "────────────────────────────────────────────────────────────"
    
    read -p "Delete PostgreSQL database? This will remove all equipment data. (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if oc get namespace "$PROJECT_PRIVATE_AI" &>/dev/null; then
            log_info "Deleting PostgreSQL resources..."
            
            oc delete service postgresql -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
            oc delete deployment postgresql -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
            oc delete pvc postgresql-data -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
            oc delete secret postgresql-credentials -n "$PROJECT_PRIVATE_AI" --ignore-not-found || true
            
            log_success "PostgreSQL deleted"
        fi
    else
        log_info "Keeping PostgreSQL for reuse"
    fi
    
    echo ""
    
    # Summary
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Cleanup Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📊 Cleanup Summary:"
    echo "  • ACME Agent namespace: $PROJECT_ACME_AGENT deleted"
    echo "  • MCP servers removed from $PROJECT_PRIVATE_AI"
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "  • PostgreSQL removed from $PROJECT_PRIVATE_AI"
    else
        echo "  • PostgreSQL kept in $PROJECT_PRIVATE_AI (for reuse)"
    fi
    echo ""
    echo "⚠️  Note: Stage 1 & 2 components in $PROJECT_PRIVATE_AI remain intact"
    echo ""
    echo "🔄 To redeploy Stage 3:"
    echo "  cd stage3-enterprise-mcp"
    echo "  ./deploy.sh"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run main function
main
