# Deploy and Host HarnessRouter with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/harnessrouter-v038-api-for-coding-agents?referralCode=20H68q)

HarnessRouter Community Edition (Apache-2.0) puts agent harnesses such as Codex, Claude Code, Hermes and Pi behind one OpenAI Responses-compatible API and a web console. This community template runs release 0.38.2 from upstream's published image, pinned by digest, with a persistent volume, a generated login and your own provider keys.

## About Hosting HarnessRouter

HarnessRouter runs three processes in one container: the console on port 3000, the gateway (the Responses API, sessions, files, streaming) and the runner, which starts each agent CLI as its own Linux user in its own workspace. Self-hosting it means a root container that can switch users, a volume for its SQLite databases, files and the CLIs it installs at first start, TLS in front of the console, a strong password and a key that encrypts stored credentials. This template sets all of that up on Railway: HTTPS domain, `/data` volume, generated password and encryption key, a healthcheck through the console to the gateway, and turn concurrency sized to the service's CPU limit instead of the host's.

## Common Use Cases

- Add agent features to your product (code changes, reports, documents, data tasks) through one API, and switch harnesses per request with `metadata.harness_id`
- Compare Codex, Claude Code, Hermes, Pi, OpenCode and others on the same task, model and files from the console
- Build and test custom harnesses (instructions, skills, MCP tools, environments) before calling them from a backend
- Run the HarnessRouter starter kits (slides, sheets, dashboards, videos) on your own infrastructure

## Dependencies for HarnessRouter Hosting

- HarnessRouter Community Edition 0.38.2 (`harnessrouter/harnessrouter` image)
- A Railway volume at `/data` (included)
- At least one model provider API key (Anthropic, OpenAI, Google AI Studio, OpenRouter, Azure, Bedrock or any compatible endpoint), added in the console or as a variable

### Deployment Dependencies

- Source and release: https://github.com/HarnessRouter/harnessrouter/releases/tag/v0.38.2
- Setup and operations guide: https://github.com/HarnessRouter/harnessrouter/blob/v0.38.2/docs/self-hosting-guide.md
- Image: https://hub.docker.com/r/harnessrouter/harnessrouter
- Unified Harness Protocol: https://unifiedharnessprotocol.org
- Railway request limits: https://docs.railway.com/networking/public-networking/specs-and-limits
- Railway Fair Use Policy: https://railway.com/legal/fair-use

### Implementation Details

| Service | Source | Purpose |
|---|---|---|
| HarnessRouter | Upstream image 0.38.2 (digest-pinned) plus a small start script | Console and API on port 3000 (public), gateway and runner on loopback only, volume at `/data`, healthcheck `/api/harness/v1/uhp` |

**First start takes a few minutes.** Upstream installs the agent CLIs listed in `HR_BACKENDS` into the volume before the console opens (the logs show `ready on :3000`). Later starts reuse them.

**Sign in**

1. Open the service's public URL.
2. Sign in as `harnessrouter` with the `HR_AUTH_PASSWORD` value from the service's Variables tab.
3. Optional: set your own password under Profile. It is stored on the volume and replaces the variable from then on. Forgot it? Delete `/data/selfhost-auth.json` (`railway ssh`) and restart the service to fall back to the variables.

**Connect a model provider.** Open the account menu, choose **Bring your own key**, pick the provider and paste its API key; it is encrypted at rest with `HR_SECRET_KEY`. Or set `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` or `OPENROUTER_API_KEY` on the service: the start script turns them into HarnessRouter's documented environment connections, used after any key added in the console. HarnessRouter works with provider API keys; it does not use Claude or ChatGPT subscription logins. Then open **Start**, describe your agent and send the example request.

**Call the API from your backend**

1. In the console open **API Keys**, create a key and store it in your backend (never in browser code).
2. Base URL: `https://{your-domain}/api/harness`. OpenAPI document at `/api/harness/v1/openapi.json`.

```bash
curl -sS "https://{your-domain}/api/harness/v1/responses" \
  -H "Authorization: Bearer $HARNESSROUTER_API_KEY" -H 'content-type: application/json' \
  -d '{"input":"Reply with exactly: it works.","metadata":{"harness_id":"codex"},"model":"gpt-5.4-mini","background":true}'
```

Railway's edge closes a request after 5 minutes without data and after 15 minutes in total. Agent turns often take longer, so use `"background": true` and poll `GET /v1/responses/{id}`, or `"stream": true` for turns under 15 minutes. A plain synchronous call is fine only for short turns.

**Harnesses and disk.** The console lists every base HarnessRouter supports, but only those in `HR_BACKENDS` are installed. The default (`claude,codex,hermes,pi,dsh,opencode,qwen,gemini,cline,omp`, an estimated 1.5 to 2.5 GB) fits Hobby's 5 GB volume with room for workspaces. A task on a base that is not installed fails on its first turn. To add more, extend the list and redeploy, for example `goose,kimi,kilo,grok,minimax,mimo,jcode,nanobot,zeroclaw,vibe,fast-agent,dcode,docker-agent,opensquilla,qoder,systemone,cheetahclaws` and the large `aider`, `openhands`, `agentzero` (600 to 750 MB each). The full set needs more than 5 GB, so use a Pro plan and a larger volume. A long install list can exceed the 20-minute healthcheck window on the first start; add a few at a time. Each CLI is downloaded by your deployment under its own license and terms.

**Isolation.** Agents run with full shell access inside the container. Each session runs as its own Linux user that can write only its own workspace; the CLIs' built-in sandboxes are off upstream because the container is the boundary. This needs only standard container capabilities, no privileged mode. Agents can reach the internet and this project's private network, so keep databases you do not want agents to reach in another project, and give each harness only the tools and keys it needs. During a turn an agent can spend through your provider key, so set a spending limit with your provider.

**Scaling.** One replica only: the volume holds the SQLite databases and workspaces. Raise CPU and RAM in the service settings. By default at most 2 to 4 turns run at once (from the CPU limit); set `HARNESS_GLOBAL_CONCURRENCY` to change it, and plan roughly 0.5 to 1 GB RAM per running turn (more when agents build or test code).

**Pinning and upgrades.** The image tag and digest are in `services/harnessrouter/Dockerfile`. Back up the volume (Railway volume backups), change both, redeploy. Keep `HR_SECRET_KEY` unchanged forever. Retention commands: `railway ssh`, then `hr-retention` or `hr-retention sweep`.

**Fair use.** This template is for your own development work: building and testing agent features with your own provider keys. Do not use it for cryptocurrency mining, proxies or VPNs, scraping that breaks site terms, or reselling access to the instance. Railway's Fair Use Policy and each model provider's terms apply, and violations can get an account suspended.

This is a community template. It is not affiliated with or endorsed by HarnessRouter, Anthropic, OpenAI or Google.

### Why Deploy HarnessRouter on Railway?

Railway gives HarnessRouter an HTTPS domain, a persistent volume and usage-based billing without a server to maintain. You get a private agent API and console for your own keys in a few minutes, and you pay for the CPU and memory your agents actually use.
