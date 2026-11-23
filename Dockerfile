# syntax=docker/dockerfile:1
#
# Imagem de produção enxuta e endurecida para hospedagem própria (VPS, Coolify,
# Railway, Render, Kubernetes...). Na Vercel este arquivo não é usado.
#
#   docker build --build-arg SITE_URL=https://www.entretoques.com.br -t entre-toques .
#   docker run --rm -p 3000:3000 --read-only --tmpfs /app/.next/cache \
#     --cap-drop ALL --security-opt no-new-privileges entre-toques
#
# Imagem base: Node 24 LTS (mesma versão do .nvmrc), fixada por digest.
# Use só versões LTS (números pares). Versões ímpares (25, 27...) duram 6 meses.
FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS base
ENV NEXT_TELEMETRY_DISABLED=1

# ---------- 1. Dependências (só reinstala se o lockfile mudar) ----------
FROM base AS deps
WORKDIR /app
COPY package.json package-lock.json .npmrc ./
RUN npm ci --no-audit --no-fund

# ---------- 2. Build ----------
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# A URL pública entra no HTML estático (canonical, Open Graph, sitemap).
ARG SITE_URL=https://www.entretoques.com.br
ENV SITE_URL=${SITE_URL}
RUN npm run build

# ---------- 3. Runtime: só o necessário, sem npm, como usuário sem privilégios ----------
FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0

RUN addgroup -S -g 1001 nodejs \
 && adduser -S -u 1001 -G nodejs nextjs \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /opt/yarn* /usr/local/bin/yarn*

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:3000/ || exit 1

CMD ["node", "server.js"]
