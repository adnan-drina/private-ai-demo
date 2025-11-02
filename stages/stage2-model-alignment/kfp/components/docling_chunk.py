from typing import List

from kfp.dsl import component, Input, Output, Dataset


@component(
    base_image="registry.access.redhat.com/ubi9/python-311:1-77",
)
def docling_chunk_op(
    in_markdown: Input[Dataset],
    chunk_size: int = 512,
    chunk_overlap: int = 50,
    out_chunks: Output[Dataset] = None,
):
    """
    Chunk Markdown text into overlapping windows and emit JSONL with metadata.
    - Preserves simple metadata fields (article/page heuristics) similar to Tekton task.
    - Limits content length to ~60KB per chunk to fit Milvus constraints.
    """
    import json
    import re

    def simple_tokenize(text: str) -> List[str]:
        return text.split()

    def chunk_text(text: str, size: int, overlap: int) -> List[str]:
        tokens = simple_tokenize(text)
        chunks = []
        start = 0
        while start < len(tokens):
            end = start + size
            section = " ".join(tokens[start:end])
            chunks.append(section)
            start = end - overlap
            if start >= len(tokens):
                break
        return chunks

    def extract_article_id(text: str):
        m = re.search(r"Art\.\s*\d+", text)
        return m.group(0) if m else None

    def extract_page_number(text: str):
        m = re.search(r"page\s*(\d+)", text, re.IGNORECASE)
        return int(m.group(1)) if m else None

    with open(in_markdown.path, "r", encoding="utf-8") as f:
        md = f.read()

    pieces = chunk_text(md, chunk_size, chunk_overlap)
    total = 0
    with open(out_chunks.path, "w", encoding="utf-8") as out:
        for i, piece in enumerate(pieces):
            # Truncate to ~60KB to keep within Milvus limits
            if len(piece) > 60000:
                piece = piece[:60000] + "... [truncated]"
            article = extract_article_id(piece)
            page = extract_page_number(piece)
            rec = {
                "chunk_id": f"doc-chunk-{i:05d}",
                "content": piece,
                "chunk_index": i,
                "article": article,
                "page": page,
                "section_type": "operative",
                "token_count": len(simple_tokenize(piece)),
            }
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            total += 1

    print(f"✅ Chunking complete: {total} chunks → {out_chunks.path}")


