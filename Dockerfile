FROM node:24.21.0-alpine AS source

RUN apk add --no-cache git

WORKDIR /app

# Renovate-managed commit SHA of the stable upstream release branch.
# Renovate only exposes upstream commits after a seven-day waiting period.
# renovate: datasource=custom.github-stats-extended-aged depName=github-stats-extended packageName=stats-organization/github-stats-extended currentValue=0
ARG GSE_REF=9313d3da7957d09befa2cc620b137c1ba05de096

# 1) Clone upstream repo
RUN git clone https://github.com/stats-organization/github-stats-extended.git . \
  && git checkout "${GSE_REF}"

FROM source AS builder

# 2) Install the pinned pnpm workspace and build the shared core package.
RUN corepack enable \
  && pnpm install --frozen-lockfile --ignore-scripts \
  && pnpm run build:packages

# 3) Promote upstream's exact Express version to a runtime dependency, then
# deploy only the backend and its production dependencies.
RUN node -e 'const fs = require("fs"); const path = "apps/backend/package.json"; const pkg = JSON.parse(fs.readFileSync(path)); const version = pkg.dependencies?.express ?? pkg.devDependencies?.express; if (!version) throw new Error("Upstream no longer declares express"); pkg.dependencies = { ...pkg.dependencies, express: version }; if (pkg.devDependencies) delete pkg.devDependencies.express; fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");' \
  && pnpm --ignore-scripts --filter @stats-organization/github-readme-stats-backend --prod deploy --legacy /prod/backend

FROM source AS frontend-builder

# Self-hosted wizard: guests edit every field and previews come from this instance's /api.
COPY patches/ /tmp/patches/
RUN git apply /tmp/patches/*.patch

# Samples used by the wizard and the docs; the whitelist must allow them.
# Empty gist / WakaTime values keep upstream's samples.
ARG DEMO_USER=Tsabo
ARG DEMO_REPO=Tsabo/ClipMate
ARG DEMO_GIST=
ARG DEMO_WAKATIME_USER=
# Client ID of this instance's GitHub OAuth app (public). Empty hides the login step.
# The backend needs OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, OAUTH_REDIRECT_URI and POSTGRES_URL at runtime.
ARG OAUTH_CLIENT_ID=Ov23li6uNhWZqxFwH7Ci

# Point the docs' example cards at the samples instead of upstream's author.
RUN find apps/frontend/src/content/docs -name '*.md' -exec sed -i -E \
    -e "s#username=anuraghazra&repo=[A-Za-z0-9_.-]+#username=${DEMO_REPO%%/*}\\&repo=${DEMO_REPO#*/}#g" \
    -e "s#username=anuraghazra#username=${DEMO_USER}#g" \
    -e "${DEMO_GIST:+s#id=bbfce31e0217a3689c8d961a356cb10d#id=${DEMO_GIST}#g}" \
    {} +

# Build the static docs + card wizard site (served under /frontend).
# Install scripts must run here: esbuild and friends need their native binaries.
ENV HUSKY=0 \
  PUBLIC_SELF_HOSTED=true \
  PUBLIC_DEMO_USER=${DEMO_USER} \
  PUBLIC_DEMO_REPO=${DEMO_REPO} \
  PUBLIC_DEMO_GIST=${DEMO_GIST} \
  PUBLIC_DEMO_WAKATIME_USER=${DEMO_WAKATIME_USER} \
  PUBLIC_OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID}
RUN corepack enable \
  && pnpm install --frozen-lockfile \
  && pnpm run build:packages \
  && pnpm run build:frontend

FROM nginxinc/nginx-unprivileged:1.31.6-alpine AS web
LABEL org.opencontainers.image.source="https://github.com/GeorgesAlkhouri/github-readme-stats-selfhosted" \
  org.opencontainers.image.description="Docs, card wizard and /api reverse proxy for stats-organization/github-stats-extended" \
  org.opencontainers.image.licenses="MIT"

# host:port of the backend (runtime) container; substituted into the nginx template at startup.
ENV BACKEND_HOST=github-readme-stats:9000

COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=frontend-builder /app/apps/frontend/build /usr/share/nginx/html/frontend

EXPOSE 8080

FROM node:24.21.0-alpine AS runtime
LABEL org.opencontainers.image.source="https://github.com/GeorgesAlkhouri/github-readme-stats-selfhosted" \
  org.opencontainers.image.description="Hardened, reproducible Docker image for stats-organization/github-stats-extended" \
  org.opencontainers.image.licenses="MIT"

RUN addgroup -S app && adduser -S -G app app

WORKDIR /app

COPY --from=builder /prod/backend /app

ENV NODE_ENV=production \
  PORT=9000

EXPOSE 9000

USER app

CMD ["node", "express.js"]
