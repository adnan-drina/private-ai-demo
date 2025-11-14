# 🎮 Stage 4: Playground Integration Guide

## Overview
How to integrate MCP tools with the LlamaStack Playground UI for Stage 4 demo.

---

## Current Playground Architecture

### Existing Features (Stage 2)
Located: `gitops/stage02-model-alignment/llama-stack/`

**Files**:
- `playground-chat.py` - Chat interface
- `playground-rag.py` - RAG interface  
- `playground-deployment.yaml` - Kubernetes deployment

**Current Capabilities**:
- ✅ Model selection dropdown
- ✅ Streaming responses
- ✅ Temperature/sampling controls
- ✅ System prompt configuration
- ✅ Guardrails enable/disable
- ✅ Shield selection
- ✅ RAG document upload
- ❌ **No MCP tool selection**

---

## Challenge: Adding Tool Selection

### The Gap
**Demo notebook** (programmatic):
```python
agent = ReActAgent(
    client=client,
    model=model_id,
    tools=["mcp::slack", "mcp::database", builtin_rag],  # ← Explicit tool list
)
```

**Our Playground** (UI):
- No UI element to select tools
- Tools must be specified when creating agent/turn

### Solution Options

---

## Option 1: Add Tool Selection Checkboxes (Recommended)

### Implementation

#### A. Discover Available Tools

Add to `playground-chat.py` and `playground-rag.py`:

```python
# After model selection, before guardrails section
st.subheader("Tools", divider=True)

# Fetch available tools from LlamaStack
try:
    available_tools = llama_stack_api.client.tools.list()
    
    # Group tools by type
    mcp_tools = [t for t in available_tools if t.identifier.startswith("mcp::")]
    builtin_tools = [t for t in available_tools if t.identifier.startswith("builtin::")]
    
    if mcp_tools:
        st.caption(f"Found {len(mcp_tools)} MCP tools")
        
        # Multi-select for MCP tools
        selected_mcp_tools = st.multiselect(
            "MCP Tools",
            options=[t.identifier for t in mcp_tools],
            default=[],
            help="Select MCP tools to enable for this conversation"
        )
    else:
        selected_mcp_tools = []
        st.info("No MCP tools available. Deploy MCP servers to enable tool calling.")
    
    # RAG tool toggle
    enable_rag = st.checkbox(
        "Enable Knowledge Search (RAG)",
        value=False,
        help="Allow the agent to search the vector database for relevant information"
    )
    
    if enable_rag:
        # Show available vector DBs
        vector_dbs = llama_stack_api.client.vector_dbs.list()
        selected_vector_db = st.selectbox(
            "Knowledge Base",
            options=[db.identifier for db in vector_dbs],
            help="Select which document collection to search"
        )
except Exception as e:
    st.warning(f"Could not fetch available tools: {e}")
    selected_mcp_tools = []
    enable_rag = False
```

#### B. Build Tool List for Agent

```python
# Build tools list for agent
tools = []

# Add selected MCP tools
tools.extend(selected_mcp_tools)

# Add RAG tool if enabled
if enable_rag:
    tools.append({
        "name": "builtin::rag",
        "args": {
            "vector_db_ids": [selected_vector_db]
        }
    })

# Store in session state
if "enabled_tools" not in st.session_state:
    st.session_state.enabled_tools = tools
else:
    st.session_state.enabled_tools = tools
```

#### C. Use Tools in Chat Completion

**For standard chat** (without agentic behavior):
```python
response = llama_stack_api.client.inference.chat_completion(
    messages=[
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": prompt},
    ],
    model_id=selected_model,
    stream=stream,
    tools=st.session_state.enabled_tools if st.session_state.enabled_tools else None,
    sampling_params={
        "strategy": strategy,
        "max_tokens": max_tokens,
        "repetition_penalty": repetition_penalty,
    },
)
```

**For agentic behavior** (ReAct):
```python
# Create agent session if tools are enabled
if st.session_state.enabled_tools:
    if "agent_session_id" not in st.session_state:
        st.session_state.agent_session_id = llama_stack_api.client.agents.session.create(
            agent_id="playground-agent",
            session_name=f"session-{int(time.time())}"
        )
    
    # Use agent turn creation
    response = llama_stack_api.client.agents.turn.create(
        agent_config={
            "model": selected_model,
            "instructions": system_prompt,
            "tools": st.session_state.enabled_tools,
            "sampling_params": sampling_params,
        },
        messages=[{"role": "user", "content": prompt}],
        session_id=st.session_state.agent_session_id,
        stream=stream,
    )
else:
    # Standard inference (no tools)
    response = llama_stack_api.client.inference.chat_completion(...)
```

#### D. Display Tool Calls

```python
# After streaming completes, show tool calls if any
if hasattr(response, 'steps'):
    for step in response.steps:
        if step.step_type == "tool_execution":
            with st.expander(f"🔧 Tool Call: {step.tool_name}", expanded=False):
                st.json({
                    "tool": step.tool_name,
                    "arguments": step.tool_arguments,
                    "result": step.tool_response
                })
```

---

## Option 2: Agent Profile Dropdown (Simpler)

### Pre-configured Agent Profiles

```python
st.subheader("Agent Profile", divider=True)

AGENT_PROFILES = {
    "None (Basic Chat)": {
        "tools": [],
        "description": "Standard chat without tools"
    },
    "ACME Calibration Assistant": {
        "tools": ["mcp::database", "mcp::slack", {"name": "builtin::rag", "args": {"vector_db_ids": ["acme_calibration_docs"]}}],
        "description": "Equipment queries, calibration history, and Slack notifications"
    },
    "DevOps Assistant": {
        "tools": ["mcp::openshift", "mcp::slack", {"name": "builtin::rag", "args": {"vector_db_ids": ["red_hat_docs"]}}],
        "description": "OpenShift troubleshooting and team alerts"
    },
    "Knowledge Explorer": {
        "tools": [{"name": "builtin::rag", "args": {"vector_db_ids": ["red_hat_docs", "acme_corporate", "eu_ai_act"]}}],
        "description": "Search across all knowledge bases"
    },
}

selected_profile = st.selectbox(
    "Agent Profile",
    options=list(AGENT_PROFILES.keys()),
    help="Select a pre-configured agent with specific tools enabled"
)

st.caption(AGENT_PROFILES[selected_profile]["description"])

# Use profile's tools
agent_tools = AGENT_PROFILES[selected_profile]["tools"]
```

**Pros**:
- ✅ Simpler UI
- ✅ Guided experience
- ✅ Pre-validated tool combinations

**Cons**:
- ❌ Less flexible
- ❌ Can't mix custom tool sets

---

## Option 3: Always-On Auto-Tool Selection

### Let LLM Decide

```python
# Register all tools with agent, let LLM choose which to use
response = llama_stack_api.client.inference.chat_completion(
    messages=messages,
    model_id=selected_model,
    tools="all",  # Give access to all registered tools
    tool_choice="auto",  # LLM decides when to use tools
    stream=stream,
)
```

**Pros**:
- ✅ No UI changes needed
- ✅ Maximum LLM autonomy
- ✅ Simplest implementation

**Cons**:
- ❌ No user control
- ❌ May use expensive/slow tools unnecessarily
- ❌ Less transparent

---

## Recommended Approach: Hybrid

### Combine Options 1 & 2

**For Power Users**: Tool checkboxes (Option 1)  
**For Quick Start**: Agent profiles (Option 2)

```python
st.subheader("Agent Configuration", divider=True)

config_mode = st.radio(
    "Configuration Mode",
    options=["Quick Start (Profiles)", "Advanced (Custom Tools)"],
    horizontal=True
)

if config_mode == "Quick Start (Profiles)":
    # Show agent profiles dropdown
    selected_profile = st.selectbox(...)
    agent_tools = AGENT_PROFILES[selected_profile]["tools"]
else:
    # Show tool checkboxes
    selected_mcp_tools = st.multiselect(...)
    enable_rag = st.checkbox(...)
    agent_tools = build_tools_list(selected_mcp_tools, enable_rag)
```

---

## Displaying Tool Execution

### Show Tool Calls in UI

```python
def display_agent_steps(steps):
    """Display agent's reasoning and tool calls"""
    for step in steps:
        if step.step_type == "shield_call":
            # Guardrail check
            with st.expander("🛡️ Guardrail Check", expanded=False):
                st.write(f"Shield: {step.shield_id}")
                st.write(f"Result: {step.result}")
        
        elif step.step_type == "tool_execution":
            # Tool call
            with st.expander(f"🔧 Tool: {step.tool_name}", expanded=True):
                col1, col2 = st.columns(2)
                
                with col1:
                    st.markdown("**Arguments**")
                    st.json(step.tool_arguments)
                
                with col2:
                    st.markdown("**Response**")
                    if isinstance(step.tool_response, dict):
                        st.json(step.tool_response)
                    else:
                        st.text(step.tool_response)
        
        elif step.step_type == "inference":
            # LLM thinking
            with st.expander("💭 Model Reasoning", expanded=False):
                st.write(step.model_response)

# Use in main chat loop
if hasattr(response, 'steps') and response.steps:
    st.divider()
    st.subheader("Agent Steps")
    display_agent_steps(response.steps)
```

---

## RAG Tool Configuration

### Existing RAG Interface

**Current**: `playground-rag.py` has dedicated RAG page

**Integration**: Can still use RAG as a tool in Chat page

```python
# In Chat page, if RAG tool is enabled
if enable_rag:
    st.info(f"""
    📚 **Knowledge Search Enabled**
    
    The agent can search the **{selected_vector_db}** collection for relevant information.
    
    Example prompts:
    - "Search for calibration procedures"
    - "What do the docs say about troubleshooting?"
    """)
```

---

## Agent vs Non-Agent Mode

### When to Use Agents

**Use Agent Mode** (agentic turn) when:
- ✅ Tools are enabled
- ✅ Multi-step reasoning needed
- ✅ Tool chaining required

**Use Standard Inference** when:
- ✅ No tools enabled
- ✅ Simple chat
- ✅ Faster responses needed

### Implementation

```python
def should_use_agent_mode():
    """Determine if agent mode is needed"""
    return bool(st.session_state.enabled_tools)

if should_use_agent_mode():
    # Create/reuse agent session
    response = create_agent_turn(...)
else:
    # Standard chat completion
    response = chat_completion(...)
```

---

## Testing Checklist

### UI Testing
- [ ] Tool selection UI appears correctly
- [ ] Selected tools are persisted in session
- [ ] Tool calls are displayed in chat
- [ ] Tool responses are formatted properly
- [ ] Streaming works with tool calls
- [ ] Guardrails + tools work together

### Functional Testing
- [ ] `mcp::database` tools execute correctly
- [ ] `mcp::slack` notifications work (demo mode)
- [ ] `builtin::rag` searches correct collection
- [ ] Tool errors are handled gracefully
- [ ] Agent profiles load correct tools

### Integration Testing
- [ ] Tools work in Chat page
- [ ] Tools work in RAG page
- [ ] Multi-turn conversations with tools
- [ ] Tool call history persists in session

---

## Example User Flows

### Flow 1: ACME Calibration Query

**Steps**:
1. User opens Chat page
2. Selects "ACME Calibration Assistant" profile
3. Enters: "Check calibration for Litho-Print-3000"
4. Agent:
   - Calls `mcp::database::query_equipment`
   - Shows equipment details
   - Calls `builtin::rag::knowledge_search`  
   - Shows calibration procedures
   - Calls `mcp::slack::send_alert`
   - Confirms notification sent
5. User sees complete response with all tool calls visible

### Flow 2: Custom Tool Selection

**Steps**:
1. User opens Chat page
2. Switches to "Advanced" mode
3. Selects:
   - ☑ `mcp::database`
   - ☑ `builtin::rag` (acme_calibration_docs)
4. Enters: "When was LITHO-3000 last calibrated?"
5. Agent queries database, returns result
6. User asks follow-up: "Show me the procedure"
7. Agent searches RAG, returns procedure doc

---

## Implementation Priority

### Phase 1: Basic Integration
1. Add tool listing from LlamaStack
2. Add simple checkbox for enabling tools
3. Pass tools to inference/agent API
4. Display tool calls in chat

### Phase 2: Enhanced UI
1. Add agent profile dropdown
2. Group tools by category
3. Show tool descriptions
4. Add tool execution visualization

### Phase 3: Advanced Features
1. Tool configuration (e.g., RAG collection selection)
2. Tool call history/analytics
3. Tool error handling UI
4. Tool performance metrics

---

## Code Changes Required

### Files to Modify

1. **`gitops/stage02-model-alignment/llama-stack/playground-chat.py`**
   - Add tool selection UI
   - Implement agent mode detection
   - Add tool call display

2. **`gitops/stage02-model-alignment/llama-stack/playground-rag.py`**
   - Add MCP tool support to RAG flow
   - Keep RAG tool as primary but allow others

3. **`gitops/stage02-model-alignment/llama-stack/playground-deployment.yaml`**
   - No changes needed (tools registered in LlamaStack)

### Estimated LOC Changes
- `playground-chat.py`: +150 lines
- `playground-rag.py`: +100 lines
- New file `utils/tools.py`: +50 lines (shared tool logic)

---

## Next Steps

1. **Choose integration approach** (Recommended: Hybrid)
2. **Implement tool UI** in Chat page
3. **Test with database-mcp and slack-mcp**
4. **Add tool visualization**
5. **Document user guide**

---

**Status**: 📝 **Ready for UI Implementation**

