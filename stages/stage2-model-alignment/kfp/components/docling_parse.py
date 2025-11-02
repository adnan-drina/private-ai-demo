from typing import Optional

from kfp.dsl import component, Output, Dataset


@component(
    base_image="registry.access.redhat.com/ubi9/python-311:1-77",
    packages_to_install=[
        "requests==2.32.3",
        "boto3==1.34.162",
    ],
)
def docling_parse_op(
    input_uri: str,
    docling_url: str = "http://shared-docling-service.ai-infrastructure.svc:5001",
    poll_seconds: int = 5,
    max_polls: int = 60,
    out_markdown: Output[Dataset] = None,
    out_json: Output[Dataset] = None,
):
    """
    Parse a document using the DoclingServe HTTP API and emit Markdown + JSON artifacts.

    - input_uri: s3://bucket/key or /path/to/file
    - docling_url: base URL of DoclingServe
    - Emits:
        - out_markdown: extracted markdown content
        - out_json: full DoclingServe JSON response
    """
    import os
    import time
    import json
    import tempfile
    import urllib.parse
    import requests

    def download_if_s3(uri: str) -> str:
        if uri.startswith("s3://"):
            import boto3

            parsed = urllib.parse.urlparse(uri)
            bucket = parsed.netloc
            key = parsed.path.lstrip("/")
            s3 = boto3.client("s3")
            fd, tmp_path = tempfile.mkstemp(suffix=os.path.splitext(key)[1] or ".bin")
            os.close(fd)
            s3.download_file(bucket, key, tmp_path)
            return tmp_path
        return uri

    def submit_docling(file_path: str) -> str:
        url = f"{docling_url}/v1/convert/file/async"
        with open(file_path, "rb") as f:
            files = {"files": (os.path.basename(file_path), f)}
            resp = requests.post(url, files=files, timeout=60)
            resp.raise_for_status()
            data = resp.json()
            task_id = data.get("task_id")
            if not task_id:
                raise RuntimeError(f"Docling response missing task_id: {data}")
            return task_id

    def poll_result(task_id: str) -> dict:
        url = f"{docling_url}/v1/result/{task_id}"
        for i in range(max_polls):
            r = requests.get(url, timeout=30)
            r.raise_for_status()
            data = r.json()
            status = data.get("status")
            if status == "success":
                return data
            if status == "failed":
                raise RuntimeError(f"Docling processing failed: {data}")
            time.sleep(poll_seconds)
        raise TimeoutError("Timeout waiting for Docling result")

    local_path = download_if_s3(input_uri)
    task_id = submit_docling(local_path)
    result = poll_result(task_id)

    # Write full JSON
    with open(out_json.path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    # Extract markdown content
    md_content = result.get("md_content") or ""
    with open(out_markdown.path, "w", encoding="utf-8") as f:
        f.write(md_content)

    print("✅ Docling parse complete")
    print(f"  Markdown: {out_markdown.path}")
    print(f"  JSON: {out_json.path}")


