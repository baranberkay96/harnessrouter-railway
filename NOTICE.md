# Notice

## Upstream software

This repository contains Railway configuration and one start script. HarnessRouter Community Edition is pulled from its publisher's container image and is not stored or modified here. This is a community template, not affiliated with or endorsed by HarnessRouter.

| Software | License | Used as |
|---|---|---|
| HarnessRouter Community Edition 0.38.2 (console, gateway, runner) | Apache License 2.0, "HarnessRouter, Copyright (c) 2026 HarnessRouter" (upstream `NOTICE`) | Image `docker.io/harnessrouter/harnessrouter:0.38.2@sha256:444e92aab1bce6046e404570376faadc71154f98dbd0210dee379b9488f15b00`, used as the base of a one-file repo build. Upstream's `LICENSE`, `NOTICE` and `THIRD-PARTY-console.txt` ship inside the image under `/app`. |
| Third-party components inside the image (Debian, Python 3.12, Node.js 22, FastAPI, Next.js, LibreOffice, ffmpeg, built-in skills and starter kits, …) | Their own licenses | Listed in upstream's `NOTICE` and `/app/THIRD-PARTY-console.txt` inside the image; starter kits have separate terms (https://github.com/HarnessRouter/starter-kit#licensing). |
| HarnessRouter logo (template icon) | Upstream repository asset | Referenced by URL from `cdn.jsdelivr.net/gh/HarnessRouter/harnessrouter@v0.38.2/ui/public/harnessrouter-logo.svg`; not copied. |

## Agent CLIs installed at run time (not redistributed)

Upstream's entrypoint downloads the agent CLIs named in `HR_BACKENDS` into the deployment's own volume on first start. They are not in the image or in this repository, and each stays under its own terms. Default set and licenses as stated by upstream's `NOTICE` and the package registries (checked 2026-11-07):

| Base | Package | License |
|---|---|---|
| claude | `@anthropic-ai/claude-code` 2.1.280 | Anthropic's own terms ("SEE LICENSE IN README.md") |
| codex | `@openai/codex` 0.154.0 | Apache-2.0 |
| hermes | `hermes-agent[anthropic]` 0.19.0 | MIT |
| pi | `@earendil-works/pi-coding-agent` (latest at first start) + `pi-mcp-adapter` 3.1.0 | MIT |
| dsh | `deepseek-harness-sdk` / `deepseek-harness-runtime-bin` 0.1.2rc1 | MIT |
| opencode | GitHub release binary (latest at first start) | MIT |
| qwen | `@qwen-code/qwen-code` (latest at first start) | Apache-2.0 (QwenLM/qwen-code repository) |
| gemini | `@google/gemini-cli` 0.58.0 | Apache-2.0 |
| cline | `cline` 3.0.60 | Apache-2.0 |
| omp | Oh My Pi 18.1.13 release binary | MIT |

Review each tool's license before enabling more bases.

## External services and terms (not legal advice)

- Model providers (Anthropic, OpenAI, Google, OpenRouter and others) are used with the deployer's own API keys and under each provider's terms and usage policies. HarnessRouter CE uses API keys; consumer subscriptions (Claude Pro/Max, ChatGPT plans) are not a supported credential here, and their terms generally do not cover powering an API service.
- Railway's Fair Use Policy (https://railway.com/legal/fair-use) applies to anything the agents run.
- This summary is practical guidance, not legal advice. Check the providers' current terms, or ask a lawyer, before using this for a customer-facing product.

## Verified against

| What | Upstream file / source | Ref | Checked |
|---|---|---|---|
| Release, tag commit | GitHub release `v0.38.2` (published 2026-11-04T22:53:50Z) | `8e1cf1b598a7ea864fda3a5de064b11289b6ac84` | 2026-11-07 |
| Local upstream copy is that release | git blob hashes of `docker/entrypoint.sh`, `Dockerfile`, `runner/server.py`, `README.md`, `docs/self-hosting-guide.md` equal the tag's | `v0.38.2` | 2026-11-07 |
| Image tag, digest, platforms, config | Docker Hub tags API; registry manifests (HEAD 200 by tag and by digest); amd64 config (entrypoint `tini -- /app/entrypoint.sh`, `VOLUME /data`, `EXPOSE 3000`, `HR_VERSION=0.38.2`, built 2026-11-04T22:39Z, skills ref `1553417d`, kits ref `9fe6ba18`) | `0.38.2` | 2026-11-07 |
| Startup, privilege drop, auth bootstrap, secret key, CLI installs, process supervision | `docker/entrypoint.sh` | `v0.38.2` | 2026-11-07 |
| Session isolation (per-session uids, setfsuid, file modes, uid ranges) | `runner/server.py` (`_isolate_session`, `_fs_as`, `_as_session`, `_child_env`), `runner/environments.py` | `v0.38.2` | 2026-11-07 |
| Harness sandbox modes | `runner/server.py` (Codex config template, Claude flags), `runner/dsh_driver.py` | `v0.38.2` | 2026-11-07 |
| Sign-in gate, public paths, API proxy, login | `ui/src/middleware.ts`, `ui/src/app/api/harness/[...path]/route.ts`, `ui/src/app/api/selfhost/login/route.ts`, `ui/src/lib/selfhost-auth.ts` | `v0.38.2` | 2026-11-07 |
| UHP discovery, healthz, concurrency, env connections and policies, chain fallback | `gateway/app.py` (`/v1/uhp`, `_conc_limit`, `_resolve_chain`, `_chain_refusal`, `_servable_models`, candidate loop), `gateway/backing.py` (`FileSecretStore._env_key`) | `v0.38.2` | 2026-11-07 |
| Install, configuration, API, public URL, backups, retention | `README.md`, `docs/self-hosting-guide.md`, `.env.example`, `docker-compose.yml`, `SECURITY.md`, `NOTICE` | `v0.38.2` | 2026-11-07 |
| CLI package versions and sizes | npm registry (`@anthropic-ai/claude-code@2.1.280`, `@openai/codex@0.154.0` and `-linux-x64`, `@google/gemini-cli@0.58.0`, `cline@3.0.60`, `pi-mcp-adapter@3.1.0`, `@qwen-code/qwen-code`, `@earendil-works/pi-coding-agent`), PyPI (`hermes-agent==0.19.0`, `deepseek-harness-*==0.1.2rc1`) | — | 2026-11-07 |
| Railway behaviour | docs.railway.com: public networking limits (5 min idle / 15 min max request), healthchecks (PORT, default 300 s, `healthcheck.railway.app`), volumes (Hobby 5 GB, no overlapping deployments) | — | 2026-11-07 |

## Our files

| File | Origin |
|---|---|
| `services/harnessrouter/Dockerfile`, `services/harnessrouter/railway-entrypoint.sh`, `template.json`, `TEMPLATE.md`, `README.md`, `NOTICE.md` | Written for this template. The start script sets environment variables that upstream documents or reads (`HARNESS_GLOBAL_CONCURRENCY`, `HR_SESSION_UID_BASE`, `HR_SECRET_GLOBAL_HARNESS_*`) and contains no upstream code. |

## Reference only (not copied)

- Railway templates `harnessrouter`, `harnessrouter-1`, `harnessrouter-2`, `deploy-harnessrouter`, `deploy-harnessrouter-codex-cli-as-api` (0 projects each): configuration read through Railway's public API; nothing copied.
- Upstream README and docs were read for behaviour; no prose was copied.

## Trademarks

HarnessRouter is a name and mark of its owners. Claude and Claude Code (Anthropic), Codex and ChatGPT (OpenAI), Gemini (Google), Hermes (Nous Research), OpenRouter and Railway belong to their respective owners. Naming them describes compatibility only; this community template is not affiliated with or endorsed by any of them.
