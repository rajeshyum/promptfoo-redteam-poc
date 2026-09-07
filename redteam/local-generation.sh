#!/usr/bin/env bash
# DATA-RESIDENCY comparison (design §5, §13.3, and the §10 "Data residency" rubric row).
#
# Runs the same config twice — remote attack generation (default, data leaves the machine) and
# local generation (PROMPTFOO_DISABLE_REDTEAM_REMOTE_GENERATION=true, air-gapped generation) —
# and saves both artifacts so the comparison is evidenced rather than narrated.
#
# The POC recorded the local-mode outcome in prose ("app-layer plugins refuse to generate").
# This produces the receipts: two case files, two result files, and a plugin-by-plugin diff of
# WHICH plugins actually generated in each mode.
#
# Note what is and is not air-gapped in local mode: generation stays local, but GRADING still
# calls a model (defaults to OpenAI). For a genuinely offline run you must also point
# `redteam.provider` at a local model. datasets.yaml is the one pass whose *generation* is
# inherently local — published corpora, no synthesis.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
setup
require_app

CONFIG="${1:-promptfooconfig.yaml}"
cd "$HERE"

echo "########## MODE 1: remote generation (default) ##########"
reset_app
pf redteam run -c "$CONFIG" -o "$OUT/gen-remote-cases.yaml" --no-cache --force 2>&1 \
  | tee "$OUT/gen-remote.log" | tail -5
ID="$("$PF" list evals -n 1 --ids-only 2>/dev/null | grep -oE 'eval-[A-Za-z0-9]+-[0-9T:-]+' | head -1)"
[ -n "$ID" ] && pf export eval "$ID" -o "$OUT/gen-remote-results.json" >/dev/null

echo
echo "########## MODE 2: local generation (no data leaves the machine) ##########"
reset_app
PROMPTFOO_DISABLE_REDTEAM_REMOTE_GENERATION=true \
  pf redteam run -c "$CONFIG" -o "$OUT/gen-local-cases.yaml" --no-cache --force 2>&1 \
  | tee "$OUT/gen-local.log" | tail -5
ID="$("$PF" list evals -n 1 --ids-only 2>/dev/null | grep -oE 'eval-[A-Za-z0-9]+-[0-9T:-]+' | head -1)"
[ -n "$ID" ] && pf export eval "$ID" -o "$OUT/gen-local-results.json" >/dev/null

echo
echo "########## which plugins generated in each mode ##########"
count_plugins() {  # $1 = eval export from `redteam run -o`
  [ -f "$1" ] || { echo "  (no cases file — generation produced nothing)"; return; }
  # Count from config.tests ONLY. A plain grep over the export double-counts: pluginId appears
  # under `results` (once per graded response) as well as under `config.tests`, which inflated
  # these totals roughly 4x.
  node -e '
    const fs=require("fs"), yaml=require("js-yaml");
    const d=yaml.load(fs.readFileSync(process.argv[1],"utf8"));
    const tests=(d.config??d).tests??[];
    const m={};
    for (const t of tests) { const p=t.metadata?.pluginId??"(none)"; m[p]=(m[p]||0)+1; }
    const rows=Object.entries(m).sort((a,b)=>b[1]-a[1]);
    if (!rows.length) { console.log("  (export contains no test cases)"); }
    for (const [p,n] of rows) console.log("  "+String(n).padStart(4)+" "+p);
    console.log("  "+String(tests.length).padStart(4)+" TOTAL");
  ' "$1"
}
echo "-- remote --"; count_plugins "$OUT/gen-remote-cases.yaml"
echo "-- local  --"; count_plugins "$OUT/gen-local-cases.yaml"

echo
echo "########## plugins that REFUSED to generate locally ##########"
# The adoption-critical number: every plugin here is coverage you lose by staying air-gapped.
grep -aiE 'requires remote generation|remote generation|skipping|failed to generate' \
  "$OUT/gen-local.log" | sed 's/^/  /' | sort -u | head -30 || echo "  (none logged)"

echo
echo "artifacts: $OUT/gen-{remote,local}-{cases.yaml,results.json,.log}"
echo "compare detections: ./compare-runs.sh $OUT/gen-remote-results.json $OUT/gen-local-results.json"
