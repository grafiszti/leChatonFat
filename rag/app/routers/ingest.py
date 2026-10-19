from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel
from pathlib import Path
import httpx

from app.config import settings
from app.parsers import (
    parse_url, parse_pdf, parse_docx, parse_text, extract_links,
    content_hash_url, content_hash_bytes, content_hash_text, file_ext,
)
from app.chunker import chunk_text
from app.embedder import embed_texts
from app.qdrant import qdrant

router = APIRouter()


class IngestURLRequest(BaseModel):
    url: str
    max_chars: int | None = None
    depth: int = 0


class IngestTextRequest(BaseModel):
    text: str
    title: str | None = None


async def _ingest(title: str, text: str, source_id: str, doc_type: str,
                  url: str = "", filename: str = "", orig_data: bytes | None = None,
                  orig_ext: str = ""):
    """Core ingest flow: clean old → save raw → chunk → embed → upsert.

    Re-ingesting an existing source_id replaces its qdrant points, raw files,
    and chunk cache.
    """
    import json
    import uuid
    from datetime import datetime, timezone

    from qdrant_client.models import PointStruct

    raw_dir = Path(settings.DOCS_DIR)
    raw_dir.mkdir(parents=True, exist_ok=True)

    # Replace old data for this source (points + raw files + chunk cache)
    await qdrant.delete_by_source(source_id)
    for old in raw_dir.glob(f"{source_id}.*"):
        old.unlink()

    # Save parsed text
    raw_path = raw_dir / f"{source_id}.txt"
    raw_path.write_text(text, encoding="utf-8")

    # Save original upload if we have one
    if orig_data is not None and orig_ext:
        (raw_dir / f"{source_id}.{orig_ext}").write_bytes(orig_data)

    # Chunk
    chunks = chunk_text(text)

    # Embed in batches
    vectors = await embed_texts(chunks)

    # Build points
    points = []
    for i, (chunk, vector) in enumerate(zip(chunks, vectors)):
        point_id = str(uuid.uuid3(uuid.NAMESPACE_OID, f"{source_id}:{i}"))
        points.append(
            PointStruct(
                id=point_id,
                vector=vector,
                payload={
                    "source_id": source_id,
                    "title": title,
                    "url": url,
                    "filename": filename,
                    "chunk_index": i,
                    "doc_type": doc_type,
                    "text": chunk,
                },
            )
        )

    if points:
        await qdrant.upsert(points)

    # Save source metadata + chunk cache (survives restarts)
    meta_path = raw_dir / f"{source_id}.chunks.json"
    meta_path.write_text(
        json.dumps(
            {
                "meta": {
                    "id": source_id,
                    "title": title,
                    "url": url,
                    "filename": filename,
                    "doc_type": doc_type,
                    "ingested_at": datetime.now(timezone.utc).isoformat(),
                    "chunk_count": len(chunks),
                },
                "chunks": [{"index": i, "text": c} for i, c in enumerate(chunks)],
            }
        ),
        encoding="utf-8",
    )

    return {
        "source_id": source_id,
        "title": title,
        "chunks": len(chunks),
    }


@router.post("/ingest/url")
async def ingest_url(req: IngestURLRequest):
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) leChatonFat-RAG/1.0 "
                      "(knowledge-base ingester)",
    }

    async def fetch(url: str) -> str:
        async with httpx.AsyncClient(timeout=settings.FETCH_TIMEOUT, follow_redirects=True, headers=headers) as client:
            resp = await client.get(url)
            if resp.status_code >= 400:
                raise RuntimeError(f"Fetch failed: {resp.status_code} for {url}")
        return resp.text

    # BFS crawl: depth 0 = this page only; depth >= 1 follows same-origin links
    to_visit = [req.url]
    visited = set()
    pages = []
    while to_visit and len(pages) < settings.MAX_CRAWL_PAGES:
        url = to_visit.pop(0)
        if url in visited:
            continue
        visited.add(url)
        try:
            html = await fetch(url)
        except Exception:
            continue
        title, text = parse_url(html, url)
        if req.max_chars:
            text = text[: req.max_chars]
        pages.append((url, title, text))
        if req.depth > 0:
            for link in extract_links(html, url):
                if link not in visited and link not in to_visit:
                    to_visit.append(link)

    results = []
    for url, title, text in pages:
        if not text.strip():
            continue
        source_id = content_hash_url(url)
        result = await _ingest(title, text, source_id, doc_type="url", url=url)
        results.append(result)

    if not results:
        raise HTTPException(status_code=422, detail="No text content extracted from URL")

    if len(results) == 1:
        return results[0]
    return {"sources": results}


@router.post("/ingest/file")
async def ingest_file(file: UploadFile = File(...)):
    data = await file.read()
    ext = file_ext(file.filename)

    if ext == "pdf":
        _, text = parse_pdf(data)
    elif ext in ("docx", "doc"):
        _, text = parse_docx(data)
    elif ext in ("md", "txt", ""):
        _, text = parse_text(data)
    else:
        raise HTTPException(status_code=422, detail=f"Unsupported file type: {ext}")

    if not text.strip():
        raise HTTPException(status_code=422, detail="No text content extracted from file")

    source_id = content_hash_bytes(data)

    result = await _ingest(
        title=file.filename,
        text=text,
        source_id=source_id,
        doc_type=ext or "text",
        filename=file.filename,
        orig_data=data,
        orig_ext=ext,
    )
    return result


@router.post("/ingest/text")
async def ingest_text(req: IngestTextRequest):
    source_id = content_hash_text(req.text)
    result = await _ingest(
        title=req.title or "Untitled",
        text=req.text,
        source_id=source_id,
        doc_type="text",
    )
    return result
