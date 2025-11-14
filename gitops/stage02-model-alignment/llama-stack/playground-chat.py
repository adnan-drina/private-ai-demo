# Patched Streamlit chat page with optional TrustyAI guardrail integration.

from __future__ import annotations

from typing import Iterable, List, Optional

import streamlit as st

from llama_stack.distribution.ui.modules.api import llama_stack_api


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


# Sidebar configurations
with st.sidebar:
    st.header("Configuration")
    available_models = llama_stack_api.client.models.list()
    available_models = [model.identifier for model in available_models if model.model_type == "llm"]
    selected_model = st.selectbox(
        "Choose a model",
        available_models,
        index=0,
    )

    temperature = st.slider(
        "Temperature",
        min_value=0.0,
        max_value=1.0,
        value=0.0,
        step=0.1,
        help="Controls the randomness of the response. Higher values make the output more creative and unexpected, lower values make it more conservative and predictable",
    )

    top_p = st.slider(
        "Top P",
        min_value=0.0,
        max_value=1.0,
        value=0.95,
        step=0.1,
    )

    max_tokens = st.slider(
        "Max Tokens",
        min_value=0,
        max_value=4096,
        value=512,
        step=1,
        help="The maximum number of tokens to generate",
    )

    repetition_penalty = st.slider(
        "Repetition Penalty",
        min_value=1.0,
        max_value=2.0,
        value=1.0,
        step=0.1,
        help="Controls the likelihood for generating the same word or phrase multiple times in the same sentence or paragraph. 1 implies no penalty, 2 will strongly discourage model to repeat words or phrases.",
    )

    stream = st.checkbox("Stream", value=True)
    system_prompt = st.text_area(
        "System Prompt",
        value="You are a helpful AI assistant.",
        help="Initial instructions given to the AI to set its behavior and context",
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
    guardrail_apply_to_response = st.checkbox(
        "Screen assistant responses",
        value=True,
        help="When enabled, the guardrail checks the model response before it is displayed.",
        disabled=not guardrail_enabled,
    )
    if guardrail_enabled:
        st.caption("Requests blocked by the shield will not be sent to the model.")

    # Add clear chat button to sidebar
    if st.button("Clear Chat", use_container_width=True):
        st.session_state.messages = []
        st.rerun()


# Main chat interface
st.title("🦙 Chat")


# Initialize chat history
if "messages" not in st.session_state:
    st.session_state.messages = []

# Display chat messages
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])


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


# Chat input
if prompt := st.chat_input("Example: What is Llama Stack?"):
    # Add user message to chat history
    st.session_state.messages.append({"role": "user", "content": prompt})

    # Display user message
    with st.chat_message("user"):
        st.markdown(prompt)

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
        with st.chat_message("assistant"):
            st.markdown(guardrail_message)
        st.session_state.messages.append({"role": "assistant", "content": guardrail_message})
    else:
        # Display assistant response
        with st.chat_message("assistant"):
            message_placeholder = st.empty()
            full_response = ""

            if temperature > 0.0:
                strategy = {
                    "type": "top_p",
                    "temperature": temperature,
                    "top_p": top_p,
                }
            else:
                strategy = {"type": "greedy"}

            # Always use user's streaming preference, even with guardrails enabled
            # We'll stream the response, then check it afterwards
            response = llama_stack_api.client.inference.chat_completion(
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": prompt},
                ],
                model_id=selected_model,
                stream=stream,
                sampling_params={
                    "strategy": strategy,
                    "max_tokens": max_tokens,
                    "repetition_penalty": repetition_penalty,
                },
            )

            if stream:
                for chunk in response:
                    if chunk.event.event_type == "progress":
                        full_response += chunk.event.delta.text
                    message_placeholder.markdown(full_response + "▌")
                message_placeholder.markdown(full_response)
            else:
                full_response = response.completion_message.content

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
            else:
                message_placeholder.markdown(full_response)
                st.session_state.messages.append({"role": "assistant", "content": full_response})

