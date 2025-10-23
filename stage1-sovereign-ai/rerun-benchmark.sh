#!/bin/bash
# Quick script to re-run GuideLLM benchmarks

set -e

MODEL=${1:-"quantized"}  # Default to quantized, or pass "full"

echo "🔄 Re-running GuideLLM benchmark for ${MODEL} model..."
echo ""

# Set model-specific variables
if [ "$MODEL" = "quantized" ]; then
    JOB_NAME="guidellm-benchmark-quantized"
    ISVC_NAME="mistral-24b-quantized"
    JOB_FILE="gitops/components/benchmarking/job-guidellm-quantized.yaml"
    PLACEHOLDER="mistral-24b-quantized-private-ai-demo.apps.CLUSTER_DOMAIN"
elif [ "$MODEL" = "full" ]; then
    JOB_NAME="guidellm-benchmark-full"
    ISVC_NAME="mistral-24b"
    JOB_FILE="gitops/components/benchmarking/job-guidellm-full.yaml"
    PLACEHOLDER="mistral-24b-private-ai-demo.apps.CLUSTER_DOMAIN"
else
    echo "❌ Error: Model must be 'quantized' or 'full'"
    exit 1
fi

# Step 1: Delete old job if exists
echo "🗑️  Step 1: Deleting old job..."
oc delete job $JOB_NAME -n private-ai-demo --ignore-not-found=true
echo "✅ Old job deleted"
echo ""

# Step 2: Get current InferenceService URL
echo "🔍 Step 2: Getting InferenceService URL..."
ISVC_URL=$(oc get inferenceservice $ISVC_NAME -n private-ai-demo -o jsonpath='{.status.url}')
if [ -z "$ISVC_URL" ]; then
    echo "❌ Error: Could not get InferenceService URL. Is the model deployed?"
    exit 1
fi
echo "✅ URL: $ISVC_URL"
echo ""

# Step 3: Apply new job with correct URL
echo "🚀 Step 3: Creating new benchmark job..."
sed "s|https://${PLACEHOLDER}|${ISVC_URL}|g" $JOB_FILE | oc apply -f -
echo "✅ Job created"
echo ""

# Step 4: Monitor progress
echo "📊 Step 4: Monitoring benchmark (this will take a few minutes)..."
echo ""
echo "💡 To follow logs in real-time:"
echo "   oc logs job/$JOB_NAME -n private-ai-demo -f"
echo ""
echo "💡 To check job status:"
echo "   oc get job $JOB_NAME -n private-ai-demo"
echo ""
echo "💡 Results will be in: /results/mistral-24b*-benchmark.json"
echo ""

# Optional: Wait for completion
read -p "Wait for benchmark to complete? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "⏳ Waiting for job to complete..."
    oc wait --for=condition=complete --timeout=30m job/$JOB_NAME -n private-ai-demo
    echo ""
    echo "✅ Benchmark complete!"
    echo ""
    echo "📋 To view results:"
    echo "   1. Open JupyterLab notebook: 01-benchmark.ipynb"
    echo "   2. Re-run all cells to see updated results"
fi

echo ""
echo "🎉 Done!"
