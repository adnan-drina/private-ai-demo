# Patched version of the upstream Streamlit RAG page.

import json
import uuid
from typing import Iterable, List, Optional

import streamlit as st
from llama_stack_client import Agent, AgentEventLogger, RAGDocument

from llama_stack.apis.common.content_types import ToolCallDelta
from llama_stack.distribution.ui.modules.api import llama_stack_api
from llama_stack.distribution.ui.modules.utils import data_url_from_file


def _format_retrieved_context(chunks: List[dict]) -> str:
    if not chunks:
        return "No relevant context retrieved."

    formatted = []
    for item in chunks:
        header_parts = [f"[{item['vector_db']}"]
        if item["score"] is not None:
            header_parts.append(f"score={item['score']:.3f}")
        doc_id = item["metadata"].get("document_id")
        if doc_id:
            header_parts.append(doc_id)
        chunk_idx = item["metadata"].get("chunk_index")
        if chunk_idx is not None:
            header_parts.append(f"chunk={int(chunk_idx)}")
        header = " ".join(header_parts) + "]"
        formatted.append(f"{header}\n{item['content']}".strip())
    return "\n\n".join(formatted)


def _dedupe_chunks_by_document(chunks: List[dict]) -> List[dict]:
    grouped: dict[tuple[str, str], List[dict]] = {}
    for item in chunks:
        metadata = item.get("metadata") or {}
        doc_id = metadata.get("document_id")
        if not doc_id:
            doc_id = (item.get("content") or "")[:80]
        key = (item.get("vector_db") or "", doc_id)
        grouped.setdefault(key, []).append(item)

    deduped: List[dict] = []
    for items in grouped.values():
        def sort_key(entry: dict):
            score = entry.get("score")
            score = score if score is not None else float("-inf")
            chunk_idx = entry.get("metadata", {}).get("chunk_index")
            non_intro = 1 if chunk_idx not in (None, 0) else 0
            return (non_intro, score)

        chosen = max(items, key=sort_key)
        # If we chose a non-intro chunk, but there is also an intro chunk, append intro after for additional context
        intro_chunks = [
            entry for entry in items if entry.get("metadata", {}).get("chunk_index") in (None, 0) and entry is not chosen
        ]
        deduped.append(chosen)
        if intro_chunks and chosen.get("metadata", {}).get("chunk_index") not in (None, 0):
            deduped.extend(intro_chunks[:1])

    return deduped


def _extract_vector_db_id(item) -> str:
    """
    Extract the human-readable vector DB name (not the UUID).
    
    LlamaStack /v1/vector_stores returns:
      {
        "id": "vs_0e19961e-6541-49d8-bb99-1ea00ee7a4d2",  # UUID (internal use)
        "name": "red_hat_docs",                            # Human-readable name
        "vector_db_id": "red_hat_docs"                     # Alias for name
      }
    
    We want to display "red_hat_docs", not "vs_0e19961e...".
    """
    if item is None:
        return ""
    
    # Try name first (this is the human-readable identifier)
    name = getattr(item, "name", None)
    if name:
        return name
    
    # Try vector_db_id (alias for name in some responses)
    vector_db_id = getattr(item, "vector_db_id", None)
    if vector_db_id:
        return vector_db_id
    
    # Dict handling
    if isinstance(item, dict):
        # Check for name or vector_db_id first
        name = item.get("name") or item.get("vector_db_id")
        if name:
            return name
        
        # Check metadata
        metadata = item.get("metadata") or {}
        if isinstance(metadata, dict):
            metadata_name = metadata.get("vector_db_id") or metadata.get("provider_vector_db_id")
            if metadata_name:
                return metadata_name
        
        # Last resort: use identifier or id (UUID fallback)
        return item.get("identifier") or item.get("id") or ""
    
    # Object handling - check metadata
    metadata = getattr(item, "metadata", None) or {}
    if isinstance(metadata, dict):
        metadata_name = metadata.get("vector_db_id") or metadata.get("provider_vector_db_id")
        if metadata_name:
            return metadata_name
    
    # Last resort: fallback to UUID
    return getattr(item, "identifier", None) or getattr(item, "id", None) or ""


def _list_shield_ids() -> List[str]:
    try:
        shields = llama_stack_api.client.shields.list()
    except Exception:
        return []
    ids = []
    for shield in shields:
        identifier = getattr(shield, "identifier", None)
        if identifier:
            ids.append(identifier)
    return ids


def _filter_guardrail_messages(messages: list[dict]) -> list[dict]:
    """Remove system messages and ensure assistant messages have required fields."""
    filtered = []
    for msg in messages:
        if (msg or {}).get("role") == "system":
            continue
        
        # Add required stop_reason field for assistant messages
        if msg.get("role") == "assistant" and "stop_reason" not in msg:
            msg = {**msg, "stop_reason": "end_of_turn"}
        
        filtered.append(msg)
    
    # If everything was filtered out, fall back to the original payload to avoid empty requests
    return filtered if filtered else messages


def _extract_attr(candidate: object, attr: str, default=None):
    if candidate is None:
        return default
    if isinstance(candidate, dict):
        return candidate.get(attr, default)
    value = getattr(candidate, attr, default)
    if callable(value):
        try:
            return value()
        except Exception:  # noqa: BLE001
            return default
    return value


def _normalize_violation(payload: object) -> Optional[object]:
    if payload is None:
        return None

    # Check violation_level first - "info" level indicates informational messages, not actual violations
    violation_level = _extract_attr(payload, "violation_level")
    if violation_level and str(violation_level).lower() in {"info", "informational"}:
        # For info-level messages, still check if there are actual violations
        pass  # Continue to status/summary checks below

    # Extract metadata (TrustyAI provider returns status/summary nested in metadata)
    metadata = _extract_attr(payload, "metadata")
    
    # Try to get status from metadata first, then fallback to top-level
    status_raw = _extract_attr(metadata, "status") if metadata else None
    if status_raw is None:
        status_raw = _extract_attr(payload, "status")
    
    status_value = None
    if isinstance(status_raw, str):
        status_value = status_raw.lower()
    elif hasattr(status_raw, "value"):
        status_value = str(status_raw.value).lower()
    elif status_raw is not None:
        status_value = str(status_raw).lower()
    if status_value in {"pass", "passed", "verified", "ok"}:
        return None

    # Try to get summary from metadata first, then fallback to top-level
    summary = _extract_attr(metadata, "summary") if metadata else None
    if summary is None:
        summary = _extract_attr(payload, "summary")
    
    if summary is not None:
        messages_with_violations = _extract_attr(summary, "messages_with_violations", 0)
        total_violations = _extract_attr(summary, "total_violations_found", 0)

        def _to_int(value):
            try:
                return int(value)
            except (TypeError, ValueError):
                return value

        if _to_int(messages_with_violations) in (0, "0") and _to_int(total_violations) in (0, "0"):
            return None

    return payload


def _run_guardrail(
    shield_id: str,
    messages: Iterable[dict],
) -> tuple[Optional[object], Optional[Exception]]:
    try:
        result = llama_stack_api.client.safety.run_shield(
            shield_id=shield_id,
            messages=_filter_guardrail_messages(list(messages)),
            params={},
        )
    except Exception as exc:  # noqa: BLE001
        return None, exc

    violation = getattr(result, "violation", None)
    return _normalize_violation(violation), None


def _guardrail_block_message(violation: object, shield_id: str) -> str:
    user_message = getattr(violation, "user_message", None)
    if not user_message:
        user_message = "Request blocked by guardrail."
    metadata = getattr(violation, "metadata", {}) or {}
    formatted_meta = "\n".join(f"- **{k}**: {v}" for k, v in metadata.items())
    details = f":shield: **{shield_id}**\n\n{user_message}"
    if formatted_meta:
        details += f"\n\n{formatted_meta}"
    return details


def rag_chat_page():
    st.title("🦙 RAG")

    def reset_agent_and_chat():
        st.session_state.clear()
        st.cache_resource.clear()

    def should_disable_input():
        return "displayed_messages" in st.session_state and len(st.session_state.displayed_messages) > 0

    with st.sidebar:
        # File/Directory Upload Section
        st.subheader("Upload Documents", divider=True)
        uploaded_files = st.file_uploader(
            "Upload file(s) or directory",
            accept_multiple_files=True,
            type=["txt", "pdf", "doc", "docx"],  # Add more file types as needed
        )
        # Process uploaded files
        if uploaded_files:
            st.success(f"Successfully uploaded {len(uploaded_files)} files")
            # Add memory bank name input field
            vector_db_name = st.text_input(
                "Document Collection Name",
                value="rag_vector_db",
                help="Enter a unique identifier for this document collection",
            )
            if st.button("Create Document Collection"):
                documents = [
                    RAGDocument(
                        document_id=uploaded_file.name,
                        content=data_url_from_file(uploaded_file),
                    )
                    for uploaded_file in uploaded_files
                ]

                providers = llama_stack_api.client.providers.list()
                vector_io_provider = next((x.provider_id for x in providers if x.api == "vector_io"), None)

                llama_stack_api.client.vector_dbs.register(
                    vector_db_id=vector_db_name,  # Use the user-provided name
                    embedding_dimension=384,
                    embedding_model="all-MiniLM-L6-v2",
                    provider_id=vector_io_provider,
                )

                # insert documents using the custom vector db name
                llama_stack_api.client.tool_runtime.rag_tool.insert(
                    vector_db_id=vector_db_name,  # Use the user-provided name
                    documents=documents,
                    chunk_size_in_tokens=512,
                )
                st.success("Vector database created successfully!")

        st.subheader("RAG Parameters", divider=True)

        rag_mode = st.radio(
            "RAG mode",
            ["Direct", "Agent-based"],
            captions=[
                "RAG is performed by directly retrieving the information and augmenting the user query",
                "RAG is performed by an agent activating a dedicated knowledge search tool.",
            ],
            on_change=reset_agent_and_chat,
            disabled=should_disable_input(),
        )

        # select memory banks
        vector_dbs = llama_stack_api.client.vector_dbs.list()
        vector_dbs = [_extract_vector_db_id(vector_db) for vector_db in vector_dbs]
        vector_dbs = [vector_db for vector_db in vector_dbs if vector_db]
        selected_vector_dbs = st.multiselect(
            label="Select Document Collections to use in RAG queries",
            options=vector_dbs,
            on_change=reset_agent_and_chat,
            disabled=should_disable_input(),
        )

        st.subheader("Guardrails", divider=True)
        shield_ids = _list_shield_ids()
        if not shield_ids:
            st.caption("No guardrails registered in Llama Stack.")
        guardrail_enabled = st.checkbox(
            "Enable guardrail",
            value=False,
            help="Run the selected TrustyAI shield before sending prompts to the model.",
        )
        selected_shield = st.selectbox(
            "Shield",
            options=shield_ids or ["regex_guardrail"],
            index=0,
            disabled=not guardrail_enabled,
        )
        guardrail_apply_to_context = st.checkbox(
            "Screen RAG augmented prompt",
            value=True,
            help="When enabled, both the initial user prompt and the RAG-augmented prompt are checked.",
            disabled=not guardrail_enabled,
        )
        guardrail_apply_to_response = st.checkbox(
            "Screen assistant responses",
            value=True,
            help="When enabled, the guardrail checks the model response before it is displayed.",
            disabled=not guardrail_enabled,
        )
        if guardrail_enabled:
            st.caption("Guardrail applies before executing the model call.")

        st.subheader("Inference Parameters", divider=True)
        available_models = llama_stack_api.client.models.list()
        available_models = [model.identifier for model in available_models if model.model_type == "llm"]
        selected_model = st.selectbox(
            label="Choose a model",
            options=available_models,
            index=0,
            on_change=reset_agent_and_chat,
            disabled=should_disable_input(),
        )
        system_prompt = st.text_area(
            "System Prompt",
            value="You are a helpful assistant. ",
            help="Initial instructions given to the AI to set its behavior and context",
            on_change=reset_agent_and_chat,
            disabled=should_disable_input(),
        )
        temperature = st.slider(
            "Temperature",
            min_value=0.0,
            max_value=1.0,
            value=0.0,
            step=0.1,
            help="Controls the randomness of the response. Higher values make the output more creative and unexpected, lower values make it more conservative and predictable",
            on_change=reset_agent_and_chat,
            disabled=should_disable_input(),
        )

        top_p = st.slider(
            "Top P",
            min_value=0.0,
            max_value=1.0,
            value=0.95,
            step=0.1,
            on_change=reset_agent_and_chat,
            disabled=should_disable_input(),
        )

        max_tokens = st.slider(
            "Max tokens",
            min_value=16,
            max_value=4096,
            value=768,
            step=16,
            help="Maximum number of tokens the assistant may generate per response.",
            on_change=reset_agent_and_chat,
            disabled=should_disable_input(),
        )

        st.subheader("Agent Tools", divider=True)
        # NOTE: database-mcp and slack-mcp are disabled (no SSE endpoint implementation)
        # enable_database_tool = st.checkbox(
        #     "Enable Database MCP (equipment data lookup)",
        #     value=True,
        #     help="Allow the agent to query ACME equipment metadata/service history via the PostgreSQL-backed MCP server.",
        #     on_change=reset_agent_and_chat,
        #     disabled=should_disable_input(),
        # )
        enable_openshift_tool = st.checkbox(
            "Enable OpenShift MCP (pods, logs, events)",
            value=True,
            help="Allow the agent to issue OpenShift MCP tool calls (list pods, get logs, list projects/events).",
            on_change=reset_agent_and_chat,
            disabled=should_disable_input(),
        )
        # enable_slack_tool = st.checkbox(
        #     "Enable Slack MCP (post updates)",
        #     value=False,
        #     help="Allow the agent to post short updates via the Slack MCP server.",
        #     on_change=reset_agent_and_chat,
        #     disabled=should_disable_input(),
        # )

        # Add clear chat button to sidebar
        if st.button("Clear Chat", use_container_width=True):
            reset_agent_and_chat()
            st.rerun()

    # Chat Interface
    if "messages" not in st.session_state:
        st.session_state.messages = []
    if "displayed_messages" not in st.session_state:
        st.session_state.displayed_messages = []

    # Display chat history
    for message in st.session_state.displayed_messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])

    if temperature > 0.0:
        strategy = {
            "type": "top_p",
            "temperature": temperature,
            "top_p": top_p,
        }
    else:
        strategy = {"type": "greedy"}

    agent_cache_key = json.dumps(
        {
            "model": selected_model,
            "system_prompt": system_prompt,
            "strategy": strategy,
            "vector_dbs": list(selected_vector_dbs),
            "enable_openshift_tool": enable_openshift_tool,
            "max_tokens": max_tokens,
        },
        sort_keys=True,
    )

    @st.cache_resource
    def create_agent(_cache_key: str):
        agent_tools = [
            dict(
                name="builtin::rag/knowledge_search",
                args={
                    "vector_db_ids": list(selected_vector_dbs),
                },
            )
        ]
        if enable_openshift_tool:
            agent_tools.append("mcp::openshift")

        # Llama Stack auto tool-choice is disabled in our cluster. Force the agent to use tools
        # whenever they are configured so we don't hit the server-side 400 requiring CLI flags.
        tool_config = {"tool_choice": "required"} if agent_tools else {"tool_choice": "none"}

        return Agent(
            llama_stack_api.client,
            model=selected_model,
            instructions=system_prompt,
            sampling_params={
                "strategy": strategy,
                "max_tokens": max_tokens,
            },
            tools=agent_tools,
            tool_config=tool_config,
        )

    agent = create_agent(agent_cache_key)

    if rag_mode == "Agent-based":
        if "agent_session_id" not in st.session_state:
            st.session_state["agent_session_id"] = agent.create_session(session_name=f"rag_demo_{uuid.uuid4()}")

        session_id = st.session_state["agent_session_id"]

    def agent_process_prompt(prompt):
        guardrail_violation = None
        guardrail_error = None
        if guardrail_enabled and selected_shield:
            guardrail_violation, guardrail_error = _run_guardrail(
                selected_shield,
                [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": prompt},
                ],
            )
        if guardrail_error:
            st.warning(f"Guardrail check failed: {guardrail_error}")
        if guardrail_violation:
            guardrail_message = _guardrail_block_message(guardrail_violation, selected_shield)
            st.session_state.messages.append({"role": "user", "content": prompt})
            st.session_state.displayed_messages.append({"role": "assistant", "content": guardrail_message})
            with st.chat_message("assistant"):
                st.markdown(guardrail_message)
            return

        st.session_state.messages.append({"role": "user", "content": prompt})

        # WORKAROUND: Agent.create_turn() is hard-coded to use tool_choice: "auto"
        # which causes vLLM 400 errors. Call the underlying agents API directly instead.
        turn_tool_config = {"tool_choice": "required"} if agent.agent_config.get("toolgroups") else {"tool_choice": "none"}
        
        response = llama_stack_api.client.agents.turn.create(
            agent_id=agent.agent_id,
            session_id=session_id,
            messages=[
                {
                    "role": "user",
                    "content": prompt,
                }
            ],
            tool_config=turn_tool_config,
            stream=True,
        )

        with st.chat_message("assistant"):
            retrieval_message_placeholder = st.empty()
            message_placeholder = st.empty()
            full_response = ""
            tool_event_outputs: list[str] = []
            for log in AgentEventLogger().log(response):
                log.print()
                if log.role == "tool_execution":
                    metadata = getattr(log, "metadata", {}) or {}
                    tool_name = getattr(log, "tool_name", None) or metadata.get("tool_name")
                    tool_output = log.content.replace("====", "").strip()
                    if tool_name:
                        tool_output = f"**{tool_name}**\n{tool_output}"
                    tool_event_outputs.append(tool_output)
                    retrieval_message_placeholder.info("\n\n".join(tool_event_outputs))
                else:
                    full_response += log.content
                    message_placeholder.markdown(full_response + "▌")

            post_guardrail_violation = None
            post_guardrail_error = None
            if guardrail_enabled and guardrail_apply_to_response and selected_shield:
                post_guardrail_violation, post_guardrail_error = _run_guardrail(
                    selected_shield,
                    [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": prompt},
                        {"role": "assistant", "content": full_response},
                    ],
                )
                if post_guardrail_error:
                    st.warning(f"Guardrail response check failed: {post_guardrail_error}")

            if post_guardrail_violation:
                guardrail_message = _guardrail_block_message(post_guardrail_violation, selected_shield)
                message_placeholder.markdown(guardrail_message)
                st.session_state.messages.append({"role": "assistant", "content": guardrail_message})
                st.session_state.displayed_messages.append({"role": "assistant", "content": guardrail_message})
            else:
                message_placeholder.markdown(full_response)
                st.session_state.messages.append({"role": "assistant", "content": full_response})
                st.session_state.displayed_messages.append({"role": "assistant", "content": full_response})

    def direct_process_prompt(prompt):
        if len(st.session_state.messages) == 0:
            st.session_state.messages.append({"role": "system", "content": system_prompt})

        if not selected_vector_dbs:
            st.warning("Select at least one document collection to run RAG.")
            return

        retrieved_chunks: List[dict] = []
        for vector_db_id in selected_vector_dbs:
            try:
                query_result = llama_stack_api.client.vector_io.query(
                    vector_db_id=vector_db_id,
                    query=prompt,
                    params={"top_k": 5},
                )
                for chunk, score in zip(query_result.chunks or [], query_result.scores or []):
                    chunk_text = getattr(chunk, "content", "") or ""
                    metadata = getattr(chunk, "metadata", {}) or {}
                    retrieved_chunks.append(
                        {
                            "vector_db": vector_db_id,
                            "score": score,
                            "content": chunk_text,
                            "metadata": metadata,
                        }
                    )
            except Exception as err:
                retrieved_chunks.append(
                    {
                        "vector_db": vector_db_id,
                        "score": None,
                        "content": f"⚠️ Retrieval failed: {err}",
                        "metadata": {},
                    }
                )

        deduped_chunks = _dedupe_chunks_by_document(retrieved_chunks)
        prompt_context = _format_retrieved_context(deduped_chunks)

        guardrail_violation = None
        guardrail_error = None
        if guardrail_enabled and selected_shield:
            pre_messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ]
            guardrail_violation, guardrail_error = _run_guardrail(selected_shield, pre_messages)
            if guardrail_violation is None and guardrail_apply_to_context:
                extended_prompt_preview = (
                    "Please answer the following query using the context below.\n\n"
                    f"CONTEXT:\n{prompt_context}\n\nQUERY:\n{prompt}"
                )
                guardrail_violation, guardrail_error = _run_guardrail(
                    selected_shield,
                    [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": extended_prompt_preview},
                    ],
                )

        if guardrail_error:
            st.warning(f"Guardrail check failed: {guardrail_error}")

        if guardrail_violation:
            guardrail_message = _guardrail_block_message(guardrail_violation, selected_shield)
            st.session_state.displayed_messages.append({"role": "assistant", "content": guardrail_message})
            with st.chat_message("assistant"):
                st.markdown(guardrail_message)
            return

        extended_prompt = (
            "Please answer the following query using the context below.\n\n"
            f"CONTEXT:\n{prompt_context}\n\nQUERY:\n{prompt}"
        )
        user_message = {"role": "user", "content": extended_prompt}
        conversation_messages = st.session_state.messages + [user_message]

        with st.chat_message("assistant"):
            retrieval_message_placeholder = st.empty()
            message_placeholder = st.empty()
            full_response = ""

            retrieval_message_placeholder.info(prompt_context)

            # Always stream responses, even with guardrails enabled
            # We'll stream the response, then check it afterwards
            response = llama_stack_api.client.inference.chat_completion(
                messages=conversation_messages,
                model_id=selected_model,
                sampling_params={
                    "strategy": strategy,
                    "max_tokens": max_tokens,
                },
                stream=True,
            )

            for chunk in response:
                response_delta = chunk.event.delta
                if isinstance(response_delta, ToolCallDelta):
                    retrieval_message_placeholder.info(
                        f"{prompt_context}\n\n{response_delta.tool_call.replace('====', '').strip()}"
                    )
                else:
                    full_response += chunk.event.delta.text
                    message_placeholder.markdown(full_response + "▌")
            message_placeholder.markdown(full_response)

            post_guardrail_violation = None
            post_guardrail_error = None
            if guardrail_enabled and guardrail_apply_to_response and selected_shield:
                post_guardrail_violation, post_guardrail_error = _run_guardrail(
                    selected_shield,
                    conversation_messages
                    + [
                        {
                            "role": "assistant",
                            "content": full_response,
                        }
                    ],
                )
                if post_guardrail_error:
                    st.warning(f"Guardrail response check failed: {post_guardrail_error}")

            if post_guardrail_violation:
                guardrail_message = _guardrail_block_message(post_guardrail_violation, selected_shield)
                message_placeholder.markdown(guardrail_message)
                st.session_state.messages.append(user_message)
                response_dict = {"role": "assistant", "content": guardrail_message, "stop_reason": "blocked"}
                st.session_state.messages.append(response_dict)
                st.session_state.displayed_messages.append(response_dict)
            else:
                message_placeholder.markdown(full_response)
                response_dict = {"role": "assistant", "content": full_response, "stop_reason": "end_of_message"}
                st.session_state.messages.extend([user_message, response_dict])
                st.session_state.displayed_messages.append(response_dict)

    if prompt := st.chat_input("Ask a question about your documents"):
        st.session_state.displayed_messages.append({"role": "user", "content": prompt})

        with st.chat_message("user"):
            st.markdown(prompt)

        st.session_state.prompt = prompt
        st.rerun()

    if "prompt" in st.session_state and st.session_state.prompt is not None:
        if rag_mode == "Agent-based":
            agent_process_prompt(st.session_state.prompt)
        else:  # rag_mode == "Direct"
            direct_process_prompt(st.session_state.prompt)
        st.session_state.prompt = None


rag_chat_page()

