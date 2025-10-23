#!/bin/bash

echo "═══════════════════════════════════════════════════════════════"
echo "📊 Step 1 Monitoring Dashboard"
echo "═══════════════════════════════════════════════════════════════"
echo ""

INTERVAL=120  # 2 minutes
TIMEOUT=2400  # 40 minutes
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    clear
    echo "═══════════════════════════════════════════════════════════════"
    echo "📊 Step 1 Progress ($(date +%H:%M:%S))"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Job status
    echo "Job Status:"
    oc get lmevaljob -n private-ai-demo
    echo ""
    
    # Progress
    echo "Full Model Progress:"
    FULL_PROGRESS=$(oc logs mistral-24b-full-eval -n private-ai-demo 2>&1 | grep "Requesting API" | tail -1)
    [ -n "$FULL_PROGRESS" ] && echo "  $FULL_PROGRESS" || echo "  (initializing...)"
    echo ""
    
    echo "Quantized Model Progress:"
    QUANT_PROGRESS=$(oc logs mistral-24b-quantized-eval -n private-ai-demo 2>&1 | grep "Requesting API" | tail -1)
    [ -n "$QUANT_PROGRESS" ] && echo "  $QUANT_PROGRESS" || echo "  (initializing...)"
    echo ""
    
    # Error check
    echo "───────────────────────────────────────────────────────────────"
    echo "Error Check:"
    FULL_ERRORS=$(oc logs mistral-24b-full-eval -n private-ai-demo 2>&1 | grep -i "timeout\|5xx\|error" | wc -l | tr -d ' ')
    QUANT_ERRORS=$(oc logs mistral-24b-quantized-eval -n private-ai-demo 2>&1 | grep -i "timeout\|5xx\|error" | wc -l | tr -d ' ')
    
    if [ "$FULL_ERRORS" -eq "0" ]; then
        echo "  Full: ✅ No errors"
    else
        echo "  Full: ⚠️ $FULL_ERRORS error lines (check logs)"
    fi
    
    if [ "$QUANT_ERRORS" -eq "0" ]; then
        echo "  Quantized: ✅ No errors"
    else
        echo "  Quantized: ⚠️ $QUANT_ERRORS error lines (check logs)"
    fi
    
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo "Next check in 2 minutes... (Ctrl+C to stop)"
    
    # Check if complete
    FULL_STATE=$(oc get lmevaljob mistral-24b-full-eval -n private-ai-demo -o jsonpath='{.status.state}' 2>/dev/null)
    QUANT_STATE=$(oc get lmevaljob mistral-24b-quantized-eval -n private-ai-demo -o jsonpath='{.status.state}' 2>/dev/null)
    
    if [ "$FULL_STATE" = "Complete" ] && [ "$QUANT_STATE" = "Complete" ]; then
        echo ""
        echo "🎉 Both evaluations complete!"
        break
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 Final Status"
echo "═══════════════════════════════════════════════════════════════"
oc get lmevaljob -n private-ai-demo
