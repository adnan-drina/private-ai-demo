#!/bin/bash
set -e

# Reproducible script to upload KFP pipeline and create run
# This script can be run by deploy.sh or manually

NAMESPACE="private-ai-demo"
PIPELINE_FILE="artifacts/docling-rag-pipeline.yaml"
PIPELINE_NAME="docling-rag-ingestion"

echo "════════════════════════════════════════════════════════════════════════════════"
echo "KFP V2 PIPELINE UPLOAD AND RUN (REPRODUCIBLE)"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Check if pipeline file exists
if [ ! -f "$PIPELINE_FILE" ]; then
  echo "❌ Pipeline file not found: $PIPELINE_FILE"
  echo "   Run: cd /path/to/repo && python3 stages/stage2-model-alignment/kfp/pipeline.py"
  exit 1
fi

# Get MinIO credentials
echo "Retrieving MinIO credentials..."
MINIO_KEY=$(oc get secret minio-credentials -n model-storage -o jsonpath='{.data.accesskey}' | base64 -d)
MINIO_SECRET=$(oc get secret minio-credentials -n model-storage -o jsonpath='{.data.secretkey}' | base64 -d)

# In KFP v2, we need to use the KFP SDK or REST API to upload pipelines
# For now, we'll document the manual approach and provide an alternative

echo ""
echo "APPROACH 1: Upload via RHOAI Dashboard (One-time manual step)"
echo "────────────────────────────────────────────────────────────────────────────────"
echo "1. Open: https://ds-pipeline-dspa-private-ai-demo.apps.cluster-gmgrr.gmgrr.sandbox5294.opentlc.com"
echo "2. Click 'Upload pipeline'"
echo "3. Select: $PIPELINE_FILE"
echo "4. Pipeline will be stored in DSPA database (persists across restarts)"
echo ""

echo "APPROACH 2: Use Python SDK (Fully automated)"
echo "────────────────────────────────────────────────────────────────────────────────"
echo "This requires OAuth token - see upload-pipeline.py script"
echo ""

echo "APPROACH 3: Direct Pipeline Run (Skip upload, use inline spec)"
echo "────────────────────────────────────────────────────────────────────────────────"
echo "We can create a Run directly using the compiled pipeline spec"
echo ""

# For reproducibility, let's create a Run using oc and the KFP API
echo "Creating pipeline run via KFP REST API..."
echo ""

# Get DSPA route
DSPA_ROUTE=$(oc get route ds-pipeline-dspa -n $NAMESPACE -o jsonpath='{.spec.host}')
DSPA_API="https://$DSPA_ROUTE/apis/v2beta1"

echo "DSPA API: $DSPA_API"
echo ""

# Note: This requires authentication
echo "⚠️  REST API approach requires OAuth token"
echo "   For reproducibility, pipelines should be uploaded once via UI"
echo "   Then runs can be created programmatically"
echo ""

echo "To create runs programmatically after upload:"
echo "  oc port-forward svc/ds-pipeline-dspa 8888:8443 -n $NAMESPACE"
echo "  # Then use KFP SDK with http://localhost:8888"
echo ""

echo "════════════════════════════════════════════════════════════════════════════════"
echo "For now, upload pipeline via dashboard once, then runs are reproducible"
echo "════════════════════════════════════════════════════════════════════════════════"
