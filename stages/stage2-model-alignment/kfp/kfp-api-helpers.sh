#!/bin/bash
# KFP API Helpers - Idempotent pipeline upload and management
# 
# These functions provide programmatic access to KFP v2 (DSPA) API
# using OAuth authentication, making pipeline management fully reproducible.
#
# Fixed to properly handle pipeline versions per Red Hat best practices:
# - If pipeline doesn't exist: use pipelines/upload (creates pipeline + first version)
# - If pipeline exists: use pipeline_versions/upload (creates new version)
# - Always tie runs to pipeline_version_id

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

# Upload a NEW pipeline (creates pipeline + first version)
# Returns: pipeline_id pipeline_version_id
kfp_upload_pipeline() {
  local file="$1" name="$2"
  local response
  response=$(curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    -F "uploadfile=@${file};filename=${name}.yaml;type=application/x-yaml" \
    "$KFP_HOST/apis/v2beta1/pipelines/upload?name=$(printf %s "$name" | jq -s -R -r @uri)")
  
  local pid vid
  pid=$(echo "$response" | jq -r '.pipeline_id // empty')
  vid=$(echo "$response" | jq -r '.default_version.pipeline_version_id // empty')
  
  echo "$pid $vid"
}

# Upload a new VERSION to an existing pipeline
# Returns: pipeline_version_id
kfp_upload_pipeline_version() {
  local file="$1" pipeline_id="$2" version_name="$3"
  local response
  response=$(curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    -F "uploadfile=@${file};filename=pipeline.yaml;type=application/x-yaml" \
    "$KFP_HOST/apis/v2beta1/pipeline_versions/upload?pipeline_id=$pipeline_id&name=$(printf %s "$version_name" | jq -s -R -r @uri)")
  
  echo "$response" | jq -r '.pipeline_version_id // empty'
}

# Ensure pipeline exists (create if missing); exports PIPELINE_ID, PIPELINE_VERSION_ID
# Always uploads a new version to keep pipeline in sync with source
ensure_pipeline_imported() {
  local file="${1:-artifacts/docling-rag-pipeline.yaml}" 
  local name="${2:-docling-rag-pipeline}"
  local version_name="${3:-$(date +%Y%m%d-%H%M%S)}"
  
  get_kfp_host_and_token
  
  local pid; pid="$(kfp_get_pipeline_id_by_name "$name" || true)"
  
  if [ -z "$pid" ]; then
    # Pipeline doesn't exist - create it
    read PIPELINE_ID PIPELINE_VERSION_ID < <(kfp_upload_pipeline "$file" "$name")
    [ -n "$PIPELINE_ID" ] || { echo "❌ Upload failed"; return 1; }
    echo "✅ Created pipeline '$name' (id=$PIPELINE_ID, version=$PIPELINE_VERSION_ID)"
  else
    # Pipeline exists - upload new version
    PIPELINE_ID="$pid"
    PIPELINE_VERSION_ID="$(kfp_upload_pipeline_version "$file" "$PIPELINE_ID" "$version_name")"
    [ -n "$PIPELINE_VERSION_ID" ] || { echo "❌ Version upload failed"; return 1; }
    echo "✅ Uploaded version '$version_name' to pipeline '$name' (id=$PIPELINE_ID, version=$PIPELINE_VERSION_ID)"
  fi
  
  export PIPELINE_ID PIPELINE_VERSION_ID
}

# Create a pipeline run tied to a specific version
kfp_create_run() {
  local run_name="$1"
  local pipeline_version_id="$2"
  local params_json="$3"
  
  get_kfp_host_and_token
  
  [ -n "$pipeline_version_id" ] || { echo "❌ pipeline_version_id required"; return 1; }
  
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
