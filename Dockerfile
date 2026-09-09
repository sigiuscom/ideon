FROM node:24-slim AS base
WORKDIR /app

# 1. Install dependencies and build app
FROM base AS builder
RUN apt-get update && apt-get install -y --no-install-recommends python3 build-essential ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
ENV NODE_ENV=production
ENV LOG_LEVEL=warn
RUN IS_NEXT_BUILD=1 npm run build
RUN rm -rf .next/cache

# 2. Production image
FROM base AS runner
ENV NODE_ENV=production
RUN apt-get update && apt-get install -y --no-install-recommends tini curl && rm -rf /var/lib/apt/lists/*
RUN useradd -u 1001 -m appuser \
    && mkdir -p /app/storage/avatars /app/storage/yjs /app/storage/uploads \
    && mkdir -p /app/.next/cache \
    && chown -R appuser:appuser /app/storage /app/.next/cache

# standalone already contains the nft-traced node_modules
COPY --from=builder /app/.next/standalone ./
COPY package-lock.json /tmp/server-runtime/package-lock.json
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 build-essential \
    && echo '{"name":"runtime","private":true,"dependencies":{"y-leveldb":"*","kysely":"*","nanoid":"*","node-pty":"*"}}' > /tmp/server-runtime/package.json \
    && cd /tmp/server-runtime \
    && npm install --no-audit --no-fund \
    && cp -R node_modules/. /app/node_modules/ \
    && apt-get purge -y --auto-remove python3 build-essential \
    && rm -rf /tmp/server-runtime \
    && rm -rf /root/.npm \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/node_modules/next ./node_modules/next
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
COPY --from=builder /app/src/app/i18n ./src/app/i18n
COPY --from=builder /app/src/app/db/migrations ./src/app/db/migrations
COPY --from=builder /app/next.config.mjs ./next.config.mjs
COPY docker-entrypoint.sh /app/docker-entrypoint.sh

RUN chmod +x /app/docker-entrypoint.sh
EXPOSE 3000
ENTRYPOINT ["tini", "--", "/app/docker-entrypoint.sh"]
CMD ["node", "dist/server.cjs"]
