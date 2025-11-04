#!/bin/bash
# KFP API Helpers - Idempotent pipeline upload and management
# 
# These functions provide programmatic access to KFP v2 (DSPA) API
# using OAuth authentication, making pipeline management fully reproducible.

# Common: resolve DSPA host + OAuth token
get_kfp_host_and_token() {
  KFP_HOST="https://$(oc -n private-ai-demo get route ds-pipeline-dspa -o jsonpath='{.spec.host}')"
  KFP_TOKEN="$(oc whoami -t)"
  : "${KFP_HOST:?missing DSPA route}"; : "${KFP_TOKEN:?oc auth missing}"
}

# Check if a pipeline by name exists; echo pipeline_id or empty
kfp_get_pipeline_id_by_name() {
  local name="$1"
  curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    "$KFP_HOST/apis/v2beta1/pipelines?page_size=100" \
    | jq -r --arg n "$name" '.pipelines[]? | select(.display_name==$n) | .pipeline_id' | head -1
}

# Upload a pipeline YAML; echo pipeline_id and pipeline_version_id
kfp_upload_pipeline() {
  local file="$1" name="$2"
  curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    -F "uploadfile=@${file}" \
    "$KFP_HOST/apis/v2beta1/pipelines/upload?name=$(printf %s "$name" | jq -s -R -r @uri)" \
    | tee /dev/stderr \
    | jq -r '[.pipeline_version?.pipeline_id, .pipeline_version?.pipeline_version_id] | @tsv'
}

# Ensure pipeline exists (create if missing); exports PIPELINE_ID, PIPELINE_VERSION_ID
ensure_pipeline_imported() {
  local file="${1:-artifacts/docling-rag-pipeline.yaml}" name="${2:-docling-rag-pipeline}"
  
  get_kfp_host_and_token
  
  local pid; pid="$(kfp_get_pipeline_id_by_name "$name" || true)"
  
  if [ -z "$pid" ]; then
    read PIPELINE_ID PIPELINE_VERSION_ID < <(kfp_upload_pipeline "$file" "$name")
    [ -n "$PIPELINE_ID" ] || { echo "❌ Upload failed"; return 1; }
    echo "✅ Uploaded pipeline '$name' (id=$PIPELINE_ID, version=$PIPELINE_VERSION_ID)"
  else
    PIPELINE_ID="$pid"
    # Always upload new version to keep pipeline in sync with source
    read _ PIPELINE_VERSION_ID < <(kfp_upload_pipeline "$file" "$name")
    echo "ℹ️  Pipeline exists (id=$PIPELINE_ID); new version=${PIPELINE_VERSION_ID:-skipped}"
  fi
  
  export PIPELINE_ID PIPELINE_VERSION_ID
}

# Create a pipeline run with parameters
kfp_create_run() {
  local run_name="$1"
  local pipeline_version_id="$2"
  local params_json="$3"
  
  get_kfp_host_and_token
  
  local run_request
  run_request=$(jq -n \
    --arg name "$run_name" \
    --arg pvid "$pipeline_version_id" \
    --argjson params "$params_json" \
    '{
      display_name: $name,
      pipeline_version_id: $pvid,
      runtime_config: {
        parameters: $params
      }
    }')
  
  curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$run_request" \
    "$KFP_HOST/apis/v2beta1/runs"
}
