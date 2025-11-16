# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the terms described in the LICENSE file in
# the root directory of this source tree.

import uuid

import streamlit as st
from llama_stack_client import Agent
from llama_stack_client.lib.agents.react.agent import ReActAgent
from llama_stack_client.lib.agents.event_logger import EventLogger

from llama_stack.distribution.ui.modules.api import llama_stack_api


def tool_chat_page():
    st.title("🛠 Tools")

    client = llama_stack_api.client
    models = client.models.list()
    model_list = [model.identifier for model in models if model.api_model_type == "llm"]

    tool_groups = client.toolgroups.list()
    tool_groups_list = [tool_group.identifier for tool_group in tool_groups]
    mcp_tools_list = [tool for tool in tool_groups_list if tool.startswith("mcp::")]
    builtin_tools_list = [tool for tool in tool_groups_list if not tool.startswith("mcp::")]

    def reset_agent():
        st.session_state.clear()
        st.cache_resource.clear()

    with st.sidebar:
        st.title("Configuration")
        st.subheader("Model")
        model = st.selectbox(label="Model", options=model_list, on_change=reset_agent, label_visibility="collapsed")

        st.subheader("Available ToolGroups")

        toolgroup_selection = st.pills(
            label="Built-in tools",
            options=builtin_tools_list,
            selection_mode="multi",
            on_change=reset_agent,
            format_func=lambda tool: "".join(tool.split("::")[1:]),
            help="List of built-in tools from your llama stack server.",
        )

        if "builtin::rag" in toolgroup_selection:
            vector_dbs = llama_stack_api.client.vector_dbs.list() or []
            if not vector_dbs:
                st.info("No vector databases available for selection.")
            # Use human-readable names (e.g., "red_hat_docs") instead of UUIDs (e.g., "vs_0e19961e...")
            vector_dbs = [
                getattr(vector_db, "name", None) or getattr(vector_db, "vector_db_id", None) or vector_db.identifier
                for vector_db in vector_dbs
            ]
            selected_vector_dbs = st.multiselect(
                label="Select Document Collections to use in RAG queries",
                options=vector_dbs,
                on_change=reset_agent,
            )

        mcp_selection = st.pills(
            label="MCP Servers",
            options=mcp_tools_list,
            selection_mode="multi",
            on_change=reset_agent,
            format_func=lambda tool: "".join(tool.split("::")[1:]),
            help="List of MCP servers registered to your llama stack server.",
        )

        toolgroup_selection.extend(mcp_selection)

        active_tool_list = []
        for toolgroup_id in toolgroup_selection:
            active_tool_list.extend(
                [
                    f"{''.join(toolgroup_id.split('::')[1:])}:{t.identifier}"
                    for t in client.tools.list(toolgroup_id=toolgroup_id)
                ]
            )

        st.markdown(f"Active Tools: 🛠 {len(active_tool_list)}", help="List of currently active tools.")
        st.json(active_tool_list)

        st.subheader("Agent Configurations")
        max_tokens = st.slider(
            "Max Tokens",
            min_value=16,
            max_value=4096,
            value=512,
            step=1,
            help="The maximum number of tokens to generate",
            on_change=reset_agent,
        )

    # CRITICAL FIX: Keep MCP tool references as STRINGS!
    # Based on working demo: https://github.com/opendatahub-io/llama-stack-demos/blob/main/demos/rag_agentic/notebooks/Level6_agents_MCP_and_RAG.ipynb
    # Tools should be:
    #   • "mcp::openshift" (string - references toolgroup_id from ConfigMap)
    #   • dict for builtin::rag (needs vector_db_ids args)
    # Previously we were converting ALL to dicts, which broke MCP execution!
    for i, tool_name in enumerate(toolgroup_selection):
        if tool_name == "builtin::rag":
            tool_dict = dict(
                name="builtin::rag",
                args={
                    "vector_db_ids": list(selected_vector_dbs),
                },
            )
            toolgroup_selection[i] = tool_dict
        # MCP tools (mcp::*) MUST stay as strings!

    # CRITICAL: Use ReActAgent (not base Agent) to match Level 6 demo
    # ReActAgent implements a Reasoning + Acting loop that FORCES tool usage
    # Base Agent uses tool_choice="auto" which lets LLM hallucinate
    # Reference: https://github.com/opendatahub-io/llama-stack-demos/blob/main/demos/rag_agentic/notebooks/Level6_agents_MCP_and_RAG.ipynb
    def create_agent(_model, _tools, _max_tokens):
        # Match demo: minimal sampling_params, no custom instructions, no tool_config
        return ReActAgent(
            client=client,
            model=_model,
            tools=_tools,  # List of strings (MCP) and dicts (RAG)
            sampling_params={"max_tokens": _max_tokens},
            # ReActAgent handles tool selection automatically through its reasoning loop
            # No need for custom instructions or tool_config
        )

    agent = create_agent(model, toolgroup_selection, max_tokens)

    if "agent_session_id" not in st.session_state:
        st.session_state["agent_session_id"] = agent.create_session(session_name=f"tool_demo_{uuid.uuid4()}")

    session_id = st.session_state["agent_session_id"]

    if "messages" not in st.session_state:
        st.session_state["messages"] = [{"role": "assistant", "content": "How can I help you?"}]

    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

    if prompt := st.chat_input(placeholder=""):
        with st.chat_message("user"):
            st.markdown(prompt)

        st.session_state.messages.append({"role": "user", "content": prompt})

        # Use ReActAgent.create_turn() - matches Level 6 demo pattern
        # ReActAgent will reason about the task and invoke tools automatically
        turn_response = agent.create_turn(
            messages=[{"role": "user", "content": prompt}],
            session_id=session_id,
            stream=True,
        )

        # Enhanced response generator that shows ReAct reasoning steps
        # Displays: Thought → Action (tool call) → Observation (result) → Answer
        def response_generator(turn_response):
            for event in EventLogger().log(turn_response):
                # Format different event types for better UX
                if event.role == "Tool":
                    # Tool execution step
                    yield f"\n\n🛠 **Executing Tool**: `{event.tool_name}`\n"
                    if event.tool_args:
                        yield f"```json\n{event.tool_args}\n```\n"
                elif event.role == "Observation":
                    # Tool result
                    yield f"\n📊 **Tool Result**:\n```\n{event.content[:500]}{'...' if len(event.content) > 500 else ''}\n```\n\n"
                elif event.role == "Thought":
                    # Agent reasoning
                    yield f"\n💭 **Thinking**: {event.content}\n\n"
                elif event.role == "Answer":
                    # Final answer
                    yield event.content
                else:
                    # Stream text deltas
                    if hasattr(event, 'content') and event.content:
                        yield event.content

        with st.chat_message("assistant"):
            with st.spinner("Agent is thinking and using tools..."):
                response = st.write_stream(response_generator(turn_response))

        st.session_state.messages.append({"role": "assistant", "content": response})


tool_chat_page()

