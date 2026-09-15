# RAG Knowledge Base — Implementation Plan

Standalone RAG service with a vector DB and document ingestion (web URLs, PDF, DOCX),
exposed to Opencode as an MCP tool. Architecture chosen: **hybrid** — an always-on
`rag` service + `qdrant` + a dedicated `embeddings` llama.cpp instance, fronted by a
thin MCP adapter.

## Why hybrid (vs all-in-one MCP)

The existing MCP servers (`mcps/browser`, `mcps/searxng`) are spawned per-call via
`docker run -i --rm` — they are ephemeral. Persistent state (vector DB, raw documents,
embeddings) therefore cannot live in the MCP process. The always-on `rag` service owns
all state; the MCP adapter is a stateless HTTP proxy.

```
 Opencode
    │
    ▼
 mcps/rag  (Node MCP, spawned per-call, stateless)        [new]
    │  HTTP :8002
    ▼
 rag  (FastAPI, always-on)                                [new]
    │  ├─ ingest: URL scrape / PDF / DOCX → parse → chunk
    │  ├─ embed:  POST /v1/embeddings
    │  └─ search: top-k semantic search over chunks
    │
    ├── qdrant (vector DB, volume-backed)                 [new]
    ├── docs/  (raw uploads, bind-mounted volume)
    └── embeddings (llama.cpp --embeddings instance)      [new]
```

## Components

### 1. `embeddings` — llama.cpp embedding server

Second instance of the existing CUDA image (`ghcr.io/ggml-org/llama.cpp:server-cuda`),
started in `--embeddings` mode instead of chat mode.

- Image: same base; new small Dockerfile (or env-gated entrypoint — prefer a dedicated
  Dockerfile for clarity).
- Model (default): `Qwen3-Embedding-0.6B-GGUF` (Q4_K_M), 1024-dim, Matryoshka/MRL
  capable. ~0.6B params → tiny VRAM footprint alongside the main model.
- Runtime flags: `--embeddings`, `--pooling mean`, `--ctx-size 8192`, low `--threads`.
  **Verify at implementation**: exact `llama-server` embedding flags for this release,
  and whether Qwen3-Embedding needs query/passage task prefixes (asymmetric model).
- Exposes OpenAI-compatible `POST /v1/embeddings`.
- Ports: internal `8082`, not exposed to host (internal network only).
- Model GGUF goes in `./models/` (shared bind mount) — reuse `make download_*` pattern.
  **Verify at implementation**: correct HF repo / GGUF filename.

### 2. `qdrant` — vector database

- Image: `qdrant/qdrant` (pin version).
- Named volume `qdrant_data:/qdrant/storage` for persistence.
- Ports: internal `6333`; expose `6333` to host **only** for the admin UI (optional).
- Collection `knowledge`:
  - `vectors.size = 1024` (must match embedding model dim; 512 if MRL-truncated)
  - `distance = Cosine`
  - created on first start by the `rag` service (`ensure_collection`).

### 3. `rag` — FastAPI service

Python image (`python:3.12-slim`), deps:
`fastapi`, `uvicorn`, `httpx`, `beautifulsoup4`, `lxml`, `pypdf`, `mammoth`,
`qdrant-client`. NO torch/sentence-transformers (embeddings come from `embeddings`).

Endpoints:

| Method | Path                   | Body                                | Purpose                                |
|--------|------------------------|-------------------------------------|----------------------------------------|
| GET    | `/health`              | —                                   | Liveness / readiness                   |
| POST   | `/ingest/url`          | `{ "url", "max_chars"?, "depth"? }` | Scrape page → ingest                   |
| POST   | `/ingest/file`         | multipart `file`                    | PDF/DOCX/MD/TXT upload → ingest        |
| GET    | `/search`              | `?q=&top_k=&min_score=`             | Semantic top-k over chunks             |
| GET    | `/sources`             | —                                   | List ingested sources                  |
| DELETE | `/sources/{id}`        | —                                   | Remove source + chunks                 |
| GET    | `/`                    | —                                   | Serve the web UI (FileResponse)        |
| GET    | `/sources/{id}/chunks` | —                                   | List chunks for a source (text, index) |

Data flow:

- **Ingest**: fetch/parse → extract text → save raw to `/docs/{id}.txt` (+ original ext) →
  chunk → embed chunks (batched) → upsert points into qdrant with payload
  `{ source_id, title, url, chunk_index, doc_type }`.
- **Search**: embed query → qdrant `query()` with `top_k` and optional `score_threshold` →
  return `{ source, title, url, chunk_index, score, text }`.

Chunking strategy:
- Paragraph-based (`split_paragraphs`) with greedy merge to ~800 tokens (~600 words)
  and ~100-token overlap. Explicit `\n\n` boundaries preferred; hard cap by sentence if
  a paragraph overflows. Keep `chunk_index` for re-assembly.
- Chunk boundaries derived once, cached per source (so re-ingest/delete is consistent).

Sources are de-duplicated by URL hash; re-ingesting the same URL replaces its chunks.

### 4. `mcps/rag` — MCP adapter

Node MCP server mirroring the `mcps/searxng` pattern (`@modelcontextprotocol/sdk`).
Stateless proxy → `rag` service over HTTP.

Tools exposed to Opencode:

| Tool                 | Args                            | Maps to                              |
|----------------------|---------------------------------|--------------------------------------|
| `knowledge_search`   | `query`, `top_k?`, `min_score?` | `GET /search`                        |
| `knowledge_add_url`  | `url`                           | `POST /ingest/url`                   |
| `knowledge_add_text` | `text`, `title?`                | inline `POST /ingest/url`-style path |

Notes:
- Local file ingestion (PDF/DOCX on the host) goes through the **Makefile** target, not
  the MCP — stdio/docker-run MCP can't easily receive binary uploads.
- Dockerfile: `node:22-alpine`, `ENTRYPOINT ["node", "server.mjs"]`.

### 5. Web UI — source management & search preview

Served directly by the `rag` FastAPI service via `StaticFiles` mount — no extra
containers. Single self-contained `rag/static/index.html` (inline CSS + vanilla JS,
no build step, no frameworks).

New API endpoints (added to the table in section 3):

| Method | Path                   | Body | Purpose                                |
|--------|------------------------|------|----------------------------------------|
| GET    | `/`                    | —    | Serve the web UI (FileResponse)        |
| GET    | `/sources/{id}/chunks` | —    | List chunks for a source (text, index) |

UI layout (single page):

- **Top bar**: search box → calls `GET /search`, shows results inline with score,
  chunk text, and source title.
- **Source table**: title, URL, doc type, chunk count, ingested_at. Auto-refreshes
  after ingest/delete actions.
  - Each row has a delete button (trash icon) → `DELETE /sources/{id}` with
    confirmation dialog.
  - Click a row → expand inline to show chunks via `GET /sources/{id}/chunks`.
- **Ingest panel** (bottom or sidebar):
  - URL input + "Ingest" button → `POST /ingest/url`.
  - File input (accepts PDF/DOCX/TXT/MD) + "Upload" button → `POST /ingest/file`.

The page is purely cosmetic sugar over the existing API — no new business logic.

## Docker Compose changes (`docker-compose.yml`)

Add three services:

```yaml
  embeddings:
    build: ./embeddings            # or reuse llama image + env flag
    container_name: llama-embeddings
    restart: unless-stopped
    volumes: ["./models:/models"]
    environment: [embedding flags from .env]
    healthcheck: curl /health

  qdrant:
    image: qdrant/qdrant:<pinned>
    container_name: qdrant
    restart: unless-stopped
    volumes: ["qdrant_data:/qdrant/storage"]
    ports: ["127.0.0.1:6333:6333"]

  rag:
    build: ./rag
    container_name: rag
    restart: unless-stopped
    depends_on: [embeddings, qdrant]
    volumes:
      - "./rag_data:/docs"           # raw parsed documents
    env_file: [.env]
    environment:
      - EMBEDDINGS_URL=http://embeddings:8082/v1/embeddings
      - QDRANT_URL=http://qdrant:6333
    ports: ["${RAG_PORT_EXTERNAL}:${RAG_PORT_INTERNAL}"]
    # Web UI served at http://localhost:${RAG_PORT_EXTERNAL}
    healthcheck: curl /health

volumes:
  qdrant_data:
  rag_data:
```

`rag` and `embeddings` must be reachable from MCP containers on the compose network
(`lechatonfat_default`), same as `searxng-search` / `browser` today.

## `.env` additions

```
# Embeddings
EMBEDDING_MODEL=Qwen3-Embedding-0.6B-GGUF          # .gguf filename (no ext)
EMBEDDING_CTX=8192
EMBEDDING_THREADS=4
EMBEDDING_DIM=1024

# RAG service
RAG_PORT_INTERNAL=8083
RAG_PORT_EXTERNAL=8002
RAG_EMBED_BATCH=32          # chunks per embedding request
RAG_CHUNK_WORDS=600         # target chunk size
RAG_CHUNK_OVERLAP=100

# Qdrant (host access optional)
QDRANT_PORT=6333
```

Add matching defaults to `templates/.env.template`.

## `templates/opencode.json.template` changes

Append to `mcp`:

```json
    "rag": {
      "type": "local",
      "command": ["docker", "run", "-i", "--rm", "--network", "lechatonfat_default", "lechatonfat-mcp-rag"]
    }
```

(Generated `opencode.json` picks this up automatically via the existing script.)

## Makefile targets

| Target                  | Purpose                                         |
|-------------------------|-------------------------------------------------|
| `build-mcp-rag`         | Build `lechatonfat-mcp-rag` image               |
| `build-mcp`             | Extend to include rag                           |
| `rag-ingest-file`       | `curl -F file=@... :8002/ingest/file`           |
| `rag-ingest-url`        | `curl -d '{"url": ...}' :8002/ingest/url`       |
| `rag-search`            | `curl ':8002/search?q=...'`                     |
| `rag-sources`           | `curl :8002/sources`                            |
| `download_embeddings`   | `hf download` of `EMBEDDING_MODEL` into `models/` |
| `rag-ui`                | Open `http://localhost:${RAG_PORT_EXTERNAL}` in default browser |

`make up` should build/start the new services; add image pre-build checks like the
existing MCP ones.

## Implementation phases

1. **Infra** — `.env` + template vars; compose services for `embeddings` + `qdrant`;
   `embeddings` Dockerfile & startup script (mirror `run.sh` pattern); verify
   `GET /v1/embeddings` works with a curl.
2. **RAG service skeleton** — FastAPI app, `/health`, `ensure_collection`, env wiring,
   deps in `rag/requirements.txt`.
3. **Parsers & chunking** — URL (httpx + BeautifulSoup), PDF (`pypdf`), DOCX
   (`mammoth`), TXT/MD; chunker + unit checks on a sample doc.
4. **Ingestion** — `/ingest/url`, `/ingest/file`; raw doc storage; chunk → embed →
   qdrant upsert; de-dup by URL; `DELETE /sources/{id}`.
5. **Search** — `/search` with `top_k`, `min_score`; verify result quality on 2–3 docs.
6. **MCP adapter** — `mcps/rag/server.mjs` + `package.json` + `Dockerfile`; wire tools;
   build image; add to `opencode.json.template`.
7. **Makefile & validation** — new targets; extend `make up`; smoke tests:
   `make rag-ingest-url`, `make rag-search`, and an Opencode session asking a question
   answerable only from the KB. Smoke test the web UI: open
   `http://localhost:${RAG_PORT_EXTERNAL}`, list sources, ingest a URL, search, delete.
8. **Docs** — update `README.md`; document ingest workflow (URL via MCP tool, files via
   `make rag-ingest-file`).

## Open items to verify at implementation time

- Exact `llama-server` embedding flags (`--embeddings`, `--pooling`) for the pinned
  image version.
- Qwen3-Embedding query/passage prefix handling in llama.cpp (asymmetric model).
- HF repo + GGUF filename for the embedding model; confirm `EMBEDDING_DIM` matches.
- Qdrant client + server version pairing; collection creation params.
- Port collisions with existing services (llama `8001`, searxng `8081`).
