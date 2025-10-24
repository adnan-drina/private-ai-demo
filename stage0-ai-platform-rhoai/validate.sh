#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 0: AI Platform - Validation Script
##############################################################################

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 0: Validation"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "🤖 OpenShift AI Operator:"
oc get csv -n redhat-ods-operator | grep rhods-operator || echo "❌ Operator not found"
echo ""

echo "🏗️  DataScienceCluster:"
oc get datasciencecluster
echo ""

echo "🎮 GPU Operator:"
oc get csv -n nvidia-gpu-operator 2>/dev/null || echo "⚠️  GPU Operator namespace not found"
echo ""

echo "💻 GPU MachineSets:"
oc get machinesets -n openshift-machine-api | grep gpu || echo "⚠️  No GPU MachineSets"
echo ""

echo "🔢 GPU Nodes:"
oc get nodes -l node.kubernetes.io/instance-type --no-headers | grep g6 || echo "⚠️  No GPU nodes ready"
echo ""

echo "📦 Model Registry:"
oc get deployment model-registry-db -n rhoai-model-registries 2>/dev/null || echo "⚠️  Model Registry not found"
echo ""

echo "✅ Validation complete"
