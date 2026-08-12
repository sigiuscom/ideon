FROM node:24-alpine@sha256:d32cdf619f63fe0471182d08996dd516c6275bb5fd31ae06e55a570bd9e1ad43 AS base
WORKDIR /app

# 1. Install dependencies and build app
FROM base AS builder
RUN apk add --no-cache \
    python3=3.14.5-r0 \
    make=4.4.1-r4 \
    g++=15.2.0-r5 \
    ca-certificates=20260611-r0
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
ENV NODE_ENV=production
ENV LOG_LEVEL=warn
RUN IS_NEXT_BUILD=1 npm run build
RUN rm -rf .next/cache

# 2. Install only the packages nft misses
FROM base AS server-runtime
RUN apk add --no-cache \
    python3=3.14.5-r0 \
    make=4.4.1-r4 \
    g++=15.2.0-r5 \
    ca-certificates=20260611-r0
COPY docker/runtime/package.json docker/runtime/package-lock.json ./
RUN npm ci --no-audit --no-fund

# 3. Production image
FROM base AS runner
ENV NODE_ENV=production
RUN apk add --no-cache tini=0.19.0-r3 shadow=4.18.0-r1 \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
RUN addgroup -g 1001 appuser \
    && adduser -D -u 1001 -G appuser appuser \
    && mkdir -p /app/storage/avatars /app/storage/yjs /app/storage/uploads \
    && mkdir -p /app/.next/cache \
    && chown -R appuser:appuser /app/storage /app/.next/cache

# standalone already contains the nft-traced node_modules
COPY --from=builder /app/.next/standalone ./
COPY --from=server-runtime /app/node_modules ./node_modules
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
