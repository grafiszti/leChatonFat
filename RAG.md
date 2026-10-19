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
     │  HTTP :8083 (internal — MCP reaches rag via compose network)
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
- Model (default): `Qwen3-Embedding-0.6B-Q8_0` from `Qwen/Qwen3-Embedding-0.6B-GGUF`
  (official repo — ships `Q8_0` / `f16` only), 1024-dim, Matryoshka/MRL
  capable. ~0.6B params → tiny VRAM footprint alongside the main model.
- Runtime flags: `--embeddings`, `--ctx-size 8192`, low `--threads`. Pooling is left to the
  model default — **verified**: Qwen3-Embedding-0.6B GGUF ships default pooling `[3]`
  (last-token), which is the correct mode for this model; the previous `--pooling mean`
  override was removed (it produced a mismatch warning on startup).
- Exposes OpenAI-compatible `POST /v1/embeddings`.
- Ports: internal `8084`, not exposed to host. (Deliberately numbered away from `8082`
  to avoid confusion with the rag host port `8002` — see `.env` section.)
- Model GGUF goes in `./models/` (shared bind mount) — reuse `make download_*` pattern.
  **Verified**: repo `Qwen/Qwen3-Embedding-0.6B-GGUF` file `Qwen3-Embedding-0.6B-Q8_0.gguf`,
  1024-dim (confirmed via live `/v1/embeddings` response).
- GPU: same CUDA image and the same nvidia runtime reservation as the main `llama` service
  (via `docker-compose.override.yml`). Without it the container silently runs on CPU and
  embedding batches take ~40s instead of <1s.**Verified**: with the reservation, an 8×600-word
  batch embeds in ~0.6s on an RTX 2070 Super.

### 2. `qdrant` — vector database

- Image: `qdrant/qdrant` (pin version).
- Named volume `qdrant_data:/qdrant/storage` for persistence.
- Ports: internal `6333`. Host exposure optional — bind `127.0.0.1:${QDRANT_PORT}:6333`
  for the admin UI and diagnostics; omit if not needed.
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
| POST   | `/ingest/file`         | multipart `file`                    | PDF/DOCX/MD/TXT upload → ingest |
| POST   | `/ingest/text`         | `{ "text", "title"? }`              | Raw text → ingest               |
| GET    | `/search`              | `?q=&top_k=&min_score=`             | Semantic top-k over chunks      |
| GET    | `/sources`             | —                                   | List ingested sources                  |
| DELETE | `/sources/{id}`        | —                                   | Remove source + chunks                 |
| GET    | `/`                    | —                                   | Serve the web UI (FileResponse)        |
| GET    | `/sources/{id}/chunks` | —                                   | List chunks for a source (text, index) |

Data flow:

- **Ingest**: fetch/parse → extract text → save parsed text to `/docs/{id}.txt`, plus the
  original upload as `/docs/{id}.{orig_ext}` when one exists (a `.txt` parse may be the
  only file for URLs/text) → chunk → embed chunks (batched) → upsert points into qdrant
  with payload `{ source_id, title, url?, filename?, chunk_index, doc_type }`.
- **Search**: embed query → qdrant `query()` with `top_k` and optional `score_threshold` →
  return `{ source_id, title, url?, filename?, chunk_index, score, text }`.

Chunking strategy:
- Paragraph-based (`split_paragraphs`) with greedy merge to ~800 tokens (~600 words)
  and ~100-token overlap. Explicit `\n\n` boundaries preferred; hard cap by sentence if
  a paragraph overflows. Keep `chunk_index` for re-assembly.
- Chunk boundaries computed once per ingest and persisted as `/docs/{id}.chunks.json`
  alongside the raw text (survives service restarts).

- `source_id` is the SHA‑256 hex hash of the URL (for `/ingest/url`) or of the file
  content (for `/ingest/file`). `/ingest/text` uses the SHA‑256 of the text itself.
- URL sources are de-duplicated by that hash; file sources by content hash, so re-uploading
  the same bytes replaces chunks. Re-ingesting an existing `source_id` replaces its points,
  raw files, and chunk cache (points are deleted by source first, then re-upserted).
- `/ingest/url` params: `depth` is crawl depth — `0` (default) ingests only the given page;
  `≥1` follows same-origin links (BFS, capped at `RAG_MAX_CRAWL_PAGES`), each page becoming
  its own source (dedup still applies). Slow/unreachable pages are skipped. `max_chars` caps
  the extracted text (character count, default none) before chunking.
- `/ingest/url` returns a single source object for depth 0, or `{ "sources": [...] }` when
  a crawl ingested multiple pages.
- `GET /sources` returns `[{ id, title, url?, filename?, doc_type, chunk_count,
  ingested_at }]`, read from the per-source chunk cache (`{id}.chunks.json` now stores
  `{ meta, chunks: [{index, text}] }`), so it survives service restarts and qdrant wipes.

### 4. `mcps/rag` — MCP adapter

Node MCP server mirroring the `mcps/searxng` pattern (`@modelcontextprotocol/sdk`).
Stateless proxy → `rag` service over HTTP.

Tools exposed to Opencode:

| Tool                 | Args                            | Maps to                              |
|----------------------|---------------------------------|--------------------------------------|
| `knowledge_search`   | `query`, `top_k?`, `min_score?` | `GET /search`                        |
| `knowledge_add_url`  | `url`                           | `POST /ingest/url`                   |
| `knowledge_add_text` | `text`, `title?`                | `POST /ingest/text`                  |

Notes:
- Local file ingestion (PDF/DOCX on the host) goes through the **Makefile** target, not
  the MCP — stdio/docker-run MCP can't easily receive binary uploads.
- Dockerfile: `node:22-alpine`, `ENTRYPOINT ["node", "server.mjs"]`.

### 5. Web UI — source management & search preview

Served directly by the `rag` FastAPI service via `StaticFiles` mount — no extra
containers. Single self-contained `rag/static/index.html` (inline CSS + vanilla JS,
no build step, no frameworks).

The `rag` Dockerfile must copy the static assets: `COPY static /app/static`. The app
mounts the directory at `/` via `StaticFiles(html=True, directory="/app/static")`.

New API endpoints (added to the table in section 3):

| Method | Path                   | Body | Purpose                                |
|--------|------------------------|------|----------------------------------------|
| GET    | `/`                    | —    | Serve the web UI (FileResponse)        |
| GET    | `/sources/{id}/chunks` | —    | List chunks for a source (text, index) |

UI layout (single page):

- **Top bar**: search box → calls `GET /search`, shows results inline with score,
  chunk text, and source title.
- **Source table**: title, URL (or filename for file uploads), doc type, chunk count,
  ingested_at. Auto-refreshes after ingest/delete actions.
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
    build: ./embeddings            # dedicated llama.cpp --embeddings instance
    container_name: llama-embeddings
    restart: unless-stopped
    env_file: [.env]               # EMBEDDING_* vars → llama-server flags via run.sh
    volumes: ["./models:/models"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8084/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  qdrant:
    image: qdrant/qdrant:<pinned>
    container_name: qdrant
    restart: unless-stopped
    volumes: ["qdrant_data:/qdrant/storage"]
    ports: ["127.0.0.1:${QDRANT_PORT}:6333"]

  rag:
    build: ./rag
    container_name: rag
    restart: unless-stopped
    depends_on: [embeddings, qdrant]
    volumes:
      - "./rag_data:/docs"           # raw parsed documents
    env_file: [.env]
    environment:
      - EMBEDDINGS_URL=http://embeddings:8084/v1/embeddings
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
EMBEDDING_MODEL=Qwen3-Embedding-0.6B-Q8_0          # .gguf filename (no ext)
EMBEDDING_HF_REPO=Qwen/Qwen3-Embedding-0.6B-GGUF
EMBEDDING_CTX=8192
EMBEDDING_THREADS=4
EMBEDDING_BATCH_SIZE=8192
EMBEDDING_DIM=1024

# RAG service
RAG_PORT_INTERNAL=8083
RAG_PORT_EXTERNAL=8002
RAG_EMBED_BATCH=8           # chunks per embedding request (stay under ctx=8192)
RAG_CHUNK_WORDS=600         # target chunk size
RAG_CHUNK_OVERLAP=100
RAG_MAX_CRAWL_PAGES=10      # pages crawled when /ingest/url depth >= 1
RAG_FETCH_TIMEOUT=30        # per-URL fetch timeout (seconds)

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
| `rag-ingest-file`       | `curl -F file=@... localhost:$(RAG_PORT_EXTERNAL)/ingest/file` |
| `rag-ingest-url`        | `curl -d '{"url": ...}' localhost:$(RAG_PORT_EXTERNAL)/ingest/url` |
| `rag-search`            | `curl 'localhost:$(RAG_PORT_EXTERNAL)/search?q=...'` |
| `rag-sources`           | `curl localhost:$(RAG_PORT_EXTERNAL)/sources` |
| `download_embeddings`   | `hf download` of `EMBEDDING_MODEL` into `models/` |
| `rag-ui`                | Open `http://localhost:$(RAG_PORT_EXTERNAL)` in default browser |

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
4. **Ingestion** — `/ingest/url`, `/ingest/file`, `/ingest/text`; raw doc storage; chunk → embed →
   qdrant upsert; de-dup by content hash; `DELETE /sources/{id}`.
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

- ~~Exact `llama-server` embedding flags (`--embeddings`, `--pooling`) for the pinned
  image version.~~ **Done.** `--embeddings` works; pooling left at model default (`[3]`/last).
- ~~Qwen3-Embedding query/passage prefix handling in llama.cpp (asymmetric model).~~
  **Check.** Server accepts plain prompts; no explicit prefix applied at ingest/search time.
  If result quality is poor, prepend the Qwen3 task prefixes before embedding. Current
  search quality on the Python tutorial sample is good (top hits match the topic).
- ~~HF repo + GGUF filename for the embedding model; confirm `EMBEDDING_DIM` matches.~~
  **Done.** `Qwen/Qwen3-Embedding-0.6B-GGUF` / `Qwen3-Embedding-0.6B-Q8_0.gguf`, 1024-dim.
- ~~Qdrant client + server version pairing; collection creation params.~~
  **Done.** `qdrant/qdrant:v1.13.4` + `qdrant-client==1.11.0`; collection `knowledge`
  (1024, Cosine) created on first startup by `ensure_collection`. Re-ingest deletes
  by source_id filter before upsert (replace semantics verified).
- ~~Port collisions with existing services (llama `8001`, searxng `8081`).~~
  **Done.** RAG host `8002`; qdrant host `6333` bound to 127.0.0.1; embeddings internal
  only `8084`. No collisions with llama `8001`/searxng `8081`.
