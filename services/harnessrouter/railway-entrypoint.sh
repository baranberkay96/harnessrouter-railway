#!/usr/bin/env bash
# Railway start wrapper for HarnessRouter Community Edition (community template, not upstream code).
#
# Runs as root under tini, does four Railway-specific things, then execs upstream's unchanged
# /app/entrypoint.sh, which installs the agent CLIs into /data, drops privileges and starts the
# console (:3000), the gateway (127.0.0.1:8080) and the runner (127.0.0.1:8081).
#
#   1. Preflight: logs whether this container has what upstream's per-session isolation needs
#      (root, the default capabilities for switching users, a uid range for session users).
#   2. Sizes turn concurrency and OMP_NUM_THREADS from the cgroup CPU quota. Upstream defaults
#      to os.cpu_count(), which on Railway is the host's core count, not the service's share.
#   3. Turns plain provider API keys (ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY,
#      OPENROUTER_API_KEY) into upstream's documented environment connections and policies
#      (HR_SECRET_GLOBAL_HARNESS_CONN_* / HR_SECRET_GLOBAL_HARNESS_POLICY_*), only when set.
#   4. Prints where the console login comes from. Never prints a secret.
set -euo pipefail

PY=/usr/local/bin/python3
UPSTREAM_ENTRYPOINT=/app/entrypoint.sh
# Upstream 0.38.2's default HR_BACKENDS (docker/entrypoint.sh), used only to name policies when
# HR_BACKENDS is unset. The template sets a smaller list; see TEMPLATE.md.
UPSTREAM_BACKENDS="claude,codex,hermes,pi,dsh,opencode,kilo,qwen,gemini,cline,omp,goose,kimi,minimax,grok,aider,openhands,agentzero,systemone,cheetahclaws,mimo,jcode,opensquilla,nanobot,zeroclaw,qoder,vibe,docker-agent,fast-agent,dcode"
# Upstream's session-uid default (runner/server.py) and the fallback used when it is not mapped.
DEFAULT_SESSION_UID_BASE=20000
FALLBACK_SESSION_UID_BASE=10002   # first id above the product user 'agent' (10001)
SESSION_UID_HEADROOM=1024         # session directories the mapped range should leave room for
ENV_GID_TOP=100000                # environments use uid=gid 60000..99999 (runner/environments.py)
AUTO_CONCURRENCY_MIN=2
AUTO_CONCURRENCY_MAX=4
OMP_THREADS_MAX=8

log() { printf '[railway] %s\n' "$*"; }

is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

clamp() {  # <value> <min> <max>
  local v="$1"
  if [ "$v" -lt "$2" ]; then v="$2"; fi
  if [ "$v" -gt "$3" ]; then v="$3"; fi
  printf '%s\n' "$v"
}

# Highest id + 1 that this user namespace maps (uid_map/gid_map: inside outside count).
mapped_top() {
  if [ -r "$1" ]; then
    awk 'BEGIN { m = 0 } { t = $1 + $3; if (t > m) m = t } END { printf "%.0f\n", m }' "$1"
  else
    printf '0\n'
  fi
}

preflight() {
  if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: started as uid $(id -u). HarnessRouter must start as root; it drops privileges itself."
    return 0   # upstream's entrypoint refuses with its own message
  fi

  local capeff item bit name missing=""
  capeff="$(awk '/^CapEff:/ { print $2 }' /proc/self/status 2>/dev/null || true)"
  if [ -n "$capeff" ]; then
    for item in 0:CAP_CHOWN 1:CAP_DAC_OVERRIDE 3:CAP_FOWNER 6:CAP_SETGID 7:CAP_SETUID; do
      bit="${item%%:*}"; name="${item#*:}"
      if (( ((16#$capeff) >> bit) & 1 )); then :; else missing="$missing $name"; fi
    done
    if [ -z "$missing" ]; then
      log "preflight: capabilities for per-session users present (CapEff $capeff); no extra privileges used"
    else
      log "ERROR: missing capabilities:$missing (CapEff $capeff). Per-session users cannot be created; the gateway and agent turns will fail."
    fi
  fi

  local top_u top_g top base
  top_u="$(mapped_top /proc/self/uid_map)"
  top_g="$(mapped_top /proc/self/gid_map)"
  if ! is_uint "$top_u" || ! is_uint "$top_g" || [ "$top_u" -eq 0 ] || [ "$top_g" -eq 0 ]; then
    log "preflight: uid/gid map unreadable; keeping upstream's session uid range"
    return 0
  fi
  top="$top_u"; if [ "$top_g" -lt "$top" ]; then top="$top_g"; fi
  base="${HR_SESSION_UID_BASE:-$DEFAULT_SESSION_UID_BASE}"
  if ! is_uint "$base"; then
    log "WARNING: HR_SESSION_UID_BASE='$base' is not a number; the runner will refuse it"
  elif [ "$top" -ge $((base + SESSION_UID_HEADROOM)) ]; then
    log "preflight: ids below $top are mapped; session users start at $base"
  elif [ -z "${HR_SESSION_UID_BASE:-}" ] && [ "$top" -ge $((FALLBACK_SESSION_UID_BASE + SESSION_UID_HEADROOM)) ]; then
    export HR_SESSION_UID_BASE="$FALLBACK_SESSION_UID_BASE"
    log "preflight: only ids below $top are mapped, so session users start at $FALLBACK_SESSION_UID_BASE instead of $DEFAULT_SESSION_UID_BASE"
  else
    log "WARNING: only ids below $top are mapped; session users from $base cannot be created and agent turns will fail"
  fi
  if is_uint "$top" && [ "$top" -lt "$ENV_GID_TOP" ]; then
    log "WARNING: ids 60000-99999 are not all mapped; building an Environment (Build > Environments) may fail. Tasks without an environment are unaffected."
  fi
}

# CPUs this service may use: cgroup v2 cpu.max, cgroup v1 CFS quota, else the visible CPUs.
cpu_limit() {
  local q="" p=""
  if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r q p < /sys/fs/cgroup/cpu.max || true
    if is_uint "$q" && is_uint "$p" && [ "$p" -gt 0 ]; then
      printf '%s\n' $(( (q + p - 1) / p )); return 0
    fi
  elif [ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ] && [ -r /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
    q="$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)"; p="$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)"
    if is_uint "$q" && is_uint "$p" && [ "$p" -gt 0 ]; then
      printf '%s\n' $(( (q + p - 1) / p )); return 0
    fi
  fi
  getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2\n'
}

size_from_quota() {
  local cpus
  cpus="$(cpu_limit)"
  if ! is_uint "$cpus" || [ "$cpus" -lt 1 ]; then cpus=1; fi

  if [ -z "${HARNESS_GLOBAL_CONCURRENCY:-}" ]; then
    export HARNESS_GLOBAL_CONCURRENCY
    HARNESS_GLOBAL_CONCURRENCY="$(clamp "$cpus" "$AUTO_CONCURRENCY_MIN" "$AUTO_CONCURRENCY_MAX")"
    log "sizing: CPU limit $cpus -> at most $HARNESS_GLOBAL_CONCURRENCY agent turns at once (set HARNESS_GLOBAL_CONCURRENCY to change)"
  elif is_uint "$HARNESS_GLOBAL_CONCURRENCY" && [ "$HARNESS_GLOBAL_CONCURRENCY" -gt 0 ]; then
    log "sizing: HARNESS_GLOBAL_CONCURRENCY=$HARNESS_GLOBAL_CONCURRENCY (CPU limit $cpus)"
  else
    log "WARNING: HARNESS_GLOBAL_CONCURRENCY='$HARNESS_GLOBAL_CONCURRENCY' is not a positive number; upstream falls back to the host core count"
  fi

  # nproc and OpenMP/BLAS read this, so `make -j$(nproc)` in an agent's shell follows the quota.
  if [ -z "${OMP_NUM_THREADS:-}" ]; then
    export OMP_NUM_THREADS
    OMP_NUM_THREADS="$(clamp "$cpus" 1 "$OMP_THREADS_MAX")"
  fi
}

CONNECTIONS=()

add_connection() {  # <plain variable> <connection name = upstream provider id>
  local plain="$1" name="$2" key conn_var json
  key="${!plain:-}"
  unset "$plain"
  if [ -z "${key//[[:space:]]/}" ]; then return 0; fi
  conn_var="HR_SECRET_GLOBAL_HARNESS_CONN_$(upper "$name")"
  if [ -n "${!conn_var:-}" ]; then
    log "providers: $conn_var is set explicitly, so $plain was not used"
    return 0
  fi
  json="$(HR_WRAP_KEY="$key" HR_WRAP_NAME="$name" "$PY" -I -c '
import json, os
print(json.dumps({"name": os.environ["HR_WRAP_NAME"], "provider": os.environ["HR_WRAP_NAME"],
                  "api_key": os.environ["HR_WRAP_KEY"].strip()}))')"
  export "$conn_var=$json"
  CONNECTIONS+=("$name")
}

provider_connections() {
  # Direct vendors first, the aggregator last. The gateway skips a connection that cannot drive
  # a base or serve the requested model, and keys added in the console are tried before these.
  add_connection ANTHROPIC_API_KEY anthropic
  add_connection OPENAI_API_KEY openai
  add_connection GEMINI_API_KEY google
  add_connection OPENROUTER_API_KEY openrouter
  if [ "${#CONNECTIONS[@]}" -eq 0 ]; then
    log "providers: no API key variables set; add a provider in the console (account menu > Bring your own key)"
    return 0
  fi

  local chain backend pvar set_count=0 backends=()
  chain="$(printf '%s\n' "${CONNECTIONS[@]}" | "$PY" -I -c '
import json, sys
print(json.dumps({"chain": sys.stdin.read().split()}))')"
  IFS=', ' read -r -a backends <<< "${HR_BACKENDS:-$UPSTREAM_BACKENDS}"
  for backend in "${backends[@]}"; do
    case "$backend" in ''|*[!a-z0-9-]*) continue ;; esac
    pvar="HR_SECRET_GLOBAL_HARNESS_POLICY_$(upper "${backend//-/_}")"
    if [ -n "${!pvar:-}" ]; then continue; fi
    export "$pvar=$chain"
    set_count=$((set_count + 1))
  done
  log "providers: environment connections ${CONNECTIONS[*]} (fallback after console keys) for $set_count bases"
}

login_hint() {
  if [ "${HR_AUTH_DISABLED:-}" = "1" ]; then
    log "WARNING: HR_AUTH_DISABLED=1 removes the sign-in gate on a public URL. Anyone can run agents with your keys."
    return 0
  fi
  local domain="${RAILWAY_PUBLIC_DOMAIN:-the service public domain}"
  if [ -z "${HR_AUTH_PASSWORD:-}" ]; then
    unset HR_AUTH_PASSWORD
    log "console: https://$domain user '${HR_AUTH_USER:-harnessrouter}'; HR_AUTH_PASSWORD is empty, so upstream generates a password in /data/selfhost-initial-password (read it with railway ssh)"
    return 0
  elif [ "${#HR_AUTH_PASSWORD}" -lt 16 ]; then
    log "WARNING: HR_AUTH_PASSWORD is shorter than 16 characters; this console is on a public URL"
  fi
  log "console: https://$domain user '${HR_AUTH_USER:-harnessrouter}', password = the HR_AUTH_PASSWORD variable (a password saved under Profile replaces it)"
}

main() {
  log "HarnessRouter ${HR_VERSION:-unknown} on Railway: preflight before upstream's entrypoint"
  preflight
  size_from_quota
  provider_connections
  login_hint
  exec "$UPSTREAM_ENTRYPOINT" "$@"
}

main "$@"
