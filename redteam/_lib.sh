#!/usr/bin/env bash
# Shared helpers for the redteam/ wrapper scripts. Source it, don't execute it:
#   . "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
#
# Why this exists: promptfoo 0.121.17 declares engines "^20.20.0 || >=22.22.0" and REFUSES
# to start on anything else ("Install a supported Node.js version and try again"), which
# includes common defaults like Node 22.15. Every script needs the same resolution logic.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="$HERE/output"
PF="$ROOT/node_modules/.bin/promptfoo"
APP_URL="${SUPPORTBOT_URL:-http://localhost:8000}"

mkdir -p "$OUT"

# Load the repo-root .env (OPENAI_API_KEY, PROMPTFOO_API_KEY, OPENAI_MODEL, ...).
load_env() {
  [ -f "$ROOT/.env" ] && { set -a; . "$ROOT/.env"; set +a; }
  export PROMPTFOO_DISABLE_TELEMETRY=1
  return 0
}

# True if $1 (a `node --version` string) satisfies promptfoo's engines range.
_node_ok() {
  local v="${1#v}" major minor
  major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%.*}"
  [ -z "$major" ] && return 1
  case "$major" in
    20) [ "$minor" -ge 20 ] ;;
    21) return 1 ;;
    22) [ "$minor" -ge 22 ] ;;
    *)  [ "$major" -gt 22 ] ;;
  esac
}

# Prepend a promptfoo-compatible node to PATH, or exit with actionable instructions.
require_node() {
  if command -v node >/dev/null 2>&1 && _node_ok "$(node --version 2>/dev/null)"; then
    return 0
  fi
  local cand
  for cand in /opt/homebrew/opt/node@24/bin /opt/homebrew/opt/node@22/bin \
              /usr/local/opt/node@24/bin /usr/local/opt/node@22/bin \
              "$HOME"/.nvm/versions/node/*/bin; do
    [ -x "$cand/node" ] || continue
    if _node_ok "$("$cand/node" --version 2>/dev/null)"; then
      export PATH="$cand:$PATH"
      echo "note: using Node $("$cand/node" --version) from $cand (promptfoo needs ^20.20.0 || >=22.22.0)" >&2
      return 0
    fi
  done
  cat >&2 <<EOF
ERROR: no Node.js satisfying promptfoo's engines range ("^20.20.0 || >=22.22.0") was found.
       Active node: $(command -v node >/dev/null 2>&1 && node --version || echo "none")
       Install one, e.g.:  nvm install 24 && nvm use 24
                    or:    brew install node@24
       Then re-run this script (it auto-detects nvm and Homebrew installs).
EOF
  exit 1
}

# Fail fast unless SupportBot is reachable.
require_app() {
  curl -sf -m 5 "$APP_URL/health" >/dev/null 2>&1 && return 0
  cat >&2 <<EOF
ERROR: SupportBot not reachable at $APP_URL. Start it first:
  $ROOT/.venv/bin/uvicorn supportbot.app:app --host 127.0.0.1 --port 8000
(Override the URL with SUPPORTBOT_URL=http://host:port)
EOF
  exit 1
}

# Restart SupportBot with extra env vars, then wait until it is healthy and reset.
# Usage: app_restart [VAR=value ...]
# Always launches from $ROOT: `uvicorn supportbot.app:app` resolves the module against the
# CWD, so starting it from redteam/ fails with ModuleNotFoundError, and load_dotenv() would
# also miss the root .env.
app_restart() {
  pkill -f "uvicorn supportbot.app" 2>/dev/null || true
  local _ i
  for i in $(seq 1 15); do
    curl -sf -m 2 "$APP_URL/health" >/dev/null 2>&1 || break
    sleep 1
  done
  ( cd "$ROOT" && env "$@" "$ROOT/.venv/bin/uvicorn" supportbot.app:app \
      --host 127.0.0.1 --port 8000 --log-level warning >/tmp/supportbot-harness.log 2>&1 & )
  for i in $(seq 1 30); do
    if curl -sf -m 2 "$APP_URL/health" >/dev/null 2>&1; then
      reset_app
      return 0
    fi
    sleep 1
  done
  echo "ERROR: SupportBot did not come up (see /tmp/supportbot-harness.log)" >&2
  return 1
}

# Clear the target's sessions + shared CRM scratchpad so findings are order-independent.
reset_app() {
  curl -sf -m 5 -X POST "$APP_URL/reset" >/dev/null 2>&1 \
    || echo "warn: POST $APP_URL/reset failed — findings may depend on test order" >&2
  return 0
}

# Run promptfoo, tolerating its documented exit code 100 ("some assertions failed").
# For this POC a failing assertion is the EXPECTED result, so 100 must not abort the
# script under `set -e`. Any other non-zero code is a real error and propagates.
pf() {
  local rc=0
  "$PF" "$@" || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 100 ]; then
    echo "ERROR: promptfoo exited $rc" >&2
    return "$rc"
  fi
  return 0
}

# Resolve a replayable case set. `redteam run -o` writes an EVAL EXPORT (evalId/results/
# config/metadata), not a bare config: its providers live under `config`, so handing it back
# to `-c` fails with "You must specify at least 1 provider". This lifts the config out, once,
# into a sibling *-replay.yaml and echoes that path. Pass an already-replayable file and it is
# regenerated harmlessly.
#   CASES="$(resolve_cases "$OUT/redteam-cases.yaml")" || exit 1
resolve_cases() {
  local src="$1" out
  [ -f "$src" ] || { echo "ERROR: no case set at $src" >&2; return 1; }
  out="${src%.yaml}"; out="${out%.json}"; out="${out%-cases}-replay.yaml"
  node "$HERE/extract-cases.mjs" "$src" "$out" >/dev/null || return 1
  echo "$out"
}

# Standard preamble.
setup() { load_env; require_node; }
