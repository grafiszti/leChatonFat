import os


class Settings:
    EMBEDDINGS_URL: str = os.getenv("EMBEDDINGS_URL", "http://embeddings:8084/v1/embeddings")
    QDRANT_URL: str = os.getenv("QDRANT_URL", "http://qdrant:6333")
    EMBEDDING_DIM: int = int(os.getenv("EMBEDDING_DIM", "1024"))
    EMBEDDING_MODEL: str = os.getenv("EMBEDDING_MODEL", "Qwen3-Embedding-0.6B-Q8_0")
    EMBED_BATCH: int = int(os.getenv("RAG_EMBED_BATCH", "8"))
    CHUNK_WORDS: int = int(os.getenv("RAG_CHUNK_WORDS", "600"))
    CHUNK_OVERLAP: int = int(os.getenv("RAG_CHUNK_OVERLAP", "100"))
    DOCS_DIR: str = "/docs"
    MAX_CRAWL_PAGES: int = int(os.getenv("RAG_MAX_CRAWL_PAGES", "10"))
    FETCH_TIMEOUT: int = int(os.getenv("RAG_FETCH_TIMEOUT", "30"))


settings = Settings()
