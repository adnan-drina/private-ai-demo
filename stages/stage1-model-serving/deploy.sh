#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 1: Model Serving with vLLM - Deployment Script
#
# This script follows Red Hat OpenShift GitOps best practices for secure
# secret management:
#   1. Loads secrets from local .env file (git-ignored)
#   2. Creates Kubernetes Secrets imperatively
#   3. Deploys GitOps manifests (which reference secrets by name only)
#
# Deploys:
#   - Namespace
#   - Secrets (HuggingFace token, MinIO credentials)
#   - vLLM InferenceServices (2 Mistral models)
#   - Model download jobs with PVCs
#   - MinIO object storage
#   - GuideLLM benchmark jobs
#   - Jupyter workbench with benchmark notebooks
#   - Model Registry integration
#
# Prerequisites:
#   - Stage 0 (AI Platform) must be deployed and healthy
#   - OpenShift CLI (oc) authenticated to cluster
#   - .env file with secrets (copy from env.template)
#
# Usage:
#   ./deploy.sh [--skip-secrets] [--dry-run]
#
# Options:
#   --skip-secrets  Skip secret creation (if already exist)
#   --dry-run       Show what would be deployed without applying
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GITOPS_PATH="$PROJECT_ROOT/gitops/stage01-model-serving"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SKIP_SECRETS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-secrets)
      SKIP_SECRETS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      echo "Usage: $0 [--skip-secrets] [--dry-run]"
      exit 1
      ;;
  esac
done

# ============================================================================
# Functions
# ============================================================================

log_header() {
  echo ""
  echo "════════════════════════════════════════════════════════════════════════"
  echo "  $1"
  echo "════════════════════════════════════════════════════════════════════════"
  echo ""
}

log_section() {
  echo ""
  echo -e "${BLUE}▶ $1${NC}"
  echo "────────────────────────────────────────────────────────────────────────"
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

log_info() {
  echo -e "   $1"
}

check_prerequisites() {
  log_section "Checking Prerequisites"
  
  # Check oc CLI
  if ! command -v oc &> /dev/null; then
    log_error "OpenShift CLI (oc) is not installed"
    log_info "Install from: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
    exit 1
  fi
  log_success "OpenShift CLI found: $(oc version --client | head -1)"
  
  # Check cluster connection
  if ! oc whoami &> /dev/null; then
    log_error "Not logged in to OpenShift cluster"
    log_info "Run: oc login <cluster-url>"
    exit 1
  fi
  log_success "Connected to cluster: $(oc whoami --show-server)"
  log_info "Logged in as: $(oc whoami)"
  
  # Check GitOps path
  if [ ! -d "$GITOPS_PATH" ]; then
    log_error "GitOps path not found: $GITOPS_PATH"
    exit 1
  fi
  log_success "GitOps manifests found: $GITOPS_PATH"
  
  # Check .env file
  if [ ! -f "$ENV_FILE" ] && [ "$SKIP_SECRETS" = false ]; then
    log_error ".env file not found: $ENV_FILE"
    echo ""
    echo "Please create .env file from template:"
    echo "  cd $PROJECT_ROOT"
    echo "  cp env.template .env"
    echo "  # Edit .env and add your secrets"
    echo ""
    echo "Or skip secret creation if they already exist:"
    echo "  $0 --skip-secrets"
    exit 1
  fi
  
  if [ -f "$ENV_FILE" ]; then
    log_success ".env file found: $ENV_FILE"
  fi
  
  # Validate kustomize build
  log_info "Validating Kustomize build..."
  if ! oc kustomize "$GITOPS_PATH" > /dev/null; then
    log_error "Kustomize build failed for $GITOPS_PATH"
    exit 1
  fi
  log_success "Kustomize build validated"
}

load_env_file() {
  if [ "$SKIP_SECRETS" = true ]; then
    log_section "Skipping Secret Loading (--skip-secrets)"
    # Still need PROJECT_NAME
    PROJECT_NAME="${PROJECT_NAME:-private-ai-demo}"
    return
  fi
  
  log_section "Loading Environment Variables from .env"
  
  # Load .env file from project root
  set -a  # Automatically export all variables
  source "$ENV_FILE"
  set +a
  
  # Validate required secrets
  local missing_vars=()
  
  if [ -z "${HF_TOKEN:-}" ]; then
    missing_vars+=("HF_TOKEN")
  fi
  
  if [ -z "${MINIO_ACCESS_KEY:-}" ]; then
    missing_vars+=("MINIO_ACCESS_KEY")
  fi
  
  if [ -z "${MINIO_SECRET_KEY:-}" ]; then
    missing_vars+=("MINIO_SECRET_KEY")
  fi
  
  if [ ${#missing_vars[@]} -gt 0 ]; then
    log_error "Missing required variables in .env:"
    for var in "${missing_vars[@]}"; do
      log_info "$var"
    done
    echo ""
    echo "Please edit $ENV_FILE and set these variables"
    exit 1
  fi
  
  log_success "Environment variables loaded"
  log_info "PROJECT_NAME: ${PROJECT_NAME:-private-ai-demo}"
  log_info "HF_TOKEN: ${HF_TOKEN:0:10}... (${#HF_TOKEN} characters)"
  log_info "MINIO_ACCESS_KEY: ${MINIO_ACCESS_KEY}"
  log_info "MINIO_SECRET_KEY: ****** (${#MINIO_SECRET_KEY} characters)"
  
  # Set defaults
  PROJECT_NAME="${PROJECT_NAME:-private-ai-demo}"
}

create_namespace() {
  log_section "Creating Namespace"
  
  if oc get namespace "$PROJECT_NAME" &> /dev/null; then
    log_warning "Namespace already exists: $PROJECT_NAME"
  else
    if [ "$DRY_RUN" = true ]; then
      log_info "[DRY-RUN] Would create namespace: $PROJECT_NAME"
    else
      oc new-project "$PROJECT_NAME" || oc project "$PROJECT_NAME"
      log_success "Namespace created/selected: $PROJECT_NAME"
    fi
  fi
}

create_secrets() {
  if [ "$SKIP_SECRETS" = true ]; then
    log_section "Skipping Secret Creation (--skip-secrets)"
    return
  fi
  
  log_section "Creating Kubernetes Secrets"
  
  # HuggingFace token secret
  log_info "Creating HuggingFace token secret..."
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would create secret: huggingface-token"
  else
    oc create secret generic huggingface-token \
      --from-literal=HF_TOKEN="$HF_TOKEN" \
      -n "$PROJECT_NAME" \
      --dry-run=client -o yaml | oc apply -f -
    log_success "Secret created: huggingface-token"
  fi
  
  # MinIO credentials secret
  log_info "Creating MinIO credentials secret..."
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would create secret: minio-credentials"
  else
    oc create secret generic minio-credentials \
      --from-literal=accesskey="$MINIO_ACCESS_KEY" \
      --from-literal=secretkey="$MINIO_SECRET_KEY" \
      -n "$PROJECT_NAME" \
      --dry-run=client -o yaml | oc apply -f -
    log_success "Secret created: minio-credentials"
  fi
  
  log_success "All secrets created successfully"
  log_warning "Remember: Secrets are NOT in Git (managed imperatively)"
}

deploy_gitops_manifests() {
  log_section "Deploying GitOps Manifests"
  
  log_info "GitOps Path: $GITOPS_PATH"
  log_info "Components:"
  log_info "  • Namespace"
  log_info "  • vLLM InferenceServices (2 models)"
  log_info "  • Model download jobs + PVCs"
  log_info "  • MinIO deployment"
  log_info "  • GuideLLM benchmark jobs"
  log_info "  • Jupyter workbench + notebooks"
  
  if [ "$DRY_RUN" = true ]; then
    echo ""
    log_info "[DRY-RUN] Would apply:"
    oc kustomize "$GITOPS_PATH" | grep -E "^(apiVersion|kind|  name:)" | head -30
    echo "..."
  else
    echo ""
    oc apply -k "$GITOPS_PATH"
    log_success "GitOps manifests applied"
  fi
}

wait_for_models() {
  if [ "$DRY_RUN" = true ]; then
    return
  fi
  
  log_section "Waiting for Model Downloads"
  
  log_info "Model download jobs will run in background..."
  log_info "This may take 10-30 minutes depending on network speed"
  echo ""
  log_info "To monitor progress:"
  log_info "  oc get jobs -n $PROJECT_NAME"
  log_info "  oc logs -f job/download-mistral-24b-quantized -n $PROJECT_NAME"
  log_info "  oc logs -f job/download-mistral-24b-full -n $PROJECT_NAME"
  echo ""
  log_warning "⏳ Not waiting for completion - jobs running in background"
}

display_next_steps() {
  log_section "Deployment Summary"
  
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN MODE] No changes were made"
    echo ""
    log_info "Run without --dry-run to apply changes:"
    log_info "  $0"
    return
  fi
  
  log_success "Stage 1 deployment initiated!"
  
  echo ""
  echo "📊 Monitor Deployment:"
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  # Check all resources"
  echo "  oc get all -n $PROJECT_NAME"
  echo ""
  echo "  # Monitor model downloads"
  echo "  oc get jobs -n $PROJECT_NAME"
  echo "  oc logs -f job/download-mistral-24b-quantized -n $PROJECT_NAME"
  echo ""
  echo "  # Check InferenceServices"
  echo "  oc get inferenceservice -n $PROJECT_NAME"
  echo "  oc get isvc -n $PROJECT_NAME -w"
  echo ""
  echo "  # View model endpoints (once ready)"
  echo "  oc get routes -n $PROJECT_NAME"
  echo ""
  echo "  # Check workbench"
  echo "  oc get notebook -n $PROJECT_NAME"
  echo ""
  echo "🔍 Validation:"
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  cd $SCRIPT_DIR"
  echo "  ./validate.sh"
  echo ""
  echo "📝 Access Jupyter Notebook:"
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  1. Get workbench route:"
  echo "     oc get notebook -n $PROJECT_NAME"
  echo "  2. Open in browser (use OpenShift credentials)"
  echo "  3. Run: 01-benchmark.ipynb"
  echo ""
  echo "⏳ Expected Timeline:"
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  • Model downloads: 10-30 minutes (running in background)"
  echo "  • InferenceServices ready: 5-10 minutes after downloads complete"
  echo "  • Benchmarks: Run manually or automatically after models ready"
  echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

log_header "Stage 1: Model Serving with vLLM - Deployment"

# Pre-flight checks
check_prerequisites

# Load environment variables and secrets
load_env_file

# Create namespace
create_namespace

# Create secrets imperatively (not in GitOps)
create_secrets

# Deploy GitOps manifests
deploy_gitops_manifests

# Wait for model downloads (optional)
wait_for_models

# Display next steps
display_next_steps

log_success "Deployment script completed!"

exit 0
