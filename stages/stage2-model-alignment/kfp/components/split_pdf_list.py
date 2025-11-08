"""
Split a list of PDF URIs into balanced groups for parallel processing.

This mirrors the canonical Docling pipeline pattern that shards work into
`num_splits` chunks before fanning out with `dsl.ParallelFor`.
"""

from typing import List

from kfp import dsl

# Base container image aligned with other lightweight utilities
BASE_PYTHON_IMAGE = "registry.access.redhat.com/ubi9/python-311:1-77"


@dsl.component(base_image=BASE_PYTHON_IMAGE)
def split_pdf_list(pdf_uris: List[str], num_splits: int = 2) -> List[List[str]]:
    """
    Split a list of PDF URIs into roughly even groups.

    Args:
        pdf_uris: List of full S3 URIs to process.
        num_splits: Desired number of splits (defaults to 2).

    Returns:
        A list of lists, each containing a subset of the original URIs.
        Empty groups are filtered out.
    """
    if num_splits < 1:
        raise ValueError("num_splits must be >= 1")

    # Ensure deterministic ordering and remove duplicates while preserving order
    seen = set()
    ordered_uris = []
    for uri in pdf_uris:
        if uri not in seen:
            seen.add(uri)
            ordered_uris.append(uri)

    if not ordered_uris:
        return []

    splits = [ordered_uris[i::num_splits] for i in range(num_splits)]
    return [group for group in splits if group]


