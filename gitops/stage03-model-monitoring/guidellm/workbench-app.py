
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
import streamlit.components.v1 as components
from html import escape
from textwrap import dedent

try:  # Optional dependency for MinIO integration
    import boto3
    from botocore.client import Config as BotoConfig
except ImportError:  # pragma: no cover
    boto3 = None
    BotoConfig = None

APP_ROOT = Path(__file__).resolve().parent
PROFILES_PATHS = [
    APP_ROOT / "profiles" / "profiles.json",
    Path("/app/profiles/profiles.json"),
    Path("/opt/app-root/src/profiles/profiles.json"),
]
RESULTS_ROOT = Path("/opt/app-root/src/results")
RESULTS_ROOT.mkdir(parents=True, exist_ok=True)

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT")
MINIO_BUCKET = os.getenv("MINIO_BUCKET", "guidellm-results")
MINIO_REGION = os.getenv("MINIO_REGION", "us-east-1")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY_ID")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_ACCESS_KEY")
MINIO_USE_SSL = os.getenv("MINIO_USE_SSL", "false").lower() == "true"

LOG_MAX_LINES = 500


def _select_metric_section(metric: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(metric, dict):
        return None
    section = metric.get("total")
    if isinstance(section, dict):
        return section
    section = metric.get("successful")
    if isinstance(section, dict):
        return section
    return metric if isinstance(metric, dict) else None


def _metric_value(metrics: Dict[str, Any], key: str, percentile: Optional[str] = None, scale: float = 1.0) -> Optional[float]:
    metric = metrics.get(key)
    section = _select_metric_section(metric)
    if not section:
        return None
    value: Optional[Any] = None
    if percentile:
        percentiles = section.get("percentiles")
        if isinstance(percentiles, dict):
            value = percentiles.get(percentile)
        if value is None:
            value = section.get(percentile)
    if value is None:
        value = section.get("mean")
    if value is None:
        return None
    try:
        return float(value) * scale
    except (TypeError, ValueError):
        return None


def _success_rate(metrics: Dict[str, Any]) -> Optional[float]:
    metric = metrics.get("requests_per_second")
    if not isinstance(metric, dict):
        return None
    total = metric.get("total")
    success = metric.get("successful")
    if isinstance(total, dict) and isinstance(success, dict):
        total_count = total.get("count")
        success_count = success.get("count")
        if isinstance(total_count, (int, float)) and total_count:
            return float(success_count or 0) / float(total_count) * 100.0
    return None


def _total_requests(metrics: Dict[str, Any]) -> Optional[int]:
    for key in ("request_latency", "requests_per_second"):
        metric = metrics.get(key)
        section = _select_metric_section(metric)
        if isinstance(section, dict):
            count = section.get("count")
            if isinstance(count, (int, float)):
                return int(count)
    return None


def _format_value(value: Optional[float], decimals: int = 4, suffix: str = "") -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.{decimals}f}{suffix}"
    if isinstance(value, int):
        return f"{value}{suffix}"
    try:
        return f"{float(value):.{decimals}f}{suffix}"
    except Exception:  # pragma: no cover - defensive
        return f"{value}{suffix}"


def build_metric_summary(metrics: Dict[str, Any]) -> List[Dict[str, str]]:
    token_rate = _metric_value(metrics, "tokens_per_second") or _metric_value(metrics, "output_tokens_per_second")
    rows = [
        ("P50 request latency (s)", _format_value(_metric_value(metrics, "request_latency", "p50"))),
        ("P95 request latency (s)", _format_value(_metric_value(metrics, "request_latency", "p95"))),
        ("P99 request latency (s)", _format_value(_metric_value(metrics, "request_latency", "p99"))),
        ("P50 time to first token (s)", _format_value(_metric_value(metrics, "time_to_first_token_ms", "p50", scale=0.001))),
        ("P95 time to first token (s)", _format_value(_metric_value(metrics, "time_to_first_token_ms", "p95", scale=0.001))),
        ("Requests per second", _format_value(_metric_value(metrics, "requests_per_second"))),
        ("Tokens per second", _format_value(token_rate)),
        ("Request success rate (%)", _format_value(_success_rate(metrics), decimals=2)),
        ("Total requests", _format_value(_total_requests(metrics), decimals=0)),
    ]
    return [{"Metric": label, "Value": value} for label, value in rows]


def write_html_report(
    destination: Path,
    model: str,
    bench_type: str,
    timestamp: str,
    summary_rows: List[Dict[str, str]],
    payload: Dict[str, Any],
) -> None:
    rows_html = "".join(
        f"<tr><th>{escape(row['Metric'])}</th><td>{escape(row['Value'])}</td></tr>" for row in summary_rows
    )
    timestamp_display = timestamp or datetime.utcnow().strftime("%Y-%m-%d %H:%M:%SZ")
    html_doc = dedent(
        f"""
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <title>GuideLLM Benchmark Report - {escape(model)}</title>
            <style>
              body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 2rem; }}
              h1 {{ margin-bottom: 0.5rem; }}
              table {{ border-collapse: collapse; margin-top: 1.5rem; width: 100%; max-width: 640px; }}
              th, td {{ border: 1px solid #444; padding: 0.4rem 0.6rem; text-align: left; }}
              th {{ background: #f0f0f0; width: 60%; }}
              pre {{ background: #f8f8f8; padding: 1rem; overflow-x: auto; }}
              footer {{ margin-top: 2rem; font-size: 0.85rem; color: #666; }}
            </style>
          </head>
          <body>
            <h1>GuideLLM Benchmark Report</h1>
            <p><strong>Model:</strong> {escape(model)}</p>
            <p><strong>Benchmark Type:</strong> {escape(bench_type)}</p>
            <p><strong>Timestamp:</strong> {escape(timestamp_display)}</p>
            <table>
              <tbody>
                {rows_html}
              </tbody>
            </table>
            <h2>Raw Benchmark Payload</h2>
            <pre>{escape(json.dumps(payload, indent=2))}</pre>
            <footer>Generated automatically by the GuideLLM workbench.</footer>
          </body>
        </html>
        """
    )
    destination.write_text(html_doc, encoding="utf-8")


def _s3_client():
    if not (boto3 and BotoConfig and MINIO_ENDPOINT and MINIO_ACCESS_KEY and MINIO_SECRET_KEY):
        return None
    try:
        return boto3.client(
            "s3",
            endpoint_url=MINIO_ENDPOINT,
            aws_access_key_id=MINIO_ACCESS_KEY,
            aws_secret_access_key=MINIO_SECRET_KEY,
            region_name=MINIO_REGION,
            use_ssl=MINIO_USE_SSL,
            config=BotoConfig(signature_version="s3v4"),
        )
    except Exception as exc:  # pragma: no cover - defensive
        st.warning(f"Unable to initialise MinIO client: {exc}")
        return None


def _list_minio_html(prefix: str = "") -> List[str]:
    client = _s3_client()
    if not client:
        return []
    paginator = client.get_paginator("list_objects_v2")
    keys: List[str] = []
    try:
        for page in paginator.paginate(Bucket=MINIO_BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj.get("Key")
                if key and key.endswith(".html"):
                    keys.append(key)
    except Exception as exc:
        st.warning(f"Unable to list MinIO objects: {exc}")
        return []
    return sorted(keys, reverse=True)


def _fetch_minio_html(key: str) -> Optional[str]:
    client = _s3_client()
    if not client:
        return None
    try:
        response = client.get_object(Bucket=MINIO_BUCKET, Key=key)
        body = response.get("Body")
        if body:
            return body.read().decode("utf-8")
    except Exception as exc:
        st.warning(f"Unable to download {key}: {exc}")
    return None


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

    if MINIO_ENDPOINT and not boto3:
        st.warning("MinIO credentials detected but boto3 is not available in the workbench image.")


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
                value="\n".join(log_cache[-200:]),
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

    summary_rows: Optional[List[Dict[str, str]]] = None
    report_path: Optional[Path] = None
    if payload:
        benchmarks = payload.get("benchmarks") or []
        metrics = benchmarks[0].get("metrics") if benchmarks else None
        if isinstance(metrics, dict):
            summary_rows = build_metric_summary(metrics)
            report_path = run_dir / "benchmark.html"
            write_html_report(
                report_path,
                model_name or "unknown",
                "workbench",
                timestamp,
                summary_rows,
                payload,
            )

    st.success("Benchmark completed successfully")
    if summary_rows:
        st.markdown("#### Summary")
        st.table(summary_rows)
        if report_path and report_path.exists():
            report_contents = report_path.read_text(encoding="utf-8")
            st.download_button(
                "Download HTML report",
                data=report_contents,
                file_name=report_path.name,
                mime="text/html",
            )
            with st.expander("Preview HTML report", expanded=False):
                components.html(report_contents, height=420, scrolling=True)

    return {
        "success": True,
        "timestamp": timestamp,
        "run_dir": str(run_dir),
        "output": payload,
        "log": log_lines,
        "output_path": str(output_path),
        "summary": summary_rows,
        "report_path": str(report_path) if report_path else None,
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
            summary_rows = entry.get("summary")
            if summary_rows:
                st.table(summary_rows)
                report_path_str = entry.get("report_path")
                if report_path_str:
                    report_path = Path(report_path_str)
                    if report_path.exists():
                        report_contents = report_path.read_text(encoding="utf-8")
                        st.download_button(
                            "Download HTML report",
                            data=report_contents,
                            file_name=report_path.name,
                            mime="text/html",
                            key=f"download-{report_path.name}",
                        )
                        with st.expander("Preview HTML report", expanded=False):
                            components.html(report_contents, height=420, scrolling=True)
            if entry.get("output"):
                with st.expander("Benchmark payload", expanded=False):
                    st.json(entry["output"])
            with st.expander("View log", expanded=False):
                st.text("\n".join(entry.get("log", [])))
            st.markdown("---")

    s3_client_available = _s3_client() is not None
    if s3_client_available:
        st.subheader("MinIO HTML reports")
        default_prefix = st.session_state.get("minio_prefix", "")
        prefix = st.text_input("Prefix filter", value=default_prefix, key="minio_prefix")
        refresh = st.button("Refresh MinIO listing")
        if refresh or "minio_objects" not in st.session_state or prefix != default_prefix:
            st.session_state["minio_objects"] = _list_minio_html(prefix)
        objects = st.session_state.get("minio_objects", [])
        if not objects:
            st.info("No HTML reports found in MinIO for the current filter")
        else:
            selected = st.selectbox("Available reports", options=objects, key="minio_selected")
            if selected:
                html_content = _fetch_minio_html(selected)
                if html_content:
                    st.download_button(
                        "Download selected report",
                        data=html_content,
                        file_name=Path(selected).name,
                        mime="text/html",
                        key=f"download-minio-{selected}",
                    )
                    with st.expander("Preview selected report", expanded=True):
                        components.html(html_content, height=420, scrolling=True)
                else:
                    st.warning("Unable to load selected report from MinIO")

