#!/usr/bin/env node
/**
 * Turn a promptfoo EVAL EXPORT into a standalone, replayable config.
 *
 * WHY THIS EXISTS
 * ---------------------------------------------------------------------------------------
 * `promptfoo redteam run -o <file>` does NOT write a bare list of test cases, despite what
 * the flag name suggests. It writes a full eval export:
 *
 *     evalId: eval-1Px-...
 *     results: { ... }          <- every response and grade
 *     config:  { providers, prompts, tests, defaultTest, ... }   <- the replayable part
 *     metadata / vars / runtimeOptions
 *
 * Passing that file straight back to `-c` fails validation with the confusing message
 * "You must specify at least 1 provider" — because at the TOP level there is no `providers`
 * key; it is nested one level down under `config`.
 *
 * So a replay needs the `config` sub-document lifted to the top level. That is all this does.
 * The extracted file keeps each test's generated attack prompt AND its grader assertion, so a
 * replay grades identically to the original run.
 *
 * Usage:
 *   node extract-cases.mjs <export.yaml|export.json> [out.yaml]
 *
 * Idempotent for any file that already carries providers AND tests (an eval export, or a
 * hand-written suite like exploit-suite.yaml), so callers can pass either shape without
 * checking first. It deliberately REJECTS a generate-time red-team config such as
 * promptfooconfig.yaml: that file has no `tests` at all — the cases do not exist until
 * `redteam run` generates them — so there is nothing to replay and failing loudly beats
 * emitting an empty case set that would silently "pass" a CI gate.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import yaml from 'js-yaml';

const [src, dstArg] = process.argv.slice(2);
if (!src) {
  console.error('usage: node extract-cases.mjs <export.yaml|export.json> [out.yaml]');
  process.exit(2);
}
const dst = dstArg ?? src.replace(/(-cases)?\.(ya?ml|json)$/, '-replay.yaml');

let doc;
const raw = readFileSync(src, 'utf8');
try {
  doc = src.endsWith('.json') ? JSON.parse(raw) : yaml.load(raw);
} catch (err) {
  console.error(`cannot parse ${src}: ${err.message}`);
  process.exit(1);
}

// An export nests the config; a plain config has providers/targets at the top already.
const cfg = doc?.config ?? doc;
const providers = cfg?.providers ?? cfg?.targets;

if (!providers || !cfg?.tests?.length) {
  console.error(
    `${basename(src)} has neither a replayable "config" section nor top-level providers+tests.\n` +
    'Expected a promptfoo eval export (from `redteam run -o` / `export eval`) or a plain config.');
  process.exit(1);
}

// `outputPath` would make every replay silently overwrite the original run's results file.
delete cfg.outputPath;

writeFileSync(dst, yaml.dump(cfg, { lineWidth: -1, noRefs: true }), 'utf8');
console.log(`${dst}  (${cfg.tests.length} replayable cases)`);
