#!/usr/bin/env bash
# Generic runner for plain (non-generated) eval configs — deterministic assertions, no
# attack generation. These are the reproducible counterpart to the generated scans.
#
#   ./eval.sh exploit-suite.yaml               # all 9 planted weaknesses, hand-written probes
#   ./eval.sh exploit-suite.yaml --repeat 3    # for the probabilistic cases (#3-poisoned, #9)
#   ./eval.sh exfil-eval.yaml                  # poisoned-doc / markdown-exfil chain
#
# Exit code: 0 even when assertions fail. For these configs a FAILING assertion means the
# vulnerability is present, which is the expected result against the vulnerable default — so
# promptfoo's exit 100 must not be treated as a script error. Use ./ci-gate.sh when you want
# failures to be fatal.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
setup
require_app
reset_app

CONFIG="${1:?usage: ./eval.sh <config.yaml> [promptfoo args...]}"; shift
[ -f "$CONFIG" ] || CONFIG="$HERE/$CONFIG"
[ -f "$CONFIG" ] || { echo "ERROR: no such config: $CONFIG" >&2; exit 1; }
NAME="$(basename "$CONFIG" .yaml)"

cd "$HERE"
pf eval -c "$CONFIG" -o "$OUT/$NAME-results.json" --no-cache "$@"
echo
echo "results: $OUT/$NAME-results.json"
node "$HERE/cost-report.mjs" "$OUT/$NAME-results.json" || true
