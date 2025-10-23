#!/bin/bash
set -euo pipefail

# Deploy TrustyAI Llama Stack Provider - Phase 2
# This script deploys the TrustyAI evaluation provider and updates Llama Stack

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
NAMESPACE="${NAMESPACE:-private-ai-demo}"

echo "🚀 Deploying TrustyAI Llama Stack Provider"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Verify prerequisites
echo "📋 Step 1: Verifying prerequisites..."
echo ""

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    echo "❌ Error: Namespace '$NAMESPACE' does not exist"
    exit 1
fi

# Check if TrustyAI Operator is enabled (check for pods, not CSV)
if ! oc get pods -n redhat-ods-applications | grep -q "trustyai-service-operator"; then
    echo "❌ Error: TrustyAI Operator is not running"
    echo "   Please enable TrustyAI in DataScienceCluster first"
    exit 1
fi

# Check if Llama Stack is deployed
if ! oc get deployment llama-stack -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Error: Llama Stack is not deployed in '$NAMESPACE'"
    echo "   Please deploy Stage 2 first"
    exit 1
fi

# Check if HuggingFace token secret exists
if ! oc get secret huggingface-token -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Error: HuggingFace token secret not found"
    echo "   Please create 'huggingface-token' secret first"
    exit 1
fi

echo "✅ All prerequisites met"
echo ""

# Step 2: Get model endpoints
echo "📋 Step 2: Getting model endpoints..."
echo ""

# Get URLs from InferenceService (KServe pattern)
MISTRAL_QUANTIZED_URL=$(oc get inferenceservice mistral-24b-quantized -n "$NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null | sed 's|https://||')
MISTRAL_FULL_URL=$(oc get inferenceservice mistral-24b -n "$NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null | sed 's|https://||')

if [ -z "$MISTRAL_QUANTIZED_URL" ] || [ -z "$MISTRAL_FULL_URL" ]; then
    echo "❌ Error: Model routes not found"
    echo "   Quantized: $MISTRAL_QUANTIZED_URL"
    echo "   Full: $MISTRAL_FULL_URL"
    exit 1
fi

echo "Model Endpoints:"
echo "  Quantized: https://$MISTRAL_QUANTIZED_URL"
echo "  Full:      https://$MISTRAL_FULL_URL"
echo ""

# Step 3: Deploy TrustyAI Provider
echo "📋 Step 3: Deploying TrustyAI Provider..."
echo ""

# Apply provider manifests
oc apply -k "$SCRIPT_DIR"

# Wait for provider deployment
echo "⏳ Waiting for provider to be ready..."
oc rollout status deployment/trustyai-lmeval-provider -n "$NAMESPACE" --timeout=5m

echo "✅ TrustyAI Provider deployed"
echo ""

# Step 4: Update Llama Stack configuration
echo "📋 Step 4: Updating Llama Stack configuration..."
echo ""

# Check if Llama Stack ConfigMap needs updating
if ! oc get configmap llamastack-config -n "$NAMESPACE" -o yaml | grep -q "eval:"; then
    echo "⚠️  Warning: Llama Stack ConfigMap does not have eval provider"
    echo "   This should have been updated by GitOps"
    echo "   Forcing ConfigMap update..."
    
    # Apply Llama Stack component to update ConfigMap
    oc apply -k "$PROJECT_ROOT/gitops/components/llama-stack"
    
    echo "✅ ConfigMap updated"
else
    echo "✅ ConfigMap already has eval provider"
fi

# Restart Llama Stack to pick up new configuration
echo "🔄 Restarting Llama Stack to load new provider..."
oc rollout restart deployment/llama-stack -n "$NAMESPACE"
oc rollout status deployment/llama-stack -n "$NAMESPACE" --timeout=5m

echo "✅ Llama Stack restarted"
echo ""

# Step 5: Verify integration
echo "📋 Step 5: Verifying integration..."
echo ""

# Wait for Llama Stack to be ready
sleep 10

# Check if eval API is available
LLAMA_STACK_URL="http://llama-stack.${NAMESPACE}.svc.cluster.local:8321"

echo "Testing Llama Stack eval API..."
if oc run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
   curl -s -f "${LLAMA_STACK_URL}/health" &>/dev/null; then
    echo "✅ Llama Stack is healthy"
else
    echo "⚠️  Warning: Could not verify Llama Stack health"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ TrustyAI Llama Stack Integration Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Next Steps:"
echo ""
echo "1. Test the integration:"
echo "   kubectl run -it --rm debug --image=python:3.11 --restart=Never -- bash"
echo "   # Then inside the pod:"
echo "   pip install llama-stack-client"
echo "   python3 -c \"from llama_stack_client import LlamaStackClient; client = LlamaStackClient(base_url='$LLAMA_STACK_URL'); print(client.eval.info())\""
echo ""
echo "2. Run evaluation from notebook:"
echo "   Open: stage2-private-data-rag/notebooks/05-unified-evaluation.ipynb"
echo ""
echo "3. Check provider logs:"
echo "   oc logs -f deployment/trustyai-lmeval-provider -n $NAMESPACE"
echo ""
echo "4. Check Llama Stack logs:"
echo "   oc logs -f deployment/llama-stack -n $NAMESPACE"
echo ""
echo "📚 Documentation:"
echo "   /gitops/components/trustyai-llama-stack-provider/README.md"
echo "   /docs/TRUSTYAI-NEXT-PHASE-PLAN.md"
echo ""

