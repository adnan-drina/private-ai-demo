#!/bin/bash
# KFP API Helpers - Red Hat-aligned solution for DSPA
# 
# Uses v2beta1 APIs for pipeline/version management and v1beta1 for run creation
# to bypass the parameter validation bug in v2beta1 runs API.
#
# This approach is aligned with Red Hat guidance until the server-side
# type validation bug is fixed in newer DSPA versions.

# Common: resolve DSPA host + OAuth token
get_kfp_host_and_token() {
  KFP_HOST="https://$(oc -n private-ai-demo get route ds-pipeline-dspa -o jsonpath='{.spec.host}')"
  KFP_TOKEN="$(oc whoami -t)"
  KFP_BASE="$KFP_HOST/apis"
  : "${KFP_HOST:?missing DSPA route}"; : "${KFP_TOKEN:?oc auth missing}"
  export KFP_HOST KFP_TOKEN KFP_BASE
}

# Get or create experiment (v1beta1)
ensure_experiment() {
  local exp_name="${1:-rag-experiment}"
  local exp_desc="${2:-RAG ingestion pipeline runs}"
  
  get_kfp_host_and_token
  
  # Try to create experiment
  local response
  response=$(curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST "$KFP_BASE/v1beta1/experiments" \
    -d "{\"name\":\"$exp_name\",\"description\":\"$exp_desc\"}" 2>/dev/null)
  
  # If already exists, fetch it
  if echo "$response" | grep -q "already exists"; then
    response=$(curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
      "$KFP_BASE/v1beta1/experiments" 2>/dev/null)
    EXPERIMENT_ID=$(echo "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for exp in data.get('experiments', []):
        if exp['name'] == '$exp_name':
            print(exp['id'])
            break
except: pass
" 2>/dev/null)
  else
    EXPERIMENT_ID=$(echo "$response" | jq -r '.id' 2>/dev/null)
  fi
  
  export EXPERIMENT_ID
  echo "$EXPERIMENT_ID"
}

# Create pipeline (v2beta1)
create_pipeline() {
  local name="$1"
  
  get_kfp_host_and_token
  
  local response
  response=$(curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST "$KFP_BASE/v2beta1/pipelines" \
    -d "{\"display_name\":\"$name\"}" 2>/dev/null)
  
  echo "$response" | jq -r '.pipeline_id'
}

# Upload pipeline version (v2beta1)
upload_pipeline_version() {
  local file="$1" pipeline_id="$2" version_name="$3"
  
  get_kfp_host_and_token
  
  curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    -X POST "$KFP_BASE/v2beta1/pipeline_versions/upload?pipeline_id=$pipeline_id&name=$version_name" \
    -F "uploadfile=@${file};filename=pipeline.yaml;type=application/x-yaml" \
    2>/dev/null > /dev/null
  
  # Query for version ID
  sleep 2
  local versions
  versions=$(curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    "$KFP_BASE/v2beta1/pipelines/$pipeline_id/versions" 2>/dev/null)
  
  echo "$versions" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['pipeline_versions'][0]['pipeline_version_id'])
except: pass
" 2>/dev/null
}

# Create run (v1beta1) - Red Hat-aligned solution
# All parameters must be strings!
kfp_create_run_v1() {
  local run_name="$1"
  local experiment_id="$2"
  local pipeline_id="$3"
  local pipeline_version_id="$4"
  local params_json="$5"
  
  get_kfp_host_and_token
  
  # Convert simple params JSON to v1beta1 format (array of name/value pairs, all strings)
  local params_array
  params_array=$(echo "$params_json" | python3 -c "
import json, sys
params = json.load(sys.stdin)
result = []
for key, value in params.items():
    result.append({'name': key, 'value': str(value)})
print(json.dumps(result))
")
  
  # Build v1beta1 run request
  local run_request
  run_request=$(jq -n \
    --arg name "$run_name" \
    --arg exp_id "$experiment_id" \
    --arg pipe_id "$pipeline_id" \
    --arg pipe_ver_id "$pipeline_version_id" \
    --argjson params "$params_array" \
    '{
      name: $name,
      pipeline_spec: {
        pipeline_id: $pipe_id,
        pipeline_version_id: $pipe_ver_id
      },
      resource_references: [
        { key: { type: "EXPERIMENT", id: $exp_id }, relationship: "OWNER" }
      ],
      parameters: $params
    }')
  
  curl -sk -H "Authorization: Bearer $KFP_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST "$KFP_BASE/v1beta1/runs" \
    -d "$run_request" 2>/dev/null
}

# High-level: ensure pipeline is uploaded and create a run
# Exports: EXPERIMENT_ID, PIPELINE_ID, PIPELINE_VERSION_ID
ensure_pipeline_and_create_run() {
  local file="${1:-artifacts/docling-rag-pipeline-ascii.yaml}"
  local pipeline_name="${2:-docling-rag-llamastack}"
  local run_name="${3:-rag-run-$(date +%s)}"
  local params_json="$4"
  
  get_kfp_host_and_token
  
  # 1. Ensure experiment
  echo "1️⃣ Ensuring experiment..."
  EXPERIMENT_ID=$(ensure_experiment)
  echo "   ✅ Experiment ID: $EXPERIMENT_ID"
  
  # 2. Create pipeline with timestamp
  echo "2️⃣ Creating pipeline..."
  local timestamped_name="${pipeline_name}-$(date +%Y%m%d-%H%M%S)"
  PIPELINE_ID=$(create_pipeline "$timestamped_name")
  echo "   ✅ Pipeline ID: $PIPELINE_ID"
  
  # 3. Upload version
  echo "3️⃣ Uploading pipeline version..."
  local version_name="v$(date +%Y%m%d-%H%M%S)"
  PIPELINE_VERSION_ID=$(upload_pipeline_version "$file" "$PIPELINE_ID" "$version_name")
  echo "   ✅ Pipeline Version ID: $PIPELINE_VERSION_ID"
  
  # 4. Create run
  echo "4️⃣ Creating run via v1beta1 API..."
  local response
  response=$(kfp_create_run_v1 "$run_name" "$EXPERIMENT_ID" "$PIPELINE_ID" "$PIPELINE_VERSION_ID" "$params_json")
  
  local run_id
  run_id=$(echo "$response" | jq -r '.run.id' 2>/dev/null)
  
  if [ -n "$run_id" ] && [ "$run_id" != "null" ]; then
    echo "   ✅ Run ID: $run_id"
    export RUN_ID="$run_id"
  else
    echo "   ❌ Run creation failed"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
    return 1
  fi
  
  export EXPERIMENT_ID PIPELINE_ID PIPELINE_VERSION_ID RUN_ID
}
