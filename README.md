# github-readme-stats-selfhosted

[![CI](https://github.com/GeorgesAlkhouri/github-readme-stats-selfhosted/actions/workflows/ci.yaml/badge.svg)](https://github.com/GeorgesAlkhouri/github-readme-stats-selfhosted/actions/workflows/ci.yaml)
[![CodeQL](https://github.com/GeorgesAlkhouri/github-readme-stats-selfhosted/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/GeorgesAlkhouri/github-readme-stats-selfhosted/actions/workflows/github-code-scanning/codeql)
[![Release](https://img.shields.io/github/v/release/GeorgesAlkhouri/github-readme-stats-selfhosted?sort=semver)](https://github.com/GeorgesAlkhouri/github-readme-stats-selfhosted/releases)
[![License](https://img.shields.io/github/license/GeorgesAlkhouri/github-readme-stats-selfhosted)](./LICENSE)

> Self-hosted Docker image for [stats-organization/github-stats-extended](https://github.com/stats-organization/github-stats-extended),
> so you can serve your own GitHub stats cards without Vercel.

---

## ✨ What this repo gives you

Self-hosted build of GitHub Stats Extended, the actively maintained successor to github-readme-stats. It is packaged as a multi-arch Docker image (amd64/arm64) and synced with the stable upstream release branch after a seven-day waiting period. Images are automatically published to Docker Hub and GHCR for easy deployment on your own infra (Docker, Podman, Kubernetes, etc.).

> Note: Image versions here are **independent of upstream tags**. Upstream doesn’t provide up-to-date releases, so this repo maintains its own semantic versions for published images. We use a semantic-style versioning scheme of `1.X.0`. Minor (`X`) increases track upstream changes; the major version only bumps if something unexpected and breaking happens.

If you just want the public service, use GitHub Stats Extended.
This repo is for people who like to own their infra. 😈

## 📦 Images

| Image | Dockerfile target | What it serves |
| --- | --- | --- |
| `github-readme-stats-selfhosted` | `runtime` | The card API (`/api`, `/api/pin`, `/api/top-langs`, …) on port `9000` |
| `github-readme-stats-selfhosted-web` | `web` | The docs (`/frontend/docs`) and card wizard (`/frontend`) on port `8080`, and proxies `/api` to the backend |

The wizard builds card URLs from the host it is served on, so it must share an origin with `/api` — put the `web` image in front and expose only it.
Set `BACKEND_HOST` (default `github-readme-stats:9000`) if your backend container has a different name.

The wizard's GitHub login is tied to the upstream OAuth app and does not work on a self-hosted instance; generating public cards does.

## 🚀 Example `docker-compose.yml`

```yaml
services:
  github-readme-stats:
    image: ghcr.io/georgesalkhouri/github-readme-stats-selfhosted:latest
    restart: unless-stopped
    environment:
      PAT_1: ${GITHUB_PAT}
      # Exact, case-sensitive match on the `username` query parameter.
      WHITELIST: "your-username"
      # Gist IDs, not usernames.
      # GIST_WHITELIST: "bbfce31e0217a3689c8d961a356cb10d"

  web:
    image: ghcr.io/georgesalkhouri/github-readme-stats-selfhosted-web:latest
    restart: unless-stopped
    depends_on:
      - github-readme-stats
    ports:
      - "8080:8080"
```

Then open `http://localhost:8080/frontend/` for the wizard or request `http://localhost:8080/api?username=your-username`.

## 🧙 Self-hosted wizard

The `web` image applies [`patches/frontend-self-hosted.patch`](patches/frontend-self-hosted.patch) to the upstream frontend:
guests skip the (upstream-only) login, can edit every field, and previews are rendered by this instance's `/api` instead of in-browser mock data.
The docs' example cards are rewritten to the same sample user and repo.

| Build arg | Default | Used for |
| --- | --- | --- |
| `DEMO_USER` | `Tsabo` | Default username in the wizard and docs |
| `DEMO_REPO` | `Tsabo/ClipMate` | Default repo pin in the wizard and docs |
| `DEMO_GIST` | upstream sample | Default gist in the wizard and docs |
| `DEMO_WAKATIME_USER` | upstream sample | Default WakaTime user in the wizard |

The samples must pass your `WHITELIST` / `GIST_WHITELIST`, or their previews show a "not whitelisted" card.
If an upstream bump touches the patched files, `git apply` fails the build; regenerate the patch against the new `GSE_REF`.
