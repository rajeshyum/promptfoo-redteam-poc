#!/usr/bin/env bash
# Apples-to-apples RESCAN: replay the SAVED generated test cases with no regeneration.
#
# This is the design doc's Phase 3 requirement (§7 / §8 "Rescan non-determinism"): a fresh
# `redteam run` generates DIFFERENT attacks, so a finding that clears could be attack
# variance rather than your fix. `promptfoo redteam eval` evaluates an existing test set.
#
# Usage:
#   ./run.sh                       # once, to generate output/redteam-cases.yaml
#   <apply a fix to SupportBot, restart it>
#   ./rescan.sh                    # same attacks, new results
#   ./rescan.sh --repeat 3         # repeat each case to separate a fix from model variance
#   ./rescan.sh depth-cases.yaml   # replay a different saved case set
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
setup
require_app
reset_app

CASES="$OUT/redteam-cases.yaml"
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then   # first arg is a path, not a flag
  CASES="$1"; [ -f "$CASES" ] || CASES="$OUT/$1"
  shift
fi
[ -f "$CASES" ] || { echo "ERROR: $CASES not found — run ./run.sh first to generate the case set." >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
cd "$HERE"
REPLAY="$(resolve_cases "$CASES")" || exit 1
pf redteam eval -c "$REPLAY" -o "$OUT/rescan-$STAMP.json" --no-cache "$@"
echo "rescan results: $OUT/rescan-$STAMP.json"
echo "compare with the baseline:  ./compare-runs.sh $OUT/redteam-results.json $OUT/rescan-$STAMP.json"
node "$HERE/cost-report.mjs" "$OUT/rescan-$STAMP.json" || true
