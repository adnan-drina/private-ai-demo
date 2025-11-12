
#!/usr/bin/env python3

"""GuideLLM Streamlit workbench with profile selector.

This app exposes two usage modes:
- quickly launch GuideLLM benchmarks against the predefined profiles that ship
  via the `guidellm-profiles` ConfigMap (Full 24B, Quantized 24B)
- allow ad-hoc tweaking of the request parameters before launching the
  benchmark.

The UI intentionally keeps the layout compact while still mirroring the
defaults used by the automation (Tekton task / CronJobs). Live output is
streamed into the page and persisted to a local log file so that refreshes do
not lose context.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import streamlit as st

APP_ROOT = Path(__file__).resolve().parent
PROFILES_PATHS = [
    APP_ROOT / "profiles" / "profiles.json",
    Path("/app/profiles/profiles.json"),
    Path("/opt/app-root/src/profiles/profiles.json"),
]
RESULTS_ROOT = Path("/opt/app-root/src/results")
RESULTS_ROOT.mkdir(parents=True, exist_ok=True)

LOG_MAX_LINES = 500


def load_profiles() -> List[Dict[str, Any]]:
    for path in PROFILES_PATHS:
        if path.exists():
            try:
                with path.open("r", encoding="utf-8") as fh:
                    data = json.load(fh)
                if isinstance(data, list):
                    return data
            except json.JSONDecodeError as exc:
                st.warning(f"Unable to parse profiles from {path}: {exc}")
    return []


def ensure_state_defaults(profile: Dict[str, Any]) -> None:
    defaults = {
        "target_input": profile.get("target", ""),
        "model_input": profile.get("model", ""),
        "processor_input": profile.get("processor", ""),
        "rate_type_select": profile.get("rate_type", "synchronous"),
        "rate_input": str(profile.get("rate", "")),
        "max_seconds_input": int(profile.get("max_seconds", 900)),
        "max_requests_input": int(profile.get("max_requests", 500)),
        "max_concurrency_input": int(profile.get("max_concurrency", 16)),
        "prompt_tokens_input": int(profile.get("prompt_tokens", 256)),
        "output_tokens_input": int(profile.get("output_tokens", 128)),
        "samples_input": int(profile.get("samples", 100)),
        "data_type_select": profile.get("data_type", "emulated"),
    }
    for key, value in defaults.items():
        st.session_state[key] = value


st.set_page_config(
    page_title="GuideLLM Benchmark Workbench",
    page_icon="🚀",
    layout="wide",
)

st.title("🚀 GuideLLM Benchmark Workbench")
st.caption("Launch GuideLLM benchmarks against the canonical Mistral endpoints")

profiles = load_profiles()
profile_map = {profile["name"]: profile for profile in profiles if profile.get("name")}
profile_names = list(profile_map.keys())

if profile_names:
    if "profile_select" not in st.session_state:
        st.session_state.profile_select = profile_names[0]
        ensure_state_defaults(profile_map[profile_names[0]])
else:
    st.info("No predefined profiles detected; manual configuration only")


def on_profile_change() -> None:
    profile = profile_map.get(st.session_state.profile_select)
    if profile:
        ensure_state_defaults(profile)


with st.sidebar:
    st.header("Configuration")
    if profile_names:
        st.selectbox(
            "Benchmark Profile",
            options=profile_names,
            key="profile_select",
            on_change=on_profile_change,
        )
        st.markdown("---")

    target = st.text_input("Target Endpoint", key="target_input")
    model_name = st.text_input("Model", key="model_input")
    processor = st.text_input("Processor", key="processor_input")

    rate_type = st.selectbox(
        "Rate Type",
        ["synchronous", "throughput", "constant", "poisson", "sweep"],
        key="rate_type_select",
    )
    rate_raw = st.text_input("Rate", key="rate_input")

    max_seconds = st.number_input(
        "Max Duration (s)",
        min_value=10,
        max_value=3600,
        key="max_seconds_input",
    )
    max_requests = st.number_input(
        "Max Requests",
        min_value=1,
        max_value=10000,
        key="max_requests_input",
    )
    max_concurrency = st.number_input(
        "Max Concurrency",
        min_value=1,
        max_value=128,
        key="max_concurrency_input",
    )

    prompt_tokens = st.number_input(
        "Prompt Tokens",
        min_value=1,
        max_value=4096,
        key="prompt_tokens_input",
    )
    output_tokens = st.number_input(
        "Output Tokens",
        min_value=1,
        max_value=2048,
        key="output_tokens_input",
    )
    samples = st.number_input(
        "Samples",
        min_value=1,
        max_value=2000,
        key="samples_input",
    )

    api_key = st.text_input("OpenAI-compatible API key", type="password")
    hf_token = st.text_input("Hugging Face token", type="password")

    st.markdown("---")
    data_config = f"prompt_tokens={prompt_tokens},output_tokens={output_tokens},samples={samples}"
    st.text_input("Data config", data_config, key="data_config_preview", disabled=True)


col_main, col_meta = st.columns([3, 1])


def normalize_rate(rate_value: str, rate_type_value: str) -> Tuple[str, Optional[str]]:
    text = str(rate_value).strip()
    if not text:
        return "", None
    if rate_type_value.lower() != "sweep":
        return text, None
    if ":" not in text:
        return text, None
    parts = text.split(":", 3)
    if len(parts) != 3:
        return text, None
    try:
        start, end, step = (float(part) for part in parts)
    except ValueError:
        return text, None
    if step <= 0 or end < start:
        return text, None
    steps = int(round((end - start) / step)) + 1
    if steps < 1:
        steps = 1
    sweep_total = steps + 2
    message = (
        f"Sweep will execute {sweep_total} runs: 1 synchronous baseline, "
        f"1 throughput baseline, {steps} constant-rate checkpoints."
    )
    return str(sweep_total), message


with col_meta:
    st.subheader("Summary")
    rate_arg, sweep_message = normalize_rate(rate_raw, rate_type)
    if sweep_message:
        st.info(sweep_message)

    st.metric("Max seconds", int(max_seconds))
    st.metric("Max requests", int(max_requests))
    st.metric("Concurrency", int(max_concurrency))
    st.metric("Prompt tokens", int(prompt_tokens))
    st.metric("Output tokens", int(output_tokens))
    st.metric("Samples", int(samples))

    st.markdown("---")
    st.caption("Environment overrides")
    env_table = {
        "GUIDELLM__OPENAI__VERIFY": os.getenv("GUIDELLM__OPENAI__VERIFY", "false"),
        "PYTHONHTTPSVERIFY": os.getenv("PYTHONHTTPSVERIFY", "0"),
    }
    st.json(env_table)


history = st.session_state.setdefault("result_history", [])
log_cache: List[str] = st.session_state.setdefault("log_cache", [])


def run_benchmark() -> Optional[Dict[str, Any]]:
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    run_dir = RESULTS_ROOT / f"{model_name}_{timestamp}"
    run_dir.mkdir(parents=True, exist_ok=True)

    output_path = run_dir / "benchmark.json"
    log_path = run_dir / "benchmark.log"

    cmd = [
        "guidellm",
        "benchmark",
        "--target",
        target,
        "--model",
        model_name,
        "--backend-type",
        "openai_http",
        "--processor",
        processor,
        "--data",
        data_config,
        "--output-path",
        str(output_path),
        "--rate-type",
        rate_type,
        "--max-seconds",
        str(int(max_seconds)),
        "--max-requests",
        str(int(max_requests)),
    ]
    if rate_type.lower() != "throughput" and rate_arg:
        cmd.extend(["--rate", rate_arg])

    env = os.environ.copy()
    env.setdefault("HOME", "/tmp")
    env.setdefault("HF_HOME", "/tmp/hf")
    Path(env["HF_HOME"]).mkdir(parents=True, exist_ok=True)

    env["GUIDELLM__OPENAI__VERIFY"] = env.get("GUIDELLM__OPENAI__VERIFY", "false")
    env["PYTHONHTTPSVERIFY"] = "0"
    env["GUIDELLM__MAX_CONCURRENCY"] = str(int(max_concurrency))

    for noisy in ("REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "SSL_CERT_FILE"):
        env.pop(noisy, None)

    if api_key:
        env["GUIDELLM__OPENAI__API_KEY"] = api_key
    if hf_token:
        env["HUGGING_FACE_HUB_TOKEN"] = hf_token

    friendly_cmd = " ".join(shlex.quote(part) for part in cmd)
    st.code(friendly_cmd, language="bash")

    placeholder = st.empty()
    progress_placeholder = st.progress(0.0)
    status_placeholder = st.empty()

    log_lines: List[str] = []
    start_time = time.time()

    with log_path.open("w", encoding="utf-8") as log_file:
        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=env,
                text=True,
                bufsize=1,
            )
        except FileNotFoundError:
            st.error("guidellm CLI not available in PATH")
            return None

        assert proc.stdout is not None
        while True:
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                time.sleep(0.1)
                continue
            log_file.write(line)
            log_file.flush()
            log_lines.append(line.rstrip())
            log_cache.append(line.rstrip())
            if len(log_cache) > LOG_MAX_LINES:
                del log_cache[:-LOG_MAX_LINES]
            placeholder.text_area(
                "Console output",
                value="
".join(log_cache[-200:]),
                height=320,
            )
            elapsed = time.time() - start_time
            status_placeholder.text(f"Runtime: {elapsed:0.1f}s")
            progress_placeholder.progress(min(elapsed / float(max_seconds), 1.0))

        proc.wait()
        progress_placeholder.empty()
        status_placeholder.empty()

    if proc.returncode != 0:
        st.error(f"Benchmark failed (exit code {proc.returncode})")
        return {
            "success": False,
            "timestamp": timestamp,
            "run_dir": str(run_dir),
            "log": log_lines,
        }

    if not output_path.exists():
        st.warning("Benchmark completed but no output artifact was generated")
        return {
            "success": False,
            "timestamp": timestamp,
            "run_dir": str(run_dir),
            "log": log_lines,
        }

    try:
        payload = json.loads(output_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        st.warning(f"Unable to parse benchmark output: {exc}")
        payload = None

    st.success("Benchmark completed successfully")
    return {
        "success": True,
        "timestamp": timestamp,
        "run_dir": str(run_dir),
        "output": payload,
        "log": log_lines,
        "output_path": str(output_path),
    }


with col_main:
    st.subheader("Launch benchmark")
    config_preview = {
        "target": target,
        "model": model_name,
        "processor": processor,
        "rate_type": rate_type,
        "rate": rate_arg or rate_raw,
        "max_seconds": int(max_seconds),
        "max_requests": int(max_requests),
        "max_concurrency": int(max_concurrency),
        "data": data_config,
    }
    st.json(config_preview)

    run_clicked = st.button("Run benchmark", type="primary")
    if run_clicked:
        if not target or not model_name:
            st.error("Target and model are required")
        else:
            result = run_benchmark()
            if result:
                history.append(result)
                st.session_state.result_history = history

    if history:
        st.markdown("---")
        st.subheader("Previous runs")
        for entry in reversed(history[-5:]):
            status = "✅" if entry.get("success") else "❌"
            st.markdown(
                f"{status} **{entry.get('timestamp')}** — {entry.get('run_dir')}"
            )
            if entry.get("output"):
                st.json(entry["output"])
            with st.expander("View log", expanded=False):
                st.text("
".join(entry.get("log", [])))
            st.markdown("---")

