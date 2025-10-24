#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 2: Model Alignment - Validation Script
##############################################################################

NAMESPACE="private-ai-demo"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 2: Validation"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "🗄️  Milvus:"
oc get deployment milvus-standalone -n "$NAMESPACE" 2>/dev/null || echo "❌ Milvus not found"
echo ""

echo "🦙 Llama Stack:"
oc get llamastackdistribution -n "$NAMESPACE"
oc get deployment llama-stack -n "$NAMESPACE" 2>/dev/null || echo "⚠️  Deployment pending"
echo ""

echo "📄 Docling + Embedding:"
oc get deployment docling -n "$NAMESPACE" 2>/dev/null || echo "❌ Docling not found"
oc get inferenceservice granite-embedding -n ai-infrastructure 2>/dev/null || echo "⚠️  Granite not found"
echo ""

echo "⚙️  Tekton Pipelines:"
tkn pipeline list -n "$NAMESPACE"
echo ""

echo "🏃 Pipeline Runs:"
tkn pr list -n "$NAMESPACE" | head -5
echo ""

echo "✅ Validation complete"
