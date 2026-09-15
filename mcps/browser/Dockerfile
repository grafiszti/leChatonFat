FROM node:22-bookworm-slim

WORKDIR /app

RUN npm init -y > /dev/null && \
    npm install @playwright/mcp && \
    npx playwright install --with-deps chromium

# Run the CLI directly with node (npx breaks MCP stdio transport).
# Headless + no-sandbox are required for a root container without a display.
# --browser chromium uses the bundled chromium (newer versions default to the
# "chrome" channel binary which is not installed in the image).
ENTRYPOINT ["node", "/app/node_modules/@playwright/mcp/cli.js", "--browser", "chromium", "--headless", "--no-sandbox"]