#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 3: Model Monitoring - Validation Script
##############################################################################

NAMESPACE="private-ai-demo"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 3: Validation"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "🔍 TrustyAI LMEvalJobs:"
oc get lmevaljob -n "$NAMESPACE"
echo ""

echo "📊 Grafana:"
oc get deployment grafana-deployment -n grafana-system 2>/dev/null || echo "❌ Grafana not found"
oc get route grafana-route -n grafana-system 2>/dev/null || echo "⚠️  Route not found"
echo ""

echo "📈 Prometheus Monitors:"
oc get servicemonitor -n "$NAMESPACE" 2>/dev/null || echo "⚠️  No ServiceMonitors"
oc get podmonitor -n "$NAMESPACE" 2>/dev/null || echo "⚠️  No PodMonitors"
echo ""

echo "📓 Evaluation Notebook:"
oc get deployment rag-testing -n "$NAMESPACE" 2>/dev/null || echo "⚠️  Workbench not found"
echo ""

echo "✅ Validation complete"
