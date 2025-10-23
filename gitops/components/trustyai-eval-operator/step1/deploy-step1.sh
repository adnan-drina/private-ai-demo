#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════════════════"
echo "🚀 Step 1 Deployment: Raise Concurrency"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Changes from Step 0:"
echo "  • Full: num_concurrent 2 → 4"
echo "  • Quantized: num_concurrent 1 → 2"
echo "  • All other params unchanged (batchSize, timeouts, sampling)"
echo ""
echo "Expected gains:"
echo "  • Full: ~1.5-2x speedup (~13 min total)"
echo "  • Quantized: ~1.5-1.8x speedup (~30 min total)"
echo ""
read -p "Deploy Step 1 configs? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Step 1: Delete Step 0 evaluations..."
oc delete lmevaljob mistral-24b-full-eval mistral-24b-quantized-eval -n private-ai-demo --wait=true

echo ""
echo "Step 2: Deploy Step 1 configs..."
oc apply -f lmevaljob-full-step1.yaml
oc apply -f lmevaljob-quantized-step1.yaml

echo ""
echo "Step 3: Verify deployment..."
sleep 10
oc get lmevaljob -n private-ai-demo

echo ""
echo "Step 4: Monitor initial startup..."
sleep 30
oc get pods -n private-ai-demo | grep -E "NAME|eval"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ Step 1 Deployed!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Monitor with:"
echo "  oc logs mistral-24b-full-eval -n private-ai-demo -f"
echo "  oc logs mistral-24b-quantized-eval -n private-ai-demo -f"
echo ""
echo "Check for issues:"
echo "  • No timeout errors"
echo "  • No 5xx errors"
echo "  • Steady req/sec (not oscillating)"
echo "  • TTFT P95 stays under 5s"
echo ""
echo "Track metrics in Grafana:"
echo "  • Throughput should increase"
echo "  • TTFT may increase slightly (acceptable)"
echo ""
