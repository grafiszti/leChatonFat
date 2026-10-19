from fastapi import APIRouter, Query
from app.embedder import embed_texts
from app.qdrant import qdrant

router = APIRouter()


@router.get("/search")
async def search(
    q: str = Query(...),
    top_k: int = Query(default=5),
    min_score: float | None = Query(default=None),
):
    vectors = await embed_texts([q])
    results = await qdrant.search(vectors[0], top_k=top_k, score_threshold=min_score)

    return [
        {
            "source_id": r.payload["source_id"],
            "title": r.payload["title"],
            "url": r.payload.get("url", ""),
            "filename": r.payload.get("filename", ""),
            "chunk_index": r.payload["chunk_index"],
            "score": r.score,
            "text": r.payload["text"],
        }
        for r in results
    ]
