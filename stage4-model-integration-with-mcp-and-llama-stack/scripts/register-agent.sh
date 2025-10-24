#!/bin/bash
#
# Register ACME Calibration Agent with Llama Stack
#
# This script registers the agent configuration with Llama Stack,
# enabling it to orchestrate multi-model inference, MCP tools, and RAG.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC}  $1"; }
log_success() { echo -e "${GREEN}✓${NC}  $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC}  $1"; }

# Configuration
NAMESPACE="${NAMESPACE:-private-ai-demo}"
AGENT_ID="acme-calibration-agent"
MODEL_ID="mistral-24b-quantized"  # Default to cost-efficient model

echo "════════════════════════════════════════════════════════════"
echo "  🤖 ACME Calibration Agent Registration"
echo "════════════════════════════════════════════════════════════"
echo ""

# Get Llama Stack endpoint
log_info "Detecting Llama Stack service..."

LLAMA_STACK_SVC="llamastack-server.${NAMESPACE}.svc.cluster.local:8321"
LLAMA_STACK_URL="http://${LLAMA_STACK_SVC}"

# Check if we can reach Llama Stack
if ! oc exec -n "${NAMESPACE}" deployment/llama-stack -- curl -s -f "${LLAMA_STACK_URL}/health" > /dev/null 2>&1; then
    log_error "Cannot reach Llama Stack at ${LLAMA_STACK_URL}"
    log_info "Please ensure Llama Stack is deployed and healthy"
    exit 1
fi

log_success "Llama Stack found: ${LLAMA_STACK_URL}"

# Check if agent already exists
log_info "Checking if agent already exists..."

EXISTING_AGENT=$(oc exec -n "${NAMESPACE}" deployment/llama-stack -- \
    curl -s "${LLAMA_STACK_URL}/agents/${AGENT_ID}" 2>/dev/null || echo "")

if [[ "$EXISTING_AGENT" =~ "agent_id" ]]; then
    log_warn "Agent '${AGENT_ID}' already exists"
    log_info "Updating agent configuration..."
    # For updates, we would need to delete and recreate
    # Llama Stack Agent API doesn't support PATCH yet
else
    log_info "Agent not found, will create new registration"
fi

# Register the agent
log_info "Registering ACME Calibration Agent..."

AGENT_CONFIG=$(cat <<EOF
{
  "agent_id": "${AGENT_ID}",
  "model": "${MODEL_ID}",
  "instructions": "You are an expert semiconductor manufacturing calibration assistant for ACME Corporation.\n\nYour role is to:\n1. Analyze equipment telemetry data to identify calibration issues\n2. Query the equipment database for specifications and maintenance history\n3. Provide data-driven recommendations based on calibration procedures\n4. Send alerts to the engineering team via Slack when critical issues are detected\n\nAvailable tools:\n- mcp::database: Query equipment metadata, specifications, and maintenance history from PostgreSQL\n- mcp::slack: Send notifications to engineering teams\n- builtin::rag: Search calibration documentation and procedures from Milvus vector DB\n\nGuidelines:\n- Always check equipment database first for context\n- Reference calibration procedures from documentation when making recommendations\n- Use clear, technical language appropriate for semiconductor engineers\n- Include numerical data to support all recommendations\n- Alert teams immediately for drift > 2.5nm (warning threshold)\n- Use CRITICAL priority for drift > 5.0nm (action limit)",
  "tools": [
    "mcp::database",
    "mcp::slack",
    "builtin::rag"
  ],
  "sampling_params": {
    "temperature": 0.7,
    "top_p": 0.9,
    "max_tokens": 1024
  },
  "enable_session_persistence": true
}
EOF
)

# Execute registration via kubectl exec (since we're inside the cluster)
RESPONSE=$(oc exec -n "${NAMESPACE}" deployment/llama-stack -- \
    curl -s -X POST "${LLAMA_STACK_URL}/agents" \
    -H "Content-Type: application/json" \
    -d "${AGENT_CONFIG}")

# Check if registration was successful
if echo "$RESPONSE" | grep -q "agent_id"; then
    log_success "Agent registered successfully!"
    echo ""
    echo "Agent Configuration:"
    echo "  • ID: ${AGENT_ID}"
    echo "  • Model: ${MODEL_ID} (Mistral 24B Quantized)"
    echo "  • Tools: database, slack, rag"
    echo "  • Temperature: 0.7"
    echo "  • Max Tokens: 1024"
    echo ""
    
    # Verify registration
    log_info "Verifying agent registration..."
    VERIFY=$(oc exec -n "${NAMESPACE}" deployment/llama-stack -- \
        curl -s "${LLAMA_STACK_URL}/agents/${AGENT_ID}")
    
    if echo "$VERIFY" | grep -q "agent_id"; then
        log_success "Agent verification successful"
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo "  ✅ REGISTRATION COMPLETE"
        echo "════════════════════════════════════════════════════════════"
        echo ""
        echo "Next steps:"
        echo "  1. Deploy ACME Agent UI: cd stage3-enterprise-mcp && ./deploy.sh"
        echo "  2. Test agent: curl http://acme-agent:8080/api/v1/health"
        echo "  3. Run calibration check with telemetry data"
        echo ""
    else
        log_warn "Could not verify agent registration"
    fi
else
    log_error "Agent registration failed"
    echo ""
    echo "Response from Llama Stack:"
    echo "$RESPONSE"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check Llama Stack logs: oc logs -n ${NAMESPACE} deployment/llama-stack"
    echo "  2. Verify MCP servers are running: oc get pods -n ${NAMESPACE}"
    echo "  3. Check ConfigMap: oc get configmap llamastack-config -n ${NAMESPACE}"
    exit 1
fi

