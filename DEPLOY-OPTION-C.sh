#!/bin/bash
##############################################################################
# Deploy Option C - vLLM Model Name Separation (Best Practices)
# Date: 2025-10-27
# Status: Ready for deployment
##############################################################################

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "🚀 Deploying Option C: vLLM Model Name Separation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

cd /Users/adrina/Sandbox/private-ai-demo

##############################################################################
# Step 1: Apply Pipeline Updates
##############################################################################
echo "📋 Step 1: Applying pipeline updates..."
echo ""

echo "  ✓ Applying updated pipeline definition (with vllm_model_name parameter)..."
oc apply -f gitops/stage01-model-serving/serving/pipelines/02-pipeline/pipeline-model-testing.yaml

echo "  ✓ Applying updated guidellm task (fixed results directory)..."
oc apply -f gitops/stage01-model-serving/serving/pipelines/01-tasks/task-run-guidellm.yaml

echo "  ✓ Applying InferenceService label updates..."
oc apply -f gitops/stage01-model-serving/serving/vllm/inferenceservice-mistral-24b-quantized.yaml

echo ""
echo "✅ Pipeline updates applied successfully!"
echo ""

##############################################################################
# Step 2: Verify Current State
##############################################################################
echo "═══════════════════════════════════════════════════════════════"
echo "🔍 Step 2: Verifying current state..."
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "📦 InferenceServices:"
oc get inferenceservice -n private-ai-demo

echo ""
echo "📊 Model Registry Models:"
MR_ROUTE=$(oc get route private-ai-model-registry-http -n rhoai-model-registries -o jsonpath='{.spec.host}')
echo "Model Registry: $MR_ROUTE"
curl -s "http://${MR_ROUTE}/api/model_registry/v1alpha3/registered_models" | python3 -c "import sys, json; models = json.load(sys.stdin)['items']; [print(f'  - {m[\"name\"]} (ID: {m[\"id\"]})') for m in models]"

echo ""

##############################################################################
# Step 3: Run Pipeline A (Optional - if new version needed)
##############################################################################
echo "═══════════════════════════════════════════════════════════════"
echo "⏭️  Step 3: Run Pipeline A (Optional)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Pipeline A will create new model versions with correct naming:"
echo "  Model: Mistral-Small-24B-Instruct"
echo "  Version: quantized-w4a16-1gpu (quantized)"
echo "  Version: full-fp16-4gpu (full precision)"
echo ""
echo "Commands:"
echo "  # For quantized model:"
echo "  oc create -f gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-quantized.yaml"
echo ""
echo "  # For full precision model:"
echo "  oc create -f gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-full.yaml"
echo ""
read -p "Run Pipeline A for quantized model now? (y/N): " run_pipeline_a

if [[ "$run_pipeline_a" =~ ^[Yy]$ ]]; then
  echo ""
  echo "  🚀 Creating Pipeline A run for quantized model..."
  oc create -f gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-mistral-quantized.yaml
  echo ""
  echo "  ✅ Pipeline A started! Monitor with:"
  echo "     oc get pipelineruns -n private-ai-demo"
  echo ""
  echo "  ⏱️  Expected duration: 45-60 minutes"
  echo ""
else
  echo "  ⏭️  Skipping Pipeline A (you can run it manually later)"
  echo ""
fi

##############################################################################
# Step 4: Run Pipeline B (Testing)
##############################################################################
echo "═══════════════════════════════════════════════════════════════"
echo "🧪 Step 4: Run Pipeline B (Model Testing)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Pipeline B will:"
echo "  1. Test InferenceService: mistral-24b-quantized"
echo "  2. Use vLLM name: mistral-24b-quantized (explicit, no autodiscovery)"
echo "  3. Publish to Model Registry:"
echo "     - Model: Mistral-Small-24B-Instruct"
echo "     - Version: quantized-w4a16-1gpu"
echo ""
read -p "Run Pipeline B now? (y/N): " run_pipeline_b

if [[ "$run_pipeline_b" =~ ^[Yy]$ ]]; then
  echo ""
  echo "  🧪 Creating Pipeline B run..."
  oc create -f gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-test-mistral-quantized.yaml
  
  PIPELINE_NAME=$(oc get pipelineruns -n private-ai-demo --sort-by=.metadata.creationTimestamp | grep test-mistral-quantized | tail -1 | awk '{print $1}')
  
  echo ""
  echo "  ✅ Pipeline B started: $PIPELINE_NAME"
  echo ""
  echo "  📊 Monitor with:"
  echo "     oc get pipelinerun $PIPELINE_NAME -n private-ai-demo"
  echo ""
  echo "  📜 View logs:"
  echo "     # lm-eval task"
  echo "     oc logs -f ${PIPELINE_NAME}-run-lm-eval-pod -n private-ai-demo --all-containers"
  echo ""
  echo "     # guidellm task"
  echo "     oc logs -f ${PIPELINE_NAME}-run-guidellm-pod -n private-ai-demo --all-containers"
  echo ""
  echo "     # publish-results task"
  echo "     oc logs -f ${PIPELINE_NAME}-publish-results-pod -n private-ai-demo --all-containers"
  echo ""
  echo "  ⏱️  Expected duration: 45-60 minutes"
  echo ""
else
  echo "  ⏭️  Skipping Pipeline B (you can run it manually later)"
  echo "     Command: oc create -f gitops/stage01-model-serving/serving/pipelines/03-runs/pipelinerun-test-mistral-quantized.yaml"
  echo ""
fi

##############################################################################
# Summary
##############################################################################
echo "═══════════════════════════════════════════════════════════════"
echo "✅ Option C Deployment Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📚 Documentation:"
echo "  - Best Practices: docs/02-PIPELINES/MODEL-REGISTRY-NAMING-BEST-PRACTICES.md"
echo "  - Implementation Summary: OPTION-C-IMPLEMENTATION-SUMMARY.md"
echo "  - Analysis: PIPELINE-B-NAMING-MISMATCH-ANALYSIS.md"
echo ""
echo "🔍 Verification:"
echo "  1. After Pipeline B completes, check Model Registry UI"
echo "  2. Navigate to: Mistral-Small-24B-Instruct → quantized-w4a16-1gpu"
echo "  3. Verify test results in customProperties"
echo "  4. Check lastUpdateTimeSinceEpoch is recent"
echo ""
echo "═══════════════════════════════════════════════════════════════"

