#!/usr/bin/env node
/**
 * Per-case before/after comparison of two promptfoo JSON exports.
 *
 * Why this exists: a headline like "2/4 failing -> 4/4 passing" is not evidence that a fix
 * worked. If a case did NOT reproduce the vulnerability in the BEFORE run, its pass in the
 * AFTER run proves nothing — the attack simply didn't fire that time. This script separates:
 *
 *   CLOSED         exploited before, defended after   <- the only cases that evidence a fix
 *   STILL OPEN     exploited before and after
 *   REGRESSED      defended before, exploited after
 *   INCONCLUSIVE   not exploited before               <- excluded from the fix's numerator
 *
 * Usage: node compare-runs.mjs <before.json> <after.json>
 */
import { readFileSync } from 'node:fs';

const [beforePath, afterPath] = process.argv.slice(2);
if (!beforePath || !afterPath) {
  console.error('usage: node compare-runs.mjs <before.json> <after.json>');
  process.exit(2);
}

const load = (p) => {
  const j = JSON.parse(readFileSync(p, 'utf8'));
  return j?.results?.results ?? j?.results ?? [];
};

/** Stable identity for a test case across runs (the attack, not the response). */
const keyOf = (r) => {
  const tc = r.testCase ?? {};
  const md = { ...(tc.metadata ?? {}), ...(r.metadata ?? {}) };
  const vars = r.vars ?? tc.vars ?? {};
  const probe = String(vars.prompt ?? vars.message ?? vars.query ?? JSON.stringify(vars));
  return [md.pluginId ?? '-', md.strategyId ?? 'basic', probe].join(' :: ');
};

/** promptfoo marks an exploited red-team case as a failing assertion. */
const exploited = (r) => r.gradingResult?.pass === false || r.success === false;

const index = (rows) => {
  const m = new Map();
  for (const r of rows) {
    const k = keyOf(r);
    // --repeat produces several results per case: exploited even once == reproducible.
    const prev = m.get(k);
    m.set(k, prev ? { ...prev, n: prev.n + 1, hit: prev.hit || exploited(r) } : { n: 1, hit: exploited(r), r });
  }
  return m;
};

const before = index(load(beforePath));
const after = index(load(afterPath));

const buckets = { CLOSED: [], 'STILL OPEN': [], REGRESSED: [], INCONCLUSIVE: [], MISSING: [] };
for (const [k, b] of before) {
  const a = after.get(k);
  if (!a) buckets.MISSING.push(k);
  else if (b.hit && !a.hit) buckets.CLOSED.push(k);
  else if (b.hit && a.hit) buckets['STILL OPEN'].push(k);
  else if (!b.hit && a.hit) buckets.REGRESSED.push(k);
  else buckets.INCONCLUSIVE.push(k);
}
const newCases = [...after.keys()].filter((k) => !before.has(k));

const label = (s) => s.replace(/\s+/g, ' ').slice(0, 100);
console.log(`before: ${beforePath}  (${before.size} cases)`);
console.log(`after : ${afterPath}  (${after.size} cases)\n`);
for (const [name, list] of Object.entries(buckets)) {
  if (!list.length) continue;
  console.log(`${name} (${list.length})`);
  for (const k of list.slice(0, 12)) console.log(`   - ${label(k)}`);
  if (list.length > 12) console.log(`   ... and ${list.length - 12} more`);
  console.log('');
}
if (newCases.length) {
  console.log(`NOT IN BASELINE (${newCases.length}) — the runs are not comparable case-for-case;`);
  console.log(`   use ./rescan.sh (replays saved cases) rather than a fresh ./run.sh.\n`);
}

const reproducible = buckets.CLOSED.length + buckets['STILL OPEN'].length;
console.log('--- verdict ---');
if (reproducible === 0) {
  console.log('No case reproduced the vulnerability in the BEFORE run: this pair cannot');
  console.log('evidence a fix. Raise --repeat, or pick cases that reliably fire.');
} else {
  console.log(`Fix closed ${buckets.CLOSED.length}/${reproducible} of the cases that actually`);
  console.log(`reproduced the vulnerability (${buckets.INCONCLUSIVE.length} case(s) never fired and are excluded).`);
}
process.exit(buckets.REGRESSED.length > 0 ? 1 : 0);
