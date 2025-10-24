#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 4: Model Integration - Validation Script
##############################################################################

NAMESPACE="private-ai-demo"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 4: Validation"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "🗄️  PostgreSQL:"
oc get deployment postgresql -n "$NAMESPACE" 2>/dev/null || echo "❌ PostgreSQL not found"
echo ""

echo "🔌 MCP Servers:"
oc get deployment database-mcp -n "$NAMESPACE" 2>/dev/null || echo "❌ Database MCP not found"
oc get deployment slack-mcp -n "$NAMESPACE" 2>/dev/null || echo "❌ Slack MCP not found"
echo ""

echo "🤖 ACME Agent:"
oc get deployment acme-agent -n "$NAMESPACE" 2>/dev/null || echo "❌ ACME Agent not found"
oc get route acme-agent -n "$NAMESPACE" 2>/dev/null || echo "⚠️  Route not found"
echo ""

echo "📓 Agent Notebook:"
oc get deployment rag-testing -n "$NAMESPACE" 2>/dev/null || echo "⚠️  Workbench not found"
echo ""

echo "✅ Validation complete"
