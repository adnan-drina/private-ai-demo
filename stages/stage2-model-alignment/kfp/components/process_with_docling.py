"""
Process PDF with Docling to extract markdown

This component uses Docling's async API for robust long-running document conversion.
Workflow: submit → poll → fetch result
"""

from kfp import dsl
from kfp.dsl import Dataset, Output, Input

# Base container images
# Pinned to specific version for reproducibility (per KFP best practices)
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:1-77"


@dsl.component(
    base_image=BASE_PYTHON_IMAGE,
    packages_to_install=["requests"]
)
def process_with_docling(
    input_file: Input[Dataset],
    docling_url: str,
    output_markdown: Output[Dataset]
):
    """
    Process document with Docling to extract markdown (asynchronous API)
    
    Uses /v1/convert/file/async endpoint for robust long-running conversions.
    This avoids server-side timeout issues (DOCLING_SERVE_MAX_SYNC_WAIT default 120s).
    
    Workflow:
    1. Submit job to /v1/convert/file/async
    2. Poll /v1/status/poll/{task_id} until completion
    3. Fetch result from /v1/result/{task_id}
    
    Reference: https://github.com/docling-project/docling-serve/blob/main/docs/usage.md
    Reference: https://github.com/docling-project/docling-serve/blob/main/docs/configuration.md
    """
    import requests
    import time
    import os
    
    print(f"Processing document with Docling (async): {docling_url}")
    
    # Read input file and get filename
    filename = os.path.basename(input_file.path)
    if not filename.endswith('.pdf'):
        filename = 'document.pdf'
    
    file_size = os.path.getsize(input_file.path)
    print(f"Converting document: {filename} ({file_size / 1024 / 1024:.2f} MB)")
    
    # Step 1: Submit async job
    print(f"Submitting to /v1/convert/file/async...")
    
    with open(input_file.path, "rb") as f:
        files = {"files": (filename, f, "application/pdf")}
        
        response = requests.post(
            f"{docling_url}/v1/convert/file/async",
            files=files,
            data={"to_formats": "md"},
            timeout=30  # Short timeout for submission only
        )
        response.raise_for_status()
    
    task = response.json()
    task_id = task["task_id"]
    print(f"[OK] Task submitted: {task_id}")
    print(f"    Initial status: {task.get('task_status', 'unknown')}")
    
    # Step 2: Poll for completion
    print(f"Polling for completion...")
    poll_count = 0
    max_polls = 360  # 30 minutes with 5s intervals
    
    while task.get("task_status") not in ("success", "failure"):
        time.sleep(5)
        poll_count += 1
        
        response = requests.get(
            f"{docling_url}/v1/status/poll/{task_id}",
            timeout=10
        )
        response.raise_for_status()
        task = response.json()
        
        if poll_count % 12 == 0:  # Log every minute
            print(f"  Check {poll_count}: {task.get('task_status')} (position: {task.get('task_position', 'N/A')})")
        
        if poll_count >= max_polls:
            raise TimeoutError(f"Task {task_id} did not complete within 30 minutes")
    
    final_status = task.get("task_status")
    print(f"[OK] Task completed with status: {final_status}")
    
    if final_status != "success":
        raise RuntimeError(f"Docling task failed: {task}")
    
    # Step 3: Fetch result
    print(f"Fetching result from /v1/result/{task_id}...")
    response = requests.get(
        f"{docling_url}/v1/result/{task_id}",
        timeout=30
    )
    response.raise_for_status()
    
    print(f"[OK] Result fetched")
    
    # Parse response
    result = response.json()
    
    # Log response structure for debugging
    print(f"Response keys: {list(result.keys())}")
    
    # Extract markdown content from response
    # Try different response formats Docling might return
    if "markdown" in result:
        # Format 1: Direct markdown field
        markdown_content = result["markdown"]
    elif "documents" in result and len(result["documents"]) > 0:
        # Format 2: Documents array with markdown
        doc = result["documents"][0]
        if isinstance(doc, dict) and "markdown" in doc:
            markdown_content = doc["markdown"]
        elif isinstance(doc, dict) and "md_content" in doc:
            markdown_content = doc["md_content"]
        else:
            markdown_content = str(doc)
    elif "document" in result:
        # Format 3: Single document object with md_content
        doc = result["document"]
        if isinstance(doc, dict):
            markdown_content = doc.get("md_content", doc.get("markdown", str(doc)))
        else:
            markdown_content = str(doc)
    elif "content" in result:
        # Format 4: Direct content field
        markdown_content = result["content"]
    else:
        # Fallback: stringify result and warn
        markdown_content = str(result)
        print(f"WARNING: Unexpected response format, stringifying result!")
        print(f"Response keys: {list(result.keys())}")
        print(f"Sample: {str(result)[:500]}")
    
    # Write markdown output
    with open(output_markdown.path, "w") as f:
        f.write(markdown_content)
    
    print(f"[OK] Extracted {len(markdown_content)} characters of markdown")
    print(f"Preview: {markdown_content[:200]}...")

