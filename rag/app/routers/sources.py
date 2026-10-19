from fastapi import APIRouter, HTTPException
from pathlib import Path
import json

from app.config import settings
from app.qdrant import qdrant

router = APIRouter()


def _load_meta(docs_dir: Path, source_id: str) -> dict | None:
    """Load source metadata from the chunks.json cache file."""
    meta_file = docs_dir / f"{source_id}.chunks.json"
    if not meta_file.exists():
        return None
    data = json.loads(meta_file.read_text(encoding="utf-8"))
    if isinstance(data, dict) and "meta" in data:
        return data["meta"]
    # Backwards compatible with older format: list of {index, text}
    return {
        "id": source_id,
        "title": (data[0]["text"][:80] if data else ""),
        "url": "",
        "filename": "",
        "doc_type": "text",
        "ingested_at": "",
        "chunk_count": len(data),
    }


@router.get("/sources")
async def list_sources():
    """List all ingested sources with metadata from chunk cache files."""
    docs_dir = Path(settings.DOCS_DIR)
    if not docs_dir.exists():
        return []

    sources = []
    for meta_file in sorted(docs_dir.glob("*.chunks.json")):
        source_id = meta_file.stem.replace(".chunks", "")
        meta = _load_meta(docs_dir, source_id)
        if meta is not None:
            sources.append({
                "id": meta["id"],
                "title": meta["title"],
                "url": meta.get("url", "") or None,
                "filename": meta.get("filename", "") or None,
                "doc_type": meta.get("doc_type", "text"),
                "chunk_count": meta.get("chunk_count", 0),
                "ingested_at": meta.get("ingested_at", ""),
            })

    return sources


@router.get("/sources/{source_id}/chunks")
async def get_chunks(source_id: str):
    """List chunks for a given source."""
    meta_file = Path(settings.DOCS_DIR) / f"{source_id}.chunks.json"
    if not meta_file.exists():
        raise HTTPException(status_code=404, detail="Source not found")

    data = json.loads(meta_file.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        return data["chunks"]
    return data


@router.delete("/sources/{source_id}")
async def delete_source(source_id: str):
    """Delete a source: remove qdrant points, raw files, and chunk cache."""
    docs_dir = Path(settings.DOCS_DIR)

    # Delete from qdrant
    await qdrant.delete_by_source(source_id)

    # Delete files
    for f in docs_dir.glob(f"{source_id}.*"):
        f.unlink()

    return {"status": "deleted", "source_id": source_id}
