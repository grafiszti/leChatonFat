from qdrant_client import AsyncQdrantClient
from qdrant_client.models import VectorParams, Distance

from app.config import settings

COLLECTION = "knowledge"


class Qdrant:
    def __init__(self):
        self.client = AsyncQdrantClient(url=settings.QDRANT_URL)

    async def ensure_collection(self, dim: int):
        collections = await self.client.get_collections()
        names = [c.name for c in collections.collections]
        if COLLECTION not in names:
            await self.client.create_collection(
                collection_name=COLLECTION,
                vectors_config=VectorParams(size=dim, distance=Distance.COSINE),
            )

    async def upsert(self, points):
        await self.client.upsert(collection_name=COLLECTION, points=points)

    async def search(self, vector, top_k=5, score_threshold=None):
        return await self.client.search(
            collection_name=COLLECTION,
            query_vector=vector,
            limit=top_k,
            score_threshold=score_threshold,
        )

    async def scroll_by_source(self, source_id: str):
        from qdrant_client.models import Filter, FieldCondition, MatchValue

        result = await self.client.scroll(
            collection_name=COLLECTION,
            scroll_filter=Filter(
                must=[FieldCondition(key="source_id", match=MatchValue(value=source_id))]
            ),
            with_payload=True,
            with_vectors=False,
        )
        return result[0]

    async def delete_by_source(self, source_id: str):
        from qdrant_client.models import Filter, FieldCondition, MatchValue

        await self.client.delete(
            collection_name=COLLECTION,
            points_selector=Filter(
                must=[FieldCondition(key="source_id", match=MatchValue(value=source_id))]
            ),
        )


qdrant = Qdrant()
