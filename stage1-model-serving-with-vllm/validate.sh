#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 1: Model Serving - Validation Script
##############################################################################

NAMESPACE="private-ai-demo"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 1: Validation"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "📋 Namespace:"
oc get project "$NAMESPACE" 2>/dev/null || echo "❌ Namespace not found"
echo ""

echo "🤖 InferenceServices:"
oc get inferenceservice -n "$NAMESPACE"
echo ""

echo "📦 Model Download Jobs:"
oc get jobs -n "$NAMESPACE" -l app=model-loader
echo ""

echo "💾 MinIO Storage:"
oc get deployment minio -n "$NAMESPACE" 2>/dev/null || echo "⚠️  MinIO not found"
echo ""

echo "📊 Benchmark Jobs:"
oc get jobs -n "$NAMESPACE" -l app=guidellm-benchmark
echo ""

echo "📓 Workbench:"
oc get deployment rag-testing -n "$NAMESPACE" 2>/dev/null || echo "⚠️  Workbench not found"
echo ""

echo "✅ Validation complete"
