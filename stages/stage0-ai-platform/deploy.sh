#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 0: AI Platform - GitOps helper
#
# This script keeps GitOps as the single source of truth. It only
#   1. loads secrets from .env,
#   2. creates/updates the MinIO credential secret,
#   3. optionally triggers ArgoCD syncs for Stage 00 applications.
#
# All infrastructure resources must be defined in gitops/stage00-ai-platform.
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

APPS_STAGE00=(
  stage00-operators
  stage00-gpu-infrastructure
  stage00-datasciencecluster
  stage00-minio
)

# Colour palette
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

print_header() {
    echo ""
  echo "══════════════════════════════════════════════════════════════"
    echo "  $1"
  echo "══════════════════════════════════════════════════════════════"
    echo ""
}

check_prerequisites() {
  print_header "Pre-flight Checks"

  if ! command -v oc >/dev/null 2>&1; then
    log_warning "OpenShift CLI (oc) not found on PATH. Install it before continuing."
    exit 1
  fi
  log_success "oc CLI detected: $(oc version --client | head -1)"

  if ! oc whoami >/dev/null 2>&1; then
    log_warning "Not logged into OpenShift. Run 'oc login …' first."
    exit 1
  fi
  log_success "Connected to cluster: $(oc whoami --show-server)"
  log_info "Logged in as: $(oc whoami)"
}

load_env_file() {
  print_header "Loading .env"

  if [ ! -f "$ENV_FILE" ]; then
    log_warning "No .env file found at $ENV_FILE. Secrets will not be created."
    return 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  if [ -z "${MINIO_ACCESS_KEY:-}" ] || [ -z "${MINIO_SECRET_KEY:-}" ]; then
    log_warning "MINIO_ACCESS_KEY or MINIO_SECRET_KEY missing in .env; skipping secret creation."
    return 1
  fi

  log_success ".env loaded successfully"
  return 0
}

ensure_minio_secret() {
  print_header "Ensuring MinIO Secret"

  if [ -z "${MINIO_ACCESS_KEY:-}" ] || [ -z "${MINIO_SECRET_KEY:-}" ]; then
    log_warning "Skipping secret creation because credentials are unavailable."
    return
  fi

  oc create secret generic minio-credentials \
    --from-literal=accesskey="$MINIO_ACCESS_KEY" \
    --from-literal=secretkey="$MINIO_SECRET_KEY" \
    -n model-storage \
    --dry-run=client -o yaml | oc apply -f -

  log_success "Secret 'minio-credentials' ensured in namespace model-storage"
}

trigger_argocd_syncs() {
  print_header "Triggering ArgoCD Syncs"

  if [ "${DRY_RUN:-false}" = true ]; then
    log_info "[DRY-RUN] Would run: argocd app sync ${APPS_STAGE00[*]} --prune"
    return
  fi

  if ! command -v argocd >/dev/null 2>&1; then
    log_warning "argocd CLI not available. Use the ArgoCD UI or install the CLI to sync apps."
    return
  fi

  for app in "${APPS_STAGE00[@]}"; do
    log_info "Syncing $app"
    tmp_log=$(mktemp "sync-${app}.XXXX")
    if argocd app sync "$app" --prune >"$tmp_log" 2>&1; then
      log_success "$app sync requested"
    else
      log_warning "Failed to sync $app. Last log lines:"
      tail -n 5 "$tmp_log"
    fi
    rm -f "$tmp_log"
  done

  log_info "Verify progress with: oc get applications.argoproj.io -n openshift-gitops"
}

main() {
  DRY_RUN=false
  for arg in "$@"; do
    case $arg in
      --dry-run)
        DRY_RUN=true
        ;;
      *)
        log_warning "Unknown option: $arg"
        exit 1
        ;;
    esac
  done

  check_prerequisites
  load_env_file || true
  ensure_minio_secret
  trigger_argocd_syncs

  print_header "Summary"
  log_success "Stage 00 helper completed"
  log_info "Secrets stay out of Git; infrastructure remains GitOps-managed."
}

main "$@"

