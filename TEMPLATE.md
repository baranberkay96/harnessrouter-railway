# HarnessRouter v0.38 API for Coding Agents (Codex, Claude Code): Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **HarnessRouter v0.38 API for Coding Agents (Codex, Claude Code)** (62 chars; 0.x release, so major.minor) |
| Description | Self-hosted API and console for Codex, Claude Code, Hermes and Pi agents. (73 chars) |
| Category | AI/ML |
| Tags | harnessrouter, coding-agents, ai-agents, codex, claude-code, hermes, openai-responses, agent-api, uhp |
| Icon | `https://cdn.jsdelivr.net/gh/HarnessRouter/harnessrouter@v0.38.2/ui/public/harnessrouter-logo.svg` (upstream's logo, pinned to the release tag, 200 `image/svg+xml`) |
| Repo | `baranberkay96/harnessrouter-railway`, service root `/services/harnessrouter` |

All four agents named in the description are installed by the default `HR_BACKENDS`. The README and NOTICE say this is a community template, not affiliated with HarnessRouter.

## Base market templates

Railway already lists five HarnessRouter templates, all with 0 projects (public API, 2026-11-07). None was copied; they were read for what to avoid:

| Code | Image | Notes |
|---|---|---|
| `harnessrouter`, `harnessrouter-1` | `harnessrouter/harnessrouter:0.20.1` | ~50 releases old, no healthcheck, no `HR_SECRET_KEY` |
| `harnessrouter-2` | `harnessrouter/harnessrouter:0.36.0@sha256:…` | Healthcheck `/login` (console only), `HR_BACKENDS=claude,codex,opencode`, 600 s healthcheck window |
| `deploy-harnessrouter`, `deploy-harnessrouter-codex-cli-as-api` | `ghcr.io/onepush-dev/harnessrouter:0.37.13` | Third-party rebuild, not upstream's image; healthcheck `/login` |

## Pinned versions

| Component | Pin | Source |
|---|---|---|
| HarnessRouter CE | `docker.io/harnessrouter/harnessrouter:0.38.2@sha256:444e92aab1bce6046e404570376faadc71154f98dbd0210dee379b9488f15b00` (index; amd64 `sha256:6aa91057…5723`, built 2026-11-04 22:39 UTC, `HR_VERSION=0.38.2`) | Docker Hub registry API; tag `v0.38.2` = commit `8e1cf1b5`, released 2026-11-04 |
| Claude Code | 2.1.280 (npm) | upstream entrypoint pin (`CLAUDE_CODE_VERSION`) |
| Codex | 0.154.0 (npm) | upstream pin (`HR_CODEX_VERSION`) |
| Gemini CLI | 0.58.0 | upstream pin (`HR_GEMINI_VERSION`) |
| Cline | 3.0.60 | upstream pin (`HR_CLINE_VERSION`) |
| Oh My Pi | 18.1.13 (SHA-256 checked) | upstream pin (`HR_OMP_VERSION`) |
| Hermes | `hermes-agent[anthropic]==0.19.0` | upstream pin |
| DeepSeek Harness | 0.1.2rc1 | upstream pin |
| Pi, Qwen Code, opencode | newest release at the volume's first start | upstream installs these unpinned (`HR_OPENCODE_VERSION` can pin opencode) |

The CLIs are installed by upstream's entrypoint into `/data/agent-tools` on the first start (not baked into the image, for licensing reasons) and reused afterwards. Pinned ones are replaced when the image moves the pin.

## Architecture

```
 Browser / your backend ── HTTPS (Railway edge) ──► :3000 console (Next.js, sign-in gate)
                                                      │ /api/harness/* same-origin proxy
 ┌─ HarnessRouter service (repo build: upstream image + start script) ─────────────────┐
 │ podman-init (PID 1) → tini (subreaper) → hr-railway-entrypoint → /app/entrypoint.sh │
 │   console  :3000  as 'agent' (uid 10001)                                           │
 │   gateway  127.0.0.1:8080  as 'agent'   Responses API, sessions, files, keys      │
 │   runner   127.0.0.1:8081  as root      starts each agent CLI as its session uid  │
 │   agent CLIs as hs20000, hs20001, …  each owning /data/workspaces/{session} 0700   │
 │ volume /data: SQLite DBs, blobs, encrypted secrets, workspaces, agent-tools         │
 └─────────────────────────────────────────────────────────────────────────────────────┘
```

## Isolation on Railway (the key question)

Read in `docker/entrypoint.sh`, `runner/server.py` (`_isolate_session`, `_fs_as`, `_as_session`, `_ensure_passwd`), `runner/environments.py` and `docs/self-hosting-guide.md` at v0.38.2:

- **Mechanism: Linux users and file modes only.** The runner (root) gives every session its own uid from 20000 up (`useradd`/`groupadd`, `chown`, `chmod 0700`), spawns the CLI with `user=`/`group=`, and does its own writes into a session tree under `setfsuid`/`setfsgid` so planted links cannot redirect a root write. Console and gateway drop to `agent` with `setpriv`. `/tmp`, `/var/tmp` and `/dev/shm` become mode 1733. Environments (Build > Environments) are root-owned with a group per environment (ids 60000-99999).
- **No namespaces, no bubblewrap, no seccomp profile, no cgroup writes, no mounts.** Upstream states it needs only Docker's default capability set ("no `--privileged`, no `--cap-add`, no custom seccomp profile"); the calls it makes need CAP_SETUID, CAP_SETGID and CAP_CHOWN (upstream names these) and, by our reading, CAP_FOWNER and CAP_DAC_OVERRIDE for root handling session-owned files. All five are in Docker's and podman's defaults. The harnesses' own sandboxes are switched off upstream (Codex `sandbox_mode = "danger-full-access"`, Claude Code `--dangerously-skip-permissions`, DeepSeek Harness `DSH_PERMISSION_MODE=danger-full-access`, which otherwise refuses to run without bubblewrap or Landlock); the container is the boundary. So nothing upstream requires is outside what a Railway container has, and **nothing is reduced** compared with upstream's documented `docker run`.
- **What Railway could still differ in, and how the template handles it:** Railway runs containers under podman (podman-init is PID 1). Podman's default capability set contains all of the above, and our other templates already rely on root switching users on Railway (sshd, `setpriv`, `gosu`). The unknown is the size of the uid map: if Railway used a user namespace smaller than ~21,000 ids, session users at 20000+ could not be created. The start script logs `CapEff` and the mapped id range on every start; if 20000+ is unmapped but 10002+ is, it sets `HR_SESSION_UID_BASE=10002` (a runner setting, just above the product user 10001), otherwise it logs a clear warning. Ids 60000-99999 for Environments are checked and warned about the same way (Environments are optional).
- **What the isolation does not give:** sessions share the kernel, the network and the container's CPU/RAM. Agents can reach the internet and this project's private network, and during a turn they can use the provider key and tools they are given. This is upstream's stated model ("not a separate sandbox or container per session") and is in the README.

## Design decisions

- **Upstream image, thin repo build.** `FROM` the digest-pinned image, add `/usr/local/bin/hr-railway-entrypoint` (root-owned), set `TINI_SUBREAPER=1`, and keep tini as the entrypoint. The wrapper execs `/app/entrypoint.sh` unchanged. Inherited `VOLUME /data` is fine for Railway's builder (our published MongoDB and Valkey templates build `FROM` images that declare `VOLUME`); the package's own Dockerfile has none.
- **Healthcheck `/api/harness/v1/uhp`.** Public by design (UHP discovery) in the console's middleware, proxied to the gateway's `/v1/uhp`, so it proves both console and gateway are up (upstream's own Docker HEALTHCHECK probes the loopback gateway, which Railway cannot reach). `/login` would only prove Next.js is up. Timeout 1200 s because upstream installs the CLIs before the console listens.
- **Auth: HarnessRouter's own.** Console sign-in gate (`HR_AUTH_USER` / `HR_AUTH_PASSWORD`, 32-char generated password, session cookie signed from it, 400 ms delay on failures), and console-issued `sk-hr-…` API keys for `/api/harness/*`. No basic-auth front: it would block bearer API calls, UHP discovery and share links that upstream designed to bypass the cookie gate. A password changed under Profile is stored in `/data/selfhost-auth.json` and wins over the variable (upstream behaviour, documented).
- **`HR_SECRET_KEY` generated** (48 chars) so stored provider keys and MCP tokens are encrypted under a key kept outside the volume (upstream's recommendation); otherwise upstream writes `/data/secret-key` beside the data.
- **Provider keys:** the console's "Bring your own key" is the primary path. As optional variables, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY` are converted by the start script into upstream's documented environment connections (`HR_SECRET_GLOBAL_HARNESS_CONN_<NAME>`, JSON built with Python's `json.dumps`) and one policy chain per base (`HR_SECRET_GLOBAL_HARNESS_POLICY_<BASE>`, order anthropic, openai, google, openrouter). Verified in `gateway/app.py`: console integrations run first and the chain is the fallback; chain entries that cannot drive a base or serve the model are skipped (`_chain_refusal`, `_conn_serves`); model pickers include chain connections (`_servable_models`). Explicitly set `HR_SECRET_GLOBAL_HARNESS_*` variables are never overwritten. The plain variables are unset before upstream starts; the runner also strips `*_API_KEY` and `*_SECRET_*` names from agent environments. Subscription logins (Claude Pro/Max, ChatGPT) are not supported by HarnessRouter CE; the README says so.
- **`HR_BACKENDS` default = upstream's previous default of 10** (`claude,codex,hermes,pi,dsh,opencode,qwen,gemini,cline,omp`, still documented in the v0.38.2 Dockerfile header). Upstream's current default installs 30 bases; from upstream's size notes (Aider ~735 MB, OpenHands ~666 MB, Agent Zero ~640 MB, Kilo 228 MB, Grok ~166 MB, …) and npm package sizes (Codex linux-x64 339 MB, Claude Code linux-x64 234 MB, Qwen 156 MB, Gemini 98 MB) that is an estimated 5-6 GB, more than Hobby's 5 GB volume. The 10 are an estimated 1.5-2.5 GB. Trade-off: the console still lists all bases, and one not installed fails on its first turn; the README explains how to add more.
- **Concurrency from the CPU limit.** Upstream caps concurrent turns at `os.cpu_count()`, the host's cores on Railway (Rule 8.15). The script reads `cpu.max` (or the v1 CFS quota), sets `HARNESS_GLOBAL_CONCURRENCY` to that number clamped to 2-4 unless set, and `OMP_NUM_THREADS` to 1-8 (so `nproc` and BLAS inside agent shells follow the quota). Extra turns wait on the gateway's semaphore; they are not rejected.
- **Railway request limits.** The edge closes requests after 5 minutes without data and 15 minutes in total. Upstream's `stream:false` example would be cut on long turns; the README uses `"background": true` and polling. Gateway and console timeouts stay at upstream's values.
- **Left at upstream defaults:** `HR_SANDBOX_TRUST=owner`, `HARNESS_CODEX_APPSERVER=1`, `HARNESS_PUBLIC_BASE_URL` unset (self-hosted agents reach the gateway on loopback; setting the public URL would route them through the sign-in gate), `WITH_BROWSER=0` image (no Chromium).
- **One replica, restart `ALWAYS`.** SQLite and workspaces are on the volume. Upstream exits the container when any of its processes dies, possibly with status 0, so `ON_FAILURE` could leave it down. `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=30` for a clean stop.

## Services

### HarnessRouter

| Setting | Value |
|---|---|
| Source | repo `baranberkay96/harnessrouter-railway`, root `/services/harnessrouter` (Dockerfile) |
| Start | image entrypoint: `tini -- hr-railway-entrypoint` → `/app/entrypoint.sh` |
| Healthcheck | `/api/harness/v1/uhp`, timeout 1200 s |
| Public domain | yes, target port 3000 |
| Volume | `/data` |
| Restart | ALWAYS |
| Replicas | 1 |

Files: `services/harnessrouter/Dockerfile`, `services/harnessrouter/railway-entrypoint.sh`.

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `3000` | Console port; healthcheck and domain use it |
| `HR_AUTH_USER` | `harnessrouter` | Console username |
| `HR_AUTH_PASSWORD` | `secret(32)` (unambiguous alphabet) | Console password; Profile overrides |
| `HR_SECRET_KEY` | `secret(48)` | Encrypts stored credentials; never change |
| `HR_BACKENDS` | 10 bases above | Installed CLIs |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY` | empty | Optional environment connections |
| `HARNESS_GLOBAL_CONCURRENCY` | empty (auto 2-4) | Turn cap |
| `HR_WORKSPACE_TTL_HOURS` | `72` | Idle workspace cleanup (upstream default) |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Clean shutdown |

No required inputs: the template boots without provider keys, and the console asks for one before the first task.

## First login

1. Wait for `ready on :3000` in the deploy logs (first start installs the CLIs; healthcheck goes green after it).
2. Open the public URL, sign in as `harnessrouter` with `HR_AUTH_PASSWORD`.
3. Account menu → Bring your own key → add a provider (or set one of the key variables and redeploy).
4. Start → describe the agent → send the example request. For the API: API Keys → create → `https://{domain}/api/harness/v1/responses` with `"background": true`.

## Improvements over market templates

1. Current release 0.38.2 from upstream's own image, pinned by tag and digest (others: 0.20.1, 0.36.0, or a third-party rebuild).
2. Readiness healthcheck through console and gateway, with a window that fits the first-start installs.
3. Turn concurrency and thread counts sized to the service's CPU limit, not the host's cores.
4. Preflight log for capabilities and uid mapping, with a fallback session-uid range.
5. Optional provider-key variables wired into upstream's environment connections, without breaking console-added keys.
6. Generated `HR_SECRET_KEY` and 32-char password; tini as subreaper under Railway's init; draining period.
7. A default harness set that fits Hobby's volume, with disk guidance, and documented Railway request limits for the API.

## Scaling

Vertical only (one replica with a volume). Concurrency is the knob: `HARNESS_GLOBAL_CONCURRENCY`. Budget roughly 0.5-1 GB RAM per running turn plus whatever the agent builds or tests. For many parallel users, run several projects or move to HarnessRouter Cloud; CE has no horizontal mode.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Estimates, not measured.

| State | RAM | CPU | Volume | $/month |
|---|---|---|---|---|
| Idle (console + gateway + runner, no turns) | ~0.5 GB | ~0.02 vCPU | ~2 GB (CLIs) | ≈ $6 |
| Typical (one or two people, 1-2 turns at a time a few hours a day) | ~1.2 GB avg, 3 GB peaks | ~0.2 vCPU avg | ~3 GB | ≈ $17 |
| Heavy (4 concurrent turns most of the working day, builds/tests, document previews) | ~3 GB avg, 6-8 GB peaks | ~1 vCPU avg | 4-5 GB | ≈ $50 |

Suggested service limits: 8 GB RAM and 4 vCPU for the default concurrency of 4. Model usage is billed by the provider. Minimum plan: **Hobby** (Trial's 0.5 GB volume cannot hold the CLIs and 1 GB RAM is too small for a turn). Hobby's 5 GB volume fits the default set; the full 30-base set needs Pro.

## Verification checklist

- [ ] Build: `FROM` by digest succeeds; the `bash -n`/`test -x` RUN step passes.
- [ ] Logs show `[railway] preflight: capabilities … present`, the mapped-id line (record it), the sizing line, then upstream's install lines, `backends available: claude codex hermes pi dsh opencode qwen gemini cline omp` and `ready on :3000`. Record first-start duration and `du -sh /data/agent-tools`.
- [ ] `GET /api/harness/v1/uhp` → 200 with `implementation.version` `0.38.2`; `GET /` → redirect to `/login`; `POST /api/harness/v1/responses` without auth → 401.
- [ ] Sign in with `HR_AUTH_PASSWORD`; a wrong password is refused.
- [ ] Add a provider key in the console; run one task on `codex` and one on `claude-code`.
- [ ] Isolation (via `railway ssh` while a task runs): the agent process runs as `hs20000`-style user; `/data/workspaces/{session}` is owned by that uid, mode 0700. In a task, `ls /data/workspaces` and reading `/data/*.db` fail with permission denied.
- [ ] Set `OPENAI_API_KEY`, redeploy: log line `providers: environment connections openai`, Codex models selectable, a Codex turn works without a console key.
- [ ] API: create a key; `"background": true` request returns an id; polling reaches `completed`; a `"stream": true` request streams events through Railway's edge without buffering.
- [ ] Redeploy: CLIs are not reinstalled, sessions, keys and login survive. Change the password under Profile; the console restarts and the new password works.

## Open questions

- Railway's capability set and uid mapping are inferred (podman defaults, our sshd/setpriv templates), not observed for ids ≥ 20000; the preflight log answers it on the first deploy. `setfsuid` through ctypes under Railway's runtime is likewise untested.
- First-start duration of the 10 default installs on Railway (estimated 3-8 minutes) and their real disk use.
- Whether Railway's edge passes SSE unbuffered for the console's live view and `stream: true`.
- The login cookie's `Secure` flag depends on Next seeing `https` behind Railway's proxy; harmless on an HTTPS-only domain, not verified.
- Upstream ships several releases a day (0.37.15 to 0.38.2 in two days). Re-check the changelog and `docs/self-hosting-guide.md` before each bump; back up the volume first (0.32.0 changed retention).
- Three default CLIs (Pi, Qwen Code, opencode) install whatever is newest at first start; a breaking release there would affect only new volumes.
