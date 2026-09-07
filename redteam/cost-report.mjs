#!/usr/bin/env node
/**
 * Token + cost + wall-clock accounting for a promptfoo run (design §6 Group B item 9,
 * §8 "Cost — order of magnitude", and the §10 "Cost at scale" rubric row).
 *
 * The design doc estimated cost as `~3 LLM calls per attack`; this measures it instead.
 * Note the scope of what promptfoo reports: token usage covers the calls promptfoo makes
 * (grader + any local generation). The TARGET's own token spend (SupportBot's OpenAI
 * chat + tool loop) is NOT visible here, and remote attack generation is billed by
 * Promptfoo Cloud, not by tokens on your key — both are called out in the output.
 *
 * Usage: node cost-report.mjs <results.json> [more.json ...]
 */
import { readFileSync } from 'node:fs';

const paths = process.argv.slice(2);
if (!paths.length) {
  console.error('usage: node cost-report.mjs <results.json> [...]');
  process.exit(2);
}

const num = (n) => (typeof n === 'number' && Number.isFinite(n) ? n : 0);
const fmt = (n) => n.toLocaleString('en-US');

for (const p of paths) {
  let j;
  try {
    j = JSON.parse(readFileSync(p, 'utf8'));
  } catch (err) {
    console.error(`skip ${p}: ${err.message}`);
    continue;
  }
  const res = j.results ?? {};
  const rows = res.results ?? [];
  const stats = res.stats ?? {};
  const tu = stats.tokenUsage ?? {};

  // Per-result cost is reported by promptfoo for providers whose pricing it knows.
  let cost = 0;
  let latencySum = 0;
  let latencyMax = 0;
  let exploited = 0;
  let errored = 0;
  for (const r of rows) {
    cost += num(r.cost);
    const ms = num(r.latencyMs);
    latencySum += ms;
    latencyMax = Math.max(latencyMax, ms);
    if (r.error && r.gradingResult?.pass !== false) errored++;
    else if (r.gradingResult?.pass === false || r.success === false) exploited++;
  }

  const started = res.timestamp ? new Date(res.timestamp) : null;
  const n = rows.length || 1;

  console.log(`\n=== ${p} ===`);
  console.log(`description   ${j.config?.description ?? '(none)'}`);
  if (started) console.log(`started       ${started.toISOString()}`);
  console.log(`test cases    ${fmt(rows.length)}   exploited ${exploited}   errors ${errored}`);
  console.log(`tokens        prompt ${fmt(num(tu.prompt))}  completion ${fmt(num(tu.completion))}  cached ${fmt(num(tu.cached))}  total ${fmt(num(tu.total))}`);
  console.log(`grader calls  ${fmt(num(tu.numRequests))}   assertion tokens ${fmt(num(tu.assertions?.total))}`);
  console.log(`reported cost $${cost.toFixed(4)}   ($${(cost / n).toFixed(4)}/case)`);
  console.log(`target latency mean ${(latencySum / n / 1000).toFixed(1)}s   max ${(latencyMax / 1000).toFixed(1)}s   summed ${(latencySum / 60000).toFixed(1)} min`);
  console.log(`per-case tokens ${(num(tu.total) / n).toFixed(0)}`);
  console.log('not counted:  the target app\'s own OpenAI spend, and remote attack generation');
  console.log('              (billed by Promptfoo Cloud, not tokens on your key).');
}
