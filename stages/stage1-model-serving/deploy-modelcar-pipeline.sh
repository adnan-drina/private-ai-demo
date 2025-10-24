#!/bin/bash
set -euo pipefail

##############################################################################
# ModelCar Pipeline Deployment Helper
#
# This script handles the deployment of the ModelCar pipeline components:
#   - ServiceAccount and RBAC for pipeline execution
#   - Tekton tasks and pipeline definitions
#   - ImageStreams for internal registry
#   - Pipeline workspace PVC
#   - Quay credentials
#   - Model Registry configuration
#   - PipelineRuns for both Mistral models
#
# This script is sourced by deploy.sh
##############################################################################

deploy_modelcar_pipeline() {
  log_header "MODEL CAR PIPELINE DEPLOYMENT"
  
  # ============================================================================
  # Step 1: Create Pipeline Secrets
  # ============================================================================
  
  log_section "Creating Pipeline Secrets"
  
  # Validate Quay credentials
  if [ -z "${QUAY_USERNAME:-}" ] || [ -z "${QUAY_PASSWORD:-}" ] || [ -z "${QUAY_ORGANIZATION:-}" ]; then
    log_warning "Quay credentials not found in .env"
    log_warning "Skipping Quay mirror and Model Registry steps"
    log_info "To enable full pipeline, add to .env:"
    log_info "  QUAY_USERNAME=your-username"
    log_info "  QUAY_PASSWORD=your-password"
    log_info "  QUAY_ORGANIZATION=your-org"
    SKIP_QUAY=true
  else
    log_info "Creating Quay push credentials..."
    if [ "$DRY_RUN" = true ]; then
      log_info "[DRY-RUN] Would create secret: quay-push"
    else
      oc create secret generic quay-push \
        --from-literal=QUAY_USERNAME="$QUAY_USERNAME" \
        --from-literal=QUAY_PASSWORD="$QUAY_PASSWORD" \
        -n "$PROJECT_NAME" \
        --dry-run=client -o yaml | oc apply -f -
      log_success "Secret created: quay-push"
    fi
    SKIP_QUAY=false
  fi
  
  # Get Model Registry URL
  log_info "Configuring Model Registry connection..."
  if [ "$DRY_RUN" = false ]; then
    # Try to get Model Registry route
    MR_ROUTE=$(oc get route model-registry-service \
      -n rhoai-model-registries \
      -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    if [ -n "$MR_ROUTE" ]; then
      MODEL_REGISTRY_URL="https://${MR_ROUTE}/api/model_registry/v1alpha3"
      log_success "Found Model Registry: $MODEL_REGISTRY_URL"
      
      oc create secret generic model-registry-config \
        --from-literal=MR_BASE_URL="$MODEL_REGISTRY_URL" \
        -n "$PROJECT_NAME" \
        --dry-run=client -o yaml | oc apply -f -
      log_success "Secret created: model-registry-config"
    else
      log_warning "Model Registry route not found, will skip registration step"
    fi
  else
    log_info "[DRY-RUN] Would configure Model Registry URL"
  fi
  
  # ============================================================================
  # Step 2: Deploy Pipeline Infrastructure
  # ============================================================================
  
  log_section "Deploying Pipeline Infrastructure"
  
  # Deploy ImageStreams
  log_info "Deploying ImageStreams..."
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would deploy ImageStreams"
  else
    oc apply -k "$GITOPS_PATH/imagestreams"
    log_success "ImageStreams deployed"
  fi
  
  # Deploy workspace PVC
  log_info "Deploying pipeline workspace PVC..."
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would deploy PVC: pipeline-workspace"
  else
    oc apply -k "$GITOPS_PATH/workspaces"
    log_success "Pipeline workspace PVC deployed"
  fi
  
  # Deploy pipeline components (SA, RBAC, Tasks, Pipeline)
  log_info "Deploying pipeline components..."
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would deploy pipeline components"
  else
    oc apply -k "$GITOPS_PATH/pipelines"
    log_success "Pipeline components deployed"
  fi
  
  # ============================================================================
  # Step 3: Grant Additional RBAC Permissions
  # ============================================================================
  
  log_section "Configuring Pipeline RBAC"
  
  if [ "$DRY_RUN" = false ]; then
    # Grant registry editor role
    log_info "Granting registry-editor role..."
    oc policy add-role-to-user registry-editor \
      -z model-pipeline-sa \
      -n "$PROJECT_NAME" 2>/dev/null || true
    
    # Grant image pusher role
    log_info "Granting system:image-pusher role..."
    oc policy add-role-to-user system:image-pusher \
      -z model-pipeline-sa \
      -n "$PROJECT_NAME" 2>/dev/null || true
    
    log_success "Pipeline RBAC configured"
  else
    log_info "[DRY-RUN] Would configure pipeline RBAC"
  fi
  
  # ============================================================================
  # Step 4: Display Pipeline Information
  # ============================================================================
  
  log_section "Pipeline Deployment Summary"
  
  if [ "$DRY_RUN" = false ]; then
    log_success "ModelCar Pipeline infrastructure deployed successfully!"
    echo ""
    log_info "Deployed components:"
    log_info "  • ServiceAccount: model-pipeline-sa"
    log_info "  • ClusterTask: kaniko-build-modelcar"
    log_info "  • Tasks: prepare-modelcar-context, mirror-to-quay, register-model, deploy-vllm"
    log_info "  • Pipeline: modelcar-build-deploy"
    log_info "  • ImageStreams: mistral-24b-quantized, mistral-24b-full"
    log_info "  • PVC: pipeline-workspace (100Gi)"
    echo ""
    log_info "To run the pipeline for Mistral quantized model:"
    echo '  oc create -f gitops/stage01-model-serving/pipelines/03-runs/pipelinerun-mistral-quantized.yaml'
    echo ""
    log_info "To run the pipeline for Mistral full model:"
    echo '  oc create -f gitops/stage01-model-serving/pipelines/03-runs/pipelinerun-mistral-full.yaml'
    echo ""
    log_info "Monitor pipeline runs:"
    echo '  oc get pipelineruns -n private-ai-demo -w'
    echo ""
    log_info "View pipeline logs:"
    echo '  tkn pipelinerun logs <pipelinerun-name> -n private-ai-demo -f'
  else
    log_info "[DRY-RUN] Would complete ModelCar pipeline deployment"
  fi
}

# ============================================================================
# Optional: Run Pipeline Automatically
# ============================================================================

run_modelcar_pipelines() {
  log_header "RUNNING MODELCAR PIPELINES"
  
  if [ "$SKIP_QUAY" = true ]; then
    log_warning "Quay credentials not configured, skipping pipeline execution"
    log_info "Configure Quay credentials in .env to enable pipeline runs"
    return
  fi
  
  log_section "Preparing PipelineRuns"
  
  # Update PipelineRun templates with actual Quay org
  QUANTIZED_PR="$GITOPS_PATH/pipelines/03-runs/pipelinerun-mistral-quantized.yaml"
  FULL_PR="$GITOPS_PATH/pipelines/03-runs/pipelinerun-mistral-full.yaml"
  
  # Create temporary files with updated Quay org
  TEMP_QUANTIZED=$(mktemp)
  TEMP_FULL=$(mktemp)
  
  sed "s/QUAY_ORG_PLACEHOLDER/${QUAY_ORGANIZATION}/g" "$QUANTIZED_PR" > "$TEMP_QUANTIZED"
  sed "s/QUAY_ORG_PLACEHOLDER/${QUAY_ORGANIZATION}/g" "$FULL_PR" > "$TEMP_FULL"
  
  log_info "PipelineRuns prepared with Quay organization: $QUAY_ORGANIZATION"
  
  # Ask user which pipeline to run
  echo ""
  echo "Which pipeline would you like to run?"
  echo "  1) Mistral 24B Quantized (w4a16) - ~20GB, 1 GPU, ~30 min"
  echo "  2) Mistral 24B Full Precision - ~50GB, 4 GPUs, ~60 min"
  echo "  3) Both (sequential)"
  echo "  4) Skip pipeline execution (deploy infrastructure only)"
  echo ""
  read -p "Enter choice (1-4): " choice
  
  case $choice in
    1)
      log_section "Running Mistral Quantized Pipeline"
      if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create quantized model PipelineRun"
      else
        oc create -f "$TEMP_QUANTIZED"
        log_success "Quantized model pipeline started"
        log_info "Monitor with: tkn pr logs -f -L -n private-ai-demo"
      fi
      ;;
    2)
      log_section "Running Mistral Full Precision Pipeline"
      if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create full model PipelineRun"
      else
        oc create -f "$TEMP_FULL"
        log_success "Full model pipeline started"
        log_info "Monitor with: tkn pr logs -f -L -n private-ai-demo"
      fi
      ;;
    3)
      log_section "Running Both Pipelines (Sequential)"
      if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create both PipelineRuns"
      else
        log_info "Starting quantized model pipeline..."
        oc create -f "$TEMP_QUANTIZED"
        log_success "Quantized model pipeline started"
        
        log_info "Starting full model pipeline..."
        oc create -f "$TEMP_FULL"
        log_success "Full model pipeline started"
        
        log_info "Monitor all pipelines: tkn pr list -n private-ai-demo"
      fi
      ;;
    4)
      log_info "Skipping pipeline execution"
      ;;
    *)
      log_warning "Invalid choice, skipping pipeline execution"
      ;;
  esac
  
  # Cleanup temp files
  rm -f "$TEMP_QUANTIZED" "$TEMP_FULL"
}

