#!/bin/bash

#============================================================================
# Stage 3: ACME LithoOps Calibration Agent - Production Deployment
# This script deploys PostgreSQL, MCP servers, and the ACME Agent
#
# Prerequisites:
#   - Stage 1 (vLLM with Mistral 24B) must be deployed
#   - OpenShift cluster with sufficient resources
#   - oc CLI logged in with appropriate permissions
#============================================================================

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ACME LithoOps Calibration Agent - Production Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GITOPS_DIR="${PROJECT_ROOT}/gitops"

# Load environment variables from .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "🔐 Loading configuration from .env file..."
    set -a
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$' | sed 's/\r$//')
    set +a
    echo "✅ Configuration loaded"
else
    echo "⚠️  No .env file found. Using defaults and environment variables."
    echo "   To configure secrets, copy env.template to .env and fill in your values:"
    echo "   cp env.template .env"
fi
echo ""

# Configuration (with defaults)
PROJECT_PRIVATE_AI="${PROJECT_PRIVATE_AI:-private-ai-demo}"
PROJECT_ACME_AGENT="${PROJECT_ACME_AGENT:-acme-calibration-ops}"
POSTGRES_DB="${POSTGRES_DB:-acme_equipment}"
POSTGRES_USER="${POSTGRES_USER:-acmeadmin}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-acme_secure_2025}"

# Global variables for dynamic URLs
VLLM_URL=""
VLLM_INTERNAL_URL=""

# --- Helper Functions ---

# Logging helpers
log_info() {
    echo "ℹ️  [$(date +%T)] $*"
}

log_success() {
    echo "✅ [$(date +%T)] $*"
}

log_error() {
    echo "❌ [$(date +%T)] $*" >&2
}

log_warn() {
    echo "⚠️  [$(date +%T)] $*"
}

# Function to check if namespace exists, create if not
ensure_namespace() {
    local ns=$1
    local description=${2:-"Stage 3 namespace"}
    
    if ! oc get namespace "$ns" &>/dev/null; then
        log_info "Creating namespace $ns..."
        oc new-project "$ns" --description="$description"
        log_success "Namespace $ns created"
    else
        log_success "Namespace $ns exists"
    fi
}

# Function to validate Stage 1 prerequisites
check_stage1_prerequisites() {
    echo ""
    echo "🔍 Step 1: Validating Stage 1 (vLLM) Prerequisites"
    echo "────────────────────────────────────────────────────────────"
    
    # Check namespace
    if ! oc get namespace "${PROJECT_PRIVATE_AI}" &>/dev/null; then
        log_error "Stage 1 not deployed: ${PROJECT_PRIVATE_AI} namespace not found"
        echo "   Please deploy Stage 1 first:"
        echo "   cd ../stage1-sovereign-ai && ./deploy.sh"
        exit 1
    fi
    log_success "Namespace ${PROJECT_PRIVATE_AI} exists"
    
    # Check vLLM InferenceService
    if ! oc get inferenceservice mistral-24b-quantized -n "${PROJECT_PRIVATE_AI}" &>/dev/null; then
        log_error "Stage 1 not deployed: mistral-24b-quantized InferenceService not found"
        echo "   Please deploy Stage 1 first:"
        echo "   cd ../stage1-sovereign-ai && ./deploy.sh"
        exit 1
    fi
    log_success "InferenceService mistral-24b-quantized exists"
    
    # Check Ready status
    local ready=$(oc get inferenceservice mistral-24b-quantized -n "${PROJECT_PRIVATE_AI}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$ready" != "True" ]; then
        log_error "vLLM not ready: mistral-24b-quantized status is $ready"
        echo "   Please wait for Stage 1 InferenceService to be Ready"
        exit 1
    fi
    log_success "InferenceService is Ready"
    
    # Fetch vLLM URL dynamically
    VLLM_URL=$(oc get inferenceservice mistral-24b-quantized -n "${PROJECT_PRIVATE_AI}" \
        -o jsonpath='{.status.url}' 2>/dev/null)
    VLLM_INTERNAL_URL="http://mistral-24b-quantized-predictor.${PROJECT_PRIVATE_AI}.svc.cluster.local/v1"
    
    log_success "vLLM external URL: $VLLM_URL"
    log_success "vLLM internal URL: $VLLM_INTERNAL_URL"
    
    echo "✅ Stage 1 prerequisites validated"
}

# Improved wait for deployment
wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=${3:-300}
    
    log_info "Waiting for deployment/$deployment in $namespace..."
    
    if ! oc wait --for=condition=available deployment/$deployment \
        -n $namespace --timeout=${timeout}s 2>&1; then
        log_error "Deployment $deployment failed to become ready"
        echo "Pod status:"
        oc get pods -l app=$deployment -n $namespace 2>/dev/null || true
        echo "Events:"
        oc get events -n $namespace --sort-by='.lastTimestamp' 2>/dev/null | grep $deployment | tail -10 || true
        return 1
    fi
    
    log_success "Deployment $deployment is ready"
}

# Wait for pod with label
wait_for_pod_ready() {
    local label=$1
    local namespace=$2
    local timeout=${3:-180}
    
    log_info "Waiting for pod with label $label in $namespace..."
    
    if ! oc wait --for=condition=Ready pod -l "$label" \
        -n $namespace --timeout=${timeout}s 2>&1; then
        log_error "Pod with label $label failed to become ready"
        oc get pods -l "$label" -n $namespace 2>/dev/null || true
        return 1
    fi
    
    log_success "Pod is ready"
}

# Wait for build completion
wait_for_build_complete() {
    local buildconfig=$1
    local namespace=$2
    local timeout=${3:-600}
    
    log_info "Waiting for build $buildconfig to complete..."
    
    # Get the latest build
    local build=$(oc get builds -l buildconfig=$buildconfig -n $namespace \
        --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
    
    if [ -z "$build" ]; then
        log_error "No build found for buildconfig $buildconfig"
        return 1
    fi
    
    log_info "Following build: $build"
    
    if ! oc wait --for=condition=Complete build/$build \
        -n $namespace --timeout=${timeout}s 2>&1; then
        log_error "Build $build failed"
        echo "Build logs (last 50 lines):"
        oc logs build/$build -n $namespace --tail=50 2>/dev/null || true
        return 1
    fi
    
    log_success "Build $build completed successfully"
}

# Deploy PostgreSQL
deploy_postgresql() {
    echo ""
    echo "📦 Step 2: Deploying PostgreSQL Database"
    echo "────────────────────────────────────────────────────────────"
    
    # Create secret from .env variables (remove hardcoded secret from manifest)
    log_info "Creating PostgreSQL credentials secret..."
    oc create secret generic postgresql-credentials \
        --from-literal=POSTGRES_DB="$POSTGRES_DB" \
        --from-literal=POSTGRES_USER="$POSTGRES_USER" \
        --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -n "${PROJECT_PRIVATE_AI}" \
        --dry-run=client -o yaml | oc apply -f -
    log_success "PostgreSQL credentials configured"
    
    # Deploy PostgreSQL (PVC, Deployment, Service)
    log_info "Applying PostgreSQL manifests..."
    oc apply -f "${SCRIPT_DIR}/gitops/database/postgresql-deployment.yaml" -n "${PROJECT_PRIVATE_AI}"
    
    # Wait for PostgreSQL to be ready
    wait_for_deployment postgresql "${PROJECT_PRIVATE_AI}" 120
    
    # Wait a bit for PostgreSQL to fully initialize
    sleep 5
    
    log_success "PostgreSQL deployed"
}

# Load database schema
load_database_schema() {
    echo ""
    echo "📊 Step 3: Loading Database Schema"
    echo "────────────────────────────────────────────────────────────"
    
    log_info "Waiting for PostgreSQL pod..."
    wait_for_pod_ready "app=postgresql" "${PROJECT_PRIVATE_AI}" 60
    
    local pod=$(oc get pod -l app=postgresql -n "${PROJECT_PRIVATE_AI}" -o jsonpath='{.items[0].metadata.name}')
    
    log_info "Loading schema into database..."
    if cat "${SCRIPT_DIR}/gitops/database/init-schema.sql" | oc exec -i -n "${PROJECT_PRIVATE_AI}" $pod -- \
        bash -c "PGPASSWORD=${POSTGRES_PASSWORD} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}" >/dev/null 2>&1; then
        log_success "Database schema loaded with equipment data"
    else
        log_warn "Schema load may have failed or already exists (this is OK if redeploying)"
    fi
    
    # Verify data
    log_info "Verifying database content..."
    local count=$(oc exec -n "${PROJECT_PRIVATE_AI}" $pod -- \
        bash -c "PGPASSWORD=${POSTGRES_PASSWORD} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -t -c 'SELECT COUNT(*) FROM equipment;'" 2>/dev/null | tr -d ' ')
    
    if [ "$count" -gt 0 ]; then
        log_success "Database contains $count equipment records"
    else
        log_error "Database verification failed: no equipment records found"
        return 1
    fi
}

# Deploy MCP servers
deploy_mcp_servers() {
    echo ""
    echo "🔧 Step 4: Deploying MCP Servers"
    echo "────────────────────────────────────────────────────────────"
    
    # Create BuildConfigs if they don't exist
    if ! oc get bc database-mcp -n "${PROJECT_PRIVATE_AI}" &>/dev/null; then
        log_info "Creating Database MCP BuildConfig..."
        oc new-build --name=database-mcp \
            --binary=true \
            --strategy=docker \
            -n "${PROJECT_PRIVATE_AI}"
    fi
    
    if ! oc get bc slack-mcp -n "${PROJECT_PRIVATE_AI}" &>/dev/null; then
        log_info "Creating Slack MCP BuildConfig..."
        oc new-build --name=slack-mcp \
            --binary=true \
            --strategy=docker \
            -n "${PROJECT_PRIVATE_AI}"
    fi
    
    # Build and deploy Database MCP
    log_info "Building Database MCP..."
    cd "${SCRIPT_DIR}/mcp-servers/database-mcp"
    oc start-build database-mcp --from-dir=. -n "${PROJECT_PRIVATE_AI}" --wait
    cd "${SCRIPT_DIR}"
    wait_for_build_complete database-mcp "${PROJECT_PRIVATE_AI}"
    
    log_info "Deploying Database MCP..."
    oc apply -f "${SCRIPT_DIR}/gitops/mcp-servers/database-mcp/deployment.yaml"
    oc apply -f "${SCRIPT_DIR}/gitops/mcp-servers/database-mcp/service.yaml"
    wait_for_deployment database-mcp "${PROJECT_PRIVATE_AI}" 120
    
    # Configure Slack webhook (optional)
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        log_info "Creating Slack webhook secret..."
        oc create secret generic slack-webhook \
            --from-literal=webhook-url="$SLACK_WEBHOOK_URL" \
            -n "${PROJECT_PRIVATE_AI}" \
            --dry-run=client -o yaml | oc apply -f -
        log_success "Slack webhook configured"
    else
        log_warn "SLACK_WEBHOOK_URL not set - Slack MCP will run in DEMO MODE (console logging)"
    fi
    
    # Build and deploy Slack MCP
    log_info "Building Slack MCP..."
    cd "${SCRIPT_DIR}/mcp-servers/slack-mcp"
    oc start-build slack-mcp --from-dir=. -n "${PROJECT_PRIVATE_AI}" --wait
    cd "${SCRIPT_DIR}"
    wait_for_build_complete slack-mcp "${PROJECT_PRIVATE_AI}"
    
    log_info "Deploying Slack MCP..."
    oc apply -f "${SCRIPT_DIR}/gitops/mcp-servers/slack-mcp/deployment.yaml"
    oc apply -f "${SCRIPT_DIR}/gitops/mcp-servers/slack-mcp/service.yaml"
    wait_for_deployment slack-mcp "${PROJECT_PRIVATE_AI}" 120
    
    log_success "MCP servers deployed"
}

# Test MCP servers
test_mcp_servers() {
    echo ""
    echo "🧪 Step 5: Testing MCP Servers"
    echo "────────────────────────────────────────────────────────────"
    
    # Test Database MCP
    log_info "Testing Database MCP..."
    local db_pod=$(oc get pod -l app=database-mcp -n "${PROJECT_PRIVATE_AI}" -o jsonpath='{.items[0].metadata.name}')
    if oc exec -n "${PROJECT_PRIVATE_AI}" $db_pod -- curl -sf http://localhost:8080/health &>/dev/null; then
        log_success "Database MCP healthy"
    else
        log_error "Database MCP health check failed"
        return 1
    fi
    
    # Test Slack MCP
    log_info "Testing Slack MCP..."
    local slack_pod=$(oc get pod -l app=slack-mcp -n "${PROJECT_PRIVATE_AI}" -o jsonpath='{.items[0].metadata.name}')
    if oc exec -n "${PROJECT_PRIVATE_AI}" $slack_pod -- curl -sf http://localhost:8080/health &>/dev/null; then
        log_success "Slack MCP healthy"
    else
        log_error "Slack MCP health check failed"
        return 1
    fi
    
    log_success "MCP servers validated"
}

# Deploy ACME Agent
deploy_acme_agent() {
    echo ""
    echo "🤖 Step 6: Deploying ACME Agent"
    echo "────────────────────────────────────────────────────────────"
    
    # Ensure ACME Agent namespace exists
    ensure_namespace "${PROJECT_ACME_AGENT}" "ACME LithoOps Calibration Agent"
    
    # Deploy RBAC
    log_info "Deploying RBAC..."
    oc apply -f "${SCRIPT_DIR}/acme-lithoops-agent/deploy/serviceaccount.yaml"
    oc apply -f "${SCRIPT_DIR}/acme-lithoops-agent/deploy/role.yaml" -n "${PROJECT_PRIVATE_AI}"
    oc apply -f "${SCRIPT_DIR}/acme-lithoops-agent/deploy/rolebinding.yaml"
    log_success "RBAC configured"
    
    # Create BuildConfig if it doesn't exist
    if ! oc get bc acme-agent -n "${PROJECT_ACME_AGENT}" &>/dev/null; then
        log_info "Creating ACME Agent BuildConfig..."
        oc new-build --name=acme-agent \
            --binary=true \
            --strategy=docker \
            -n "${PROJECT_ACME_AGENT}"
    fi
    
    # Build Quarkus application
    log_info "Building Quarkus application..."
    cd "${SCRIPT_DIR}/acme-lithoops-agent"
    mvn clean package -DskipTests -q || {
        log_error "Maven build failed"
        return 1
    }
    log_success "Quarkus application built"
    
    # Build container image
    log_info "Building ACME Agent container image..."
    oc start-build acme-agent --from-dir=. -n "${PROJECT_ACME_AGENT}" --wait
    cd "${SCRIPT_DIR}"
    wait_for_build_complete acme-agent "${PROJECT_ACME_AGENT}"
    
    # Deploy application
    log_info "Deploying ACME Agent..."
    oc apply -f "${SCRIPT_DIR}/acme-lithoops-agent/deploy/deployment.yaml"
    oc apply -f "${SCRIPT_DIR}/acme-lithoops-agent/deploy/service.yaml"
    oc apply -f "${SCRIPT_DIR}/acme-lithoops-agent/deploy/route.yaml"
    
    # Wait for deployment (Quarkus may take longer)
    log_info "Waiting for ACME Agent to be ready (this may take 60-90 seconds)..."
    sleep 15
    wait_for_deployment acme-agent "${PROJECT_ACME_AGENT}" 180
    
    log_success "ACME Agent deployed"
}

# Post-deployment validation
validate_deployment() {
    echo ""
    echo "✅ Step 7: Validating Deployment"
    echo "────────────────────────────────────────────────────────────"
    
    local all_ok=true
    
    # Check PostgreSQL
    log_info "Checking PostgreSQL..."
    local pg_pod=$(oc get pod -l app=postgresql -n "${PROJECT_PRIVATE_AI}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$pg_pod" ] && oc exec -n "${PROJECT_PRIVATE_AI}" $pg_pod -- \
        bash -c "PGPASSWORD=${POSTGRES_PASSWORD} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT 1;'" &>/dev/null; then
        log_success "PostgreSQL healthy"
    else
        log_error "PostgreSQL validation failed"
        all_ok=false
    fi
    
    # Check Database MCP
    log_info "Checking Database MCP..."
    local db_pod=$(oc get pod -l app=database-mcp -n "${PROJECT_PRIVATE_AI}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$db_pod" ] && oc exec -n "${PROJECT_PRIVATE_AI}" $db_pod -- curl -sf http://localhost:8080/health &>/dev/null; then
        log_success "Database MCP healthy"
    else
        log_error "Database MCP validation failed"
        all_ok=false
    fi
    
    # Check Slack MCP
    log_info "Checking Slack MCP..."
    local slack_pod=$(oc get pod -l app=slack-mcp -n "${PROJECT_PRIVATE_AI}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$slack_pod" ] && oc exec -n "${PROJECT_PRIVATE_AI}" $slack_pod -- curl -sf http://localhost:8080/health &>/dev/null; then
        log_success "Slack MCP healthy"
    else
        log_error "Slack MCP validation failed"
        all_ok=false
    fi
    
    # Check ACME Agent
    log_info "Checking ACME Agent..."
    local route=$(oc get route acme-agent -n "${PROJECT_ACME_AGENT}" -o jsonpath='{.spec.host}' 2>/dev/null)
    if [ -n "$route" ] && curl -skf https://$route/health &>/dev/null; then
        log_success "ACME Agent healthy"
    else
        log_warn "ACME Agent health check failed (may still be starting)"
        all_ok=false
    fi
    
    if [ "$all_ok" = true ]; then
        log_success "All components validated successfully"
        return 0
    else
        log_warn "Some validations failed - check components above"
        return 0  # Don't fail deployment, just warn
    fi
}

# Display deployment summary
show_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Deployment Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  • PostgreSQL Database: Running with equipment data"
    echo "  • Database MCP: Connected to PostgreSQL"
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        echo "  • Slack MCP: Connected to Slack (webhook configured)"
    else
        echo "  • Slack MCP: DEMO MODE (console logging - set SLACK_WEBHOOK_URL for real Slack)"
    fi
    echo "  • ACME Agent: Ready for calibration checks"
    echo "  • vLLM Integration: Using ${VLLM_INTERNAL_URL}"
    echo ""
    echo "🌐 Access URLs:"
    local route=$(oc get route acme-agent -n "${PROJECT_ACME_AGENT}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not created")
    echo "  • ACME Agent UI: https://$route"
    echo "  • API Endpoint: https://$route/api/v1/ops/calibration/check"
    echo ""
    echo "🧪 Quick Test:"
    echo "  curl -sk -X POST https://$route/api/v1/ops/calibration/check \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"equipmentId\":\"LITHO-001\",\"telemetryFile\":\"acme_telemetry_clean.csv\"}'"
    echo ""
    echo "📜 View Logs:"
    echo "  • ACME Agent: oc logs -f deployment/acme-agent -n ${PROJECT_ACME_AGENT}"
    echo "  • Database MCP: oc logs -f deployment/database-mcp -n ${PROJECT_PRIVATE_AI}"
    echo "  • Slack MCP: oc logs -f deployment/slack-mcp -n ${PROJECT_PRIVATE_AI}"
    echo "  • PostgreSQL: oc logs -f deployment/postgresql -n ${PROJECT_PRIVATE_AI}"
    echo ""
    echo "📚 Documentation:"
    echo "  • README: ${SCRIPT_DIR}/README.md"
    echo "  • Validation Guide: ${SCRIPT_DIR}/docs/VALIDATION-GUIDE.md"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# --- Main Execution ---

main() {
    # Validate prerequisites
    check_stage1_prerequisites
    
    # Ensure namespaces exist
    ensure_namespace "${PROJECT_PRIVATE_AI}" "Private AI Demo - Stage 1, 2, 3 backend services"
    ensure_namespace "${PROJECT_ACME_AGENT}" "ACME LithoOps Calibration Agent"
    
    # Deploy components
    deploy_postgresql
    load_database_schema
    deploy_mcp_servers
    test_mcp_servers
    deploy_acme_agent
    
    # Deploy Stage 3 demo notebook
    log_info "Deploying Stage 3 demo notebook..."
    if oc apply -f "${SCRIPT_DIR}/../gitops/components/workbench/configmap-notebook-05-stage3.yaml"; then
        log_success "Stage 3 notebook deployed"
        log_info "Notebook will be available in JupyterLab workbench as: 05-stage3-agent.ipynb"
        log_warn "Note: Restart the workbench pod to load the new notebook"
    else
        log_warn "Failed to deploy Stage 3 notebook (non-critical)"
    fi
    
    # Validate deployment
    validate_deployment
    
    # Show summary
    show_summary
    
    echo ""
    log_success "Stage 3 deployment completed successfully!"
}

# Run main function
main
