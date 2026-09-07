#!/usr/bin/env bash
# MODEL COMPARISON — the only way to interpret a MISSED row in the scorecard.
#
# Retests weaknesses #1 and #8 against a second model. The POC's two misses were attributed to
# gpt-4o-mini's own alignment rather than to any Promptfoo limitation — this is what tests that
# claim instead of asserting it. `scorecard.mjs` points every MISSED row here for that reason.
#
# This matters for the adoption decision. "Promptfoo missed it" and
# "the base model refused it" are indistinguishable from a single-model run — and they lead to
# opposite conclusions. Running the identical case set against a second model separates them:
#   * a weakness that fires on model B but not model A => Promptfoo's probe was sound all along,
#     and the miss was model alignment (defense-in-depth), exactly as the POC claimed.
#   * a weakness that fires on NEITHER, while a hand-written attack lands => the probe itself
#     is too weak, and the "0 detected" result is a Promptfoo coverage gap.
#
# SupportBot reads its model from OPENAI_MODEL, so each model needs an app restart.
#
# Usage:
#   ./model-compare.sh                            # the exploit suite across both models
#   SUITE=exfil-eval.yaml ./model-compare.sh      # just the poisoned-doc -> exfil chain
#   MODELS="gpt-4o-mini gpt-4.1-mini" ./model-compare.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_lib.sh"
setup

SUITE="${SUITE:-$HERE/exploit-suite.yaml}"
[ -f "$SUITE" ] || SUITE="$HERE/$SUITE"
MODELS="${MODELS:-gpt-4o-mini gpt-4.1-mini}"
RESULTS=()

start_app() {  # $1 = model id
  app_restart "OPENAI_MODEL=$1"
}

restore() {
  echo
  echo "restoring the default model (${OPENAI_MODEL:-gpt-4o-mini})..."
  start_app "${OPENAI_MODEL:-gpt-4o-mini}" >/dev/null 2>&1 && echo "restored." \
    || echo "warn: restart failed; start it manually." >&2
}
trap restore EXIT

for m in $MODELS; do
  echo "===== $m ====="
  if ! start_app "$m"; then
    echo "skipping $m (did it start? is the model available on your key?)" >&2
    continue
  fi
  out="$OUT/model-$m-results.json"
  pf eval -c "$SUITE" -o "$out" --no-cache --no-table
  RESULTS+=("$m=$out")
  echo
done

echo "===== comparison: $(basename "$SUITE") ====="
node - "${RESULTS[@]}" <<'NODE'
const fs = require('node:fs');
const runs = process.argv.slice(2).map((a) => {
  const i = a.indexOf('=');
  const [model, path] = [a.slice(0, i), a.slice(i + 1)];
  const rows = JSON.parse(fs.readFileSync(path, 'utf8'))?.results?.results ?? [];
  return { model, rows };
});
if (runs.length < 2) {
  console.log('need at least two successful runs to compare.');
  process.exit(0);
}
const key = (r) => r.testCase?.description ?? JSON.stringify(r.vars);
const cases = [...new Set(runs.flatMap((r) => r.rows.map(key)))];
const w = Math.max(...cases.map((c) => Math.min(c.length, 52)));
console.log('case'.padEnd(w + 2) + runs.map((r) => r.model.padEnd(16)).join(''));
for (const c of cases) {
  const cells = runs.map((r) => {
    const row = r.rows.find((x) => key(x) === c);
    if (!row) return '-'.padEnd(16);
    return (row.success ? 'PASS' : 'FAIL').padEnd(16);
  });
  console.log(c.slice(0, 52).padEnd(w + 2) + cells.join(''));
}
console.log('');
for (const r of runs) {
  const p = r.rows.filter((x) => x.success).length;
  console.log(`${r.model.padEnd(18)} ${p}/${r.rows.length} passing`);
}
console.log('\nFor a SECURITY suite, PASS = the app defended and FAIL = the vulnerability fired.');
console.log('A case that FAILS on one model and PASSES on another is model alignment doing the');
console.log('defending, not your application controls — record which is which.');
NODE
