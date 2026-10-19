import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

const RAG_URL = process.env.RAG_URL || "http://rag:8083";
const TIMEOUT_MS = 120_000;

const server = new Server(
  { name: "rag-mcp-server", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

async function api(method, path, body) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${RAG_URL}${path}`, {
      method,
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`RAG API ${method} ${path} failed (${res.status}): ${text}`);
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "knowledge_search",
      description: "Semantic search over the ingested knowledge base. Returns top-k matching chunks with scores.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" },
          top_k: { type: "number", description: "Number of results (default 5)", default: 5 },
          min_score: { type: "number", description: "Minimum relevance score", default: null }
        },
        required: ["query"]
      }
    },
    {
      name: "knowledge_add_url",
      description: "Scrape and ingest a web page (URL) into the knowledge base.",
      inputSchema: {
        type: "object",
        properties: {
          url: { type: "string", description: "URL to ingest" }
        },
        required: ["url"]
      }
    },
    {
      name: "knowledge_add_text",
      description: "Ingest raw text directly into the knowledge base.",
      inputSchema: {
        type: "object",
        properties: {
          text: { type: "string", description: "Text content to store" },
          title: { type: "string", description: "Optional title for the source" }
        },
        required: ["text"]
      }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "knowledge_search": {
      const params = new URLSearchParams({ q: args.query });
      if (args.top_k) params.set("top_k", String(args.top_k));
      if (args.min_score) params.set("min_score", String(args.min_score));
      const results = await api("GET", `/search?${params}`);
      const text = results.length === 0
        ? "No matching results."
        : results.map((r, i) => `${i + 1}. [${+r.score.toFixed(3)}] ${r.title}\n   ${r.text}`).join("\n\n");
      return { content: [{ type: "text", text }] };
    }

    case "knowledge_add_url": {
      const result = await api("POST", "/ingest/url", { url: args.url });
      return { content: [{ type: "text", text: `Ingested ${result.chunks} chunks (source ${result.source_id}).` }] };
    }

    case "knowledge_add_text": {
      const result = await api("POST", "/ingest/text", { text: args.text, title: args.title });
      return { content: [{ type: "text", text: `Ingested ${result.chunks} chunks (source ${result.source_id}).` }] };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);