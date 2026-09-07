#!/usr/bin/env bash
# Generic red-team scan runner: generate attacks from any config, evaluate, export results.
#
#   ./scan.sh                          # promptfooconfig.yaml (the default fast scan)
#   ./scan.sh depth.yaml               # strategy-depth pass
#   ./scan.sh owasp-framework.yaml     # framework-mapping pass
#   ./scan.sh datasets.yaml -j 8       # extra args pass through to promptfoo
#
# Produces, per config <name>.yaml:
#   output/<name>-cases.yaml     the generated TEST CASES (replay these with ./rescan.sh)
#   output/<name>-results.json   the EVAL RESULTS (machine-readable; used by CI + cost report)
#
# CAREFUL — `redteam run -o` does NOT write a bare case list, despite the flag name. It writes
# a full EVAL EXPORT (evalId / results / config / metadata). The replayable part is nested under
# `config`, so feeding that file straight back to `-c` fails with the misleading error
# "You must specify at least 1 provider". extract-cases.mjs lifts it out; see _lib.sh
# resolve_cases(). Separately, the graded results only land in the local DB, so they must be
# exported explicitly or the run leaves no reviewable artifact behind.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
setup
require_app
reset_app          # order-independent findings: clear sessions + shared CRM scratchpad

CONFIG="${1:-promptfooconfig.yaml}"; [ $# -gt 0 ] && shift
[ -f "$HERE/$CONFIG" ] || { echo "ERROR: no such config: $HERE/$CONFIG" >&2; exit 1; }
NAME="$(basename "$CONFIG" .yaml)"
[ "$NAME" = "promptfooconfig" ] && NAME="redteam"

cd "$HERE"
echo "=== $CONFIG ==="
pf redteam run -c "$CONFIG" -o "$OUT/$NAME-cases.yaml" --no-cache --force "$@"

EVAL_ID="$("$PF" list evals -n 1 --ids-only 2>/dev/null | grep -oE 'eval-[A-Za-z0-9]+-[0-9T:-]+' | head -1)"
if [ -n "$EVAL_ID" ]; then
  pf export eval "$EVAL_ID" -o "$OUT/$NAME-results.json" >/dev/null
  echo
  node "$HERE/extract-cases.mjs" "$OUT/$NAME-cases.yaml" "$OUT/$NAME-replay.yaml" >/dev/null \
    && echo "replay:  $OUT/$NAME-replay.yaml   (./rescan.sh + ./ci-gate.sh consume this)"
  echo "cases:   $OUT/$NAME-cases.yaml   (raw eval export from -o)"
  echo "results: $OUT/$NAME-results.json   (eval $EVAL_ID)"
  node "$HERE/cost-report.mjs" "$OUT/$NAME-results.json" || true
else
  echo "warn: could not determine the eval id; results remain in the local DB only" >&2
fi
