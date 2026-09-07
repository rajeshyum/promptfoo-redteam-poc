#!/usr/bin/env bash
# What every scenario in this repo covers, what it costs, and how to run it.
#   ./scenarios.sh            # the table
#   ./scenarios.sh --check    # environment readiness (node, keys, auth, app, configs)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

if [ "${1:-}" = "--check" ]; then
  load_env
  echo "=== environment readiness ==="
  if command -v node >/dev/null 2>&1 && _node_ok "$(node --version)"; then
    echo "  [ok]   node $(node --version) satisfies promptfoo's ^20.20.0 || >=22.22.0"
  elif require_node 2>/dev/null; then
    echo "  [ok]   node $(node --version) found by auto-detection (default node is too old)"
  else
    echo "  [FAIL] no compatible node — see the error above"
  fi
  [ -n "${OPENAI_API_KEY:-}" ] && echo "  [ok]   OPENAI_API_KEY set" || echo "  [FAIL] OPENAI_API_KEY missing (.env)"
  [ -n "${PROMPTFOO_API_KEY:-}" ] && echo "  [ok]   PROMPTFOO_API_KEY set" || echo "  [warn] PROMPTFOO_API_KEY missing — remote generation will hit the email gate"
  if "$PF" auth whoami >/dev/null 2>&1; then
    # Exclude the "promptfoo@latest — please upgrade" banner, which also matches user@host.
    who="$("$PF" auth whoami 2>/dev/null | grep -aoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
           | grep -av '^promptfoo@' | head -1)"
    echo "  [ok]   promptfoo auth: ${who:-logged in}"
  else
    echo "  [warn] not logged in — run: ./node_modules/.bin/promptfoo auth login --api-key \"\$PROMPTFOO_API_KEY\""
  fi
  curl -sf -m 3 "$APP_URL/health" >/dev/null 2>&1 \
    && echo "  [ok]   SupportBot up at $APP_URL ($(curl -s -m 3 "$APP_URL/health"))" \
    || echo "  [warn] SupportBot not running — start it before any scan"
  echo "  configs:"
  for c in "$HERE"/*.yaml; do
    [ -f "$c" ] || continue
    if "$PF" validate -c "$c" 2>&1 | grep -qa 'is valid'; then
      printf '    [ok]   %s\n' "${c#$ROOT/}"
    else
      printf '    [FAIL] %s\n' "${c#$ROOT/}"
    fi
  done
  exit 0
fi

cat <<'EOF'
SCENARIO COVERAGE — each row names the design-doc criterion it satisfies.
Runtimes assume concurrency 4. A single /chat measures 1.2-3.8 s; the much larger per-CASE
latency under iterative strategies is the SUM of every retry that strategy makes, not one request.

RED-TEAM PASSES                                                    design ref     runtime
  ./run.sh                    default scan, 1 plugin per weakness  §4, §13.2      ~15 min
  ./scan.sh depth.yaml        >=3 strategies layered on            §4, §3         ~20-30 min
  ./crescendo.sh              multi-turn on the 2 misses (#1,#8)   §3, §8 H3      ~1-2 min
  ./scan.sh policy-intent.yaml  Custom & Configurable category     §3, §6 C13     ~5-8 min
  ./scan.sh datasets.yaml     Dataset Collections category         §3             ~10-15 min
                              (also: the one air-gapped pass)      §5
  ./scan.sh indirect-injection.yaml  native RAG poisoning /        §3, results
                              indirect injection via a request var  next-pass 3   ~8-12 min
  ./scan.sh owasp-framework.yaml  OWASP/NIST/MITRE mapping artifact §4, §6 B11    ~20-30 min

DETERMINISTIC EVALS (no attack generation — reproducible)
  ./eval.sh exploit-suite.yaml --repeat 3  hand-written attacks on §4.1 false-    ~40 s
                                         the planted weaknesses    negative ref
                                         28/39 fire; proves 6/9 weaknesses open.
                                         NOT a Promptfoo capability number — the
                                         probes were written with the answer key.
  ./eval.sh exfil-eval.yaml --repeat 3   poisoned-doc -> markdown  §2 #3/#9       ~2-4 min
                                         exfil chain

REPLAY & REGRESSION (the answer to generation non-determinism)
  ./rescan.sh                 replay SAVED cases (no regeneration) §7 Phase 3     = the pass
  ./compare-runs.sh A B       per-case diff of two runs: CLOSED /  §8 rescan
                              STILL OPEN / REGRESSED / INCONCLUSIVE    non-determinism
                              Only meaningful on a REPLAYED pair —
                              two fresh scans share no cases.

MEASUREMENT & META
  ./discover.sh               Target Discovery Agent vs the        §6 A1          ~2-4 min
                              hand-written purpose (0/40 -> 12/40)
  ./local-generation.sh       remote vs local generation, with     §5, §13.3      2x a scan
                              a plugin-by-plugin diff
  ./cost-report.sh <results>  tokens / cost / latency per case     §6 B9, §8      instant
  ./code-scan.sh              STATIC scan of the source (uploads   new            ~2-5 min
                              code to Promptfoo Cloud)
  ./model-compare.sh          same cases on 2 models: separates    results
                              "Promptfoo missed it" from "the       next-pass 2   2x a suite
                              model refused it" — the only way to
                              read a MISSED row in the scorecard

CI
  ./ci-gate.sh                replay committed cases, threshold    §6 B10, §9     = the pass
                              gate, junit.xml artifact
  ../.github/workflows/redteam-gate.yml   the same gate in Actions

REPORTING
  ./report.sh                 local vulnerability dashboard (the demo artifact; no upload)
  ./view.sh                   general local results viewer

  ./scenarios.sh --check      verify node / keys / auth / app / every config parses

⚠️  Every scan drives a deliberately-vulnerable app and generates genuinely adversarial
    content. Local target only. Never point these at another system.
EOF
