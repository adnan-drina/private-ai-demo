#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="private-ai-demo"

echo "════════════════════════════════════════════════════════════════"
echo "  📊 LM-Eval Jobs Monitor"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Function to get job status
get_job_status() {
    local job_name=$1
    oc get job -n $NAMESPACE $job_name -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "NotFound"
}

# Function to get pod status
get_pod_status() {
    local label=$1
    oc get pod -n $NAMESPACE -l "$label" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound"
}

# Function to get container status
get_container_status() {
    local label=$1
    local container=$2
    oc get pod -n $NAMESPACE -l "$label" -o jsonpath="{.items[0].status.containerStatuses[?(@.name=='$container')].state}" 2>/dev/null | jq -r 'keys[0]' 2>/dev/null || echo "unknown"
}

# Function to get last log line
get_last_log() {
    local label=$1
    local container=$2
    oc logs -n $NAMESPACE -l "$label" -c $container --tail=1 2>/dev/null || echo "No logs yet"
}

# Monitor loop
DURATION=0
MAX_DURATION=3600  # 1 hour

while [ $DURATION -lt $MAX_DURATION ]; do
    clear
    echo "════════════════════════════════════════════════════════════════"
    echo "  📊 LM-Eval Jobs Monitor"
    echo "  ⏱️  Running for: ${DURATION}s / ${MAX_DURATION}s"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Get job statuses
    FULL_JOB_STATUS=$(get_job_status "eval-mistral-full")
    QUANT_JOB_STATUS=$(get_job_status "eval-mistral-quantized")
    
    # Get pod statuses
    FULL_POD_STATUS=$(get_pod_status "model=mistral-24b")
    QUANT_POD_STATUS=$(get_pod_status "model=mistral-24b-quantized")
    
    # Full Precision Model
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 🎯 Mistral 24B Full Precision (4 GPUs)                     │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Job Status:  $FULL_JOB_STATUS"
    echo "│ Pod Status:  $FULL_POD_STATUS"
    
    if [ "$FULL_POD_STATUS" != "NotFound" ]; then
        FULL_EVAL_STATE=$(get_container_status "model=mistral-24b" "lm-eval")
        FULL_PUBLISH_STATE=$(get_container_status "model=mistral-24b" "publish-results")
        echo "│ ├─ lm-eval:         $FULL_EVAL_STATE"
        echo "│ └─ publish-results: $FULL_PUBLISH_STATE"
        
        if [ "$FULL_EVAL_STATE" == "running" ]; then
            LAST_LOG=$(get_last_log "model=mistral-24b" "lm-eval" | cut -c 1-50)
            echo "│ Latest: $LAST_LOG"
        fi
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Quantized Model
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 🎯 Mistral 24B Quantized (1 GPU)                           │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Job Status:  $QUANT_JOB_STATUS"
    echo "│ Pod Status:  $QUANT_POD_STATUS"
    
    if [ "$QUANT_POD_STATUS" != "NotFound" ]; then
        QUANT_EVAL_STATE=$(get_container_status "model=mistral-24b-quantized" "lm-eval")
        QUANT_PUBLISH_STATE=$(get_container_status "model=mistral-24b-quantized" "publish-results")
        echo "│ ├─ lm-eval:         $QUANT_EVAL_STATE"
        echo "│ └─ publish-results: $QUANT_PUBLISH_STATE"
        
        if [ "$QUANT_EVAL_STATE" == "running" ]; then
            LAST_LOG=$(get_last_log "model=mistral-24b-quantized" "lm-eval" | cut -c 1-50)
            echo "│ Latest: $LAST_LOG"
        fi
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Check if both jobs completed
    if [ "$FULL_JOB_STATUS" == "Complete" ] && [ "$QUANT_JOB_STATUS" == "Complete" ]; then
        echo -e "${GREEN}✅ BOTH JOBS COMPLETED SUCCESSFULLY!${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Check results in Model Registry"
        echo "  2. Review Grafana dashboard"
        echo "  3. Fix Prometheus sidecar"
        echo ""
        break
    fi
    
    # Check for failures
    if [ "$FULL_JOB_STATUS" == "Failed" ] || [ "$QUANT_JOB_STATUS" == "Failed" ]; then
        echo -e "${RED}❌ ONE OR MORE JOBS FAILED${NC}"
        echo ""
        echo "Check events:"
        echo "  oc get events -n $NAMESPACE --sort-by='.lastTimestamp' | grep eval"
        echo ""
        echo "Check logs:"
        echo "  oc logs -n $NAMESPACE -l app=trustyai-eval -c lm-eval"
        echo ""
        break
    fi
    
    # Show raw status
    echo "Raw status:"
    oc get jobs,pods -n $NAMESPACE -l app=trustyai-eval --no-headers 2>/dev/null || echo "No resources found"
    echo ""
    echo -e "${YELLOW}⏳ Refreshing in 30s... (Ctrl+C to stop)${NC}"
    
    sleep 30
    DURATION=$((DURATION + 30))
done

if [ $DURATION -ge $MAX_DURATION ]; then
    echo -e "${RED}⏱️  TIMEOUT: Monitor stopped after 1 hour${NC}"
    echo ""
    echo "Jobs may still be running. Check manually:"
    echo "  oc get jobs,pods -n $NAMESPACE -l app=trustyai-eval"
fi


