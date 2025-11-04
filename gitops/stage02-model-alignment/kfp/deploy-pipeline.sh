#!/bin/bash
# Reproducible KFP Pipeline Deployment Script
# Can be called from main deploy.sh or run standalone

set -e

NAMESPACE="private-ai-demo"
PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$PIPELINE_DIR/../../.." && pwd)"

echo "════════════════════════════════════════════════════════════════════════════════"
echo "DEPLOYING KFP V2 PIPELINE (REPRODUCIBLE)"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

cd "$PROJECT_ROOT"

# 1. Ensure DSPA is ready
echo "1️⃣ Verifying DSPA status..."
DSPA_READY=$(oc get dspa dspa -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$DSPA_READY" != "True" ]; then
  echo "❌ DSPA not ready. Apply DSPA configuration first:"
  echo "   oc apply -f gitops/stage02-model-alignment/kfp/dspa.yaml"
  exit 1
fi
echo "   ✅ DSPA Ready"
echo ""

# 2. Ensure pipeline is compiled
echo "2️⃣ Checking compiled pipeline..."
if [ ! -f "artifacts/docling-rag-pipeline.yaml" ]; then
  echo "   Compiling pipeline..."
  source .venv-kfp/bin/activate 2>/dev/null || python3 -m venv .venv-kfp
  source .venv-kfp/bin/activate
  pip install -q kfp==2.14.6
  python3 stages/stage2-model-alignment/kfp/pipeline.py
  deactivate
fi
echo "   ✅ Pipeline compiled"
echo ""

# 3. Upload pipeline via port-forward
echo "3️⃣ Uploading pipeline to DSPA..."
echo "   Starting port-forward (backgrounded)..."
oc port-forward svc/ds-pipeline-dspa 8888:8443 -n $NAMESPACE > /dev/null 2>&1 &
PF_PID=$!
sleep 3

echo "   Uploading pipeline..."
source .venv-kfp/bin/activate
export DSPA_ENDPOINT="https://localhost:8888"
python3 gitops/stage02-model-alignment/kfp/upload-pipeline.py
UPLOAD_STATUS=$?
deactivate

# Clean up port-forward
kill $PF_PID 2>/dev/null || true

if [ $UPLOAD_STATUS -eq 0 ]; then
  echo "   ✅ Pipeline uploaded successfully"
else
  echo "   ❌ Pipeline upload failed"
  exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ PIPELINE DEPLOYMENT COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Pipeline is now available in:"
echo "  • RHOAI Dashboard → Data Science Projects → $NAMESPACE → Pipelines"
echo "  • Direct KFP UI: https://$(oc get route ds-pipeline-dspa -n $NAMESPACE -o jsonpath='{.spec.host}')"
echo ""
echo "To create a pipeline run:"
echo "  1. Via Dashboard: Click 'Create run' button"
echo "  2. Via Script: ./gitops/stage02-model-alignment/kfp/create-run.sh"
echo ""
