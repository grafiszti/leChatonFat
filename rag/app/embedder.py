import httpx

from app.config import settings


async def embed_texts(texts: list[str]) -> list[list[float]]:
    """Embed a list of texts via the OpenAI-compatible /v1/embeddings endpoint."""
    all_vectors = []
    batch_size = settings.EMBED_BATCH

    async with httpx.AsyncClient(timeout=120) as client:
        for i in range(0, len(texts), batch_size):
            batch = texts[i : i + batch_size]
            resp = await client.post(
                settings.EMBEDDINGS_URL,
                json={"input": batch, "model": settings.EMBEDDING_MODEL},
            )
            resp.raise_for_status()
            data = resp.json()
            # Sort by index to ensure order matches input
            sorted_data = sorted(data["data"], key=lambda x: x["index"])
            all_vectors.extend([d["embedding"] for d in sorted_data])

    return all_vectors
