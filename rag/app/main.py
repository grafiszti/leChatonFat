from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from app.config import settings
from app.qdrant import qdrant
from app.routers import ingest, search, sources

app = FastAPI(title="RAG Knowledge Base")

app.include_router(ingest.router)
app.include_router(search.router)
app.include_router(sources.router)

app.mount("/static", StaticFiles(directory="/app/static"), name="static")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/", include_in_schema=False)
async def index():
    return FileResponse("/app/static/index.html")


@app.on_event("startup")
async def startup():
    await qdrant.ensure_collection(settings.EMBEDDING_DIM)
