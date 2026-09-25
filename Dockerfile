# syntax=docker/dockerfile:1
# Multi-stage image for this checkout: install, build, then run `dsh web`
# with docker/web.cordis.yml so the process listens on 0.0.0.0 inside the
# container. docker-compose.yml publishes 127.0.0.1:3080:3080 by default.

ARG NODE_VERSION=22

FROM node:${NODE_VERSION}-bookworm-slim AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV CI=true \
  COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
  NODE_OPTIONS=--max-old-space-size=8192 \
  PNPM_HOME=/pnpm \
  PATH=/pnpm:$PATH

RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

WORKDIR /opt/dsh
COPY . .

RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
  pnpm install --frozen-lockfile --store-dir /pnpm/store

# tsdown globs vendor/*, packages/*/*, apps/cli. A directory in that glob
# without package.json inherits the root entry lib/types/{index,invariant,startup}.js
# and the root package name. Deleted packages leave such directories on a
# host tree (only gitignored lib/ and node_modules remain); COPY still
# creates the empty directory, and a clean image then fails resolveEntry.
RUN for dir in vendor/* packages/*/*; do \
      if [ -d "$dir" ] && [ ! -f "$dir/package.json" ]; then rm -rf "$dir"; fi; \
    done

# `.dockerignore` excludes `.git`, so `git rev-parse HEAD` cannot run here.
# `pnpm run build` accepts DSH_CLIENT_COMMIT_HASH instead (7–40 hex chars).
ARG DSH_CLIENT_COMMIT_HASH=0000000
ENV DSH_CLIENT_COMMIT_HASH=$DSH_CLIENT_COMMIT_HASH
RUN pnpm run build

FROM node:${NODE_VERSION}-bookworm-slim AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends git bash python3 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder --chown=node:node /opt/dsh /opt/dsh

RUN mkdir -p /workspace /home/node/.dsh \
  && chown node:node /workspace /home/node/.dsh

ENV DSH_HOME=/home/node/.dsh \
  HOME=/home/node

WORKDIR /workspace
USER node
EXPOSE 3080

HEALTHCHECK --interval=15s --timeout=5s --start-period=90s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:3080/').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["node", "/opt/dsh/apps/cli/lib/bin.js"]
CMD ["web", "--patch", "/opt/dsh/docker/web.cordis.yml"]
