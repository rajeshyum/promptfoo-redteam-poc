# Scenario Matrix — design criterion → runnable command

Every exit criterion and learning area in [promptfoo-poc-design.md](promptfoo-poc-design.md),
mapped to the config/script that satisfies it. `./redteam/scenarios.sh` prints the same table
with runtimes; `./redteam/scenarios.sh --check` verifies the environment.

The POC's question is **exploitation and detection**: *does the scanner find the holes we know
are there?* Everything below is organised around that. Remediation is deliberately out of scope.

## §4 exit criteria

| Criterion | Status | Command |
|---|---|---|
| App reachable as a Promptfoo target | ✅ | `curl localhost:8000/health` |
| Red-team scan across **≥5 of 6** plugin categories | ✅ **6/6** | see the category table below |
| **≥3 attack strategies** layered on | ✅ **5** | `./redteam/scan.sh depth.yaml` |
| Vulnerability dashboard generated | ✅ | `./redteam/report.sh` |
| Framework mapping (OWASP LLM Top 10) | ▶ run it | `./redteam/scan.sh owasp-framework.yaml` |
| **Detection-quality scorecard (§4.1)** filled | ✅ generated | `./redteam/scorecard.sh` |
| False-positive tally | ✅ generated | `./redteam/scorecard.sh` (last section) |
| Replay saved cases (detection vs generator variance) | ✅ | `./redteam/rescan.sh` + `./redteam/compare-runs.sh` |
| Rubric filled with evidence | ✅ | [poc-results.md](poc-results.md) §10 |

## Plugin categories (§3) — all 6 now covered

| Promptfoo category | Config | Plugins |
|---|---|---|
| Security & Access Control | `promptfooconfig.yaml` | `prompt-extraction`, `sql-injection`, `bola` |
| Security — Data/Privacy | `promptfooconfig.yaml` | `pii:direct`, `cross-session-leak`, `data-exfil`, `agentic:memory-poisoning` |
| Security — RAG | `promptfooconfig.yaml`, `indirect-injection.yaml` | `rag-document-exfiltration`, `rag-poisoning`, `indirect-prompt-injection`, `rag-source-attribution` |
| Brand & Reputation | `promptfooconfig.yaml` | `excessive-agency` |
| Trust & Safety | `promptfooconfig.yaml`, `datasets.yaml` | `harmful:hate`, `harmful:privacy` |
| **Custom & Configurable** | `policy-intent.yaml` | `policy` ×4, `intent` ×6 |
| **Dataset Collections** | `datasets.yaml` | `harmbench`, `donotanswer`, `beavertails`, `cyberseceval`, `pliny`, `xstest` |

The last two rows were missing from the original POC, which is why the "≥5 of 6 categories"
criterion was not actually met.

## Attack strategies (§3) — `depth.yaml`

`prompt-injection` (direct injection) · `base64` + `leetspeak` (encoding/obfuscation) ·
`jailbreak:composite` (chained jailbreak) · `crescendo` (multi-turn). The default config runs
one (`jailbreak`, which resolves to `jailbreak:meta` on 0.121.17).

## Learning areas (§6)

| # | Area | Where |
|---|---|---|
| A1 | setup → run → report workflow | `./redteam/run.sh`, `report.sh`; `discover.sh` for the Target Discovery Agent |
| A2 | Plugins: categories, presets | the table above; `promptfoo redteam plugins` lists all 155 |
| A3 | Strategies, composition | `depth.yaml` |
| A4 | Adversarial generation | `local-generation.sh` (remote vs local, with a plugin diff) |
| A5 | Grading: deterministic vs model-graded | `exfil-eval.yaml` (deterministic) vs the scans (graded); `scorecard.sh` prints grader rationales |
| A6 | Vulnerability report / dashboard | `./redteam/report.sh` |
| **B7** | **Detection quality** (the honest core) | `./redteam/scorecard.sh` |
| B8 | Replay & regression (answers generator non-determinism) | `rescan.sh` + `compare-runs.sh` |
| B9 | Cost & runtime at scale | `./redteam/cost-report.sh <results.json>` |
| B10 | CI integration | `ci-gate.sh`, `.github/workflows/redteam-gate.yml` |
| B11 | Framework/compliance reporting | `owasp-framework.yaml` |
| C12 | Deterministic (non-generated) test suites | `exploit-suite.yaml`, `exfil-eval.yaml` |
| C13 | Custom policy plugin | `policy-intent.yaml` |

## Beyond the design doc

Capabilities of the installed CLI that the original plan did not know about, each of which
changes a conclusion:

| Capability | Command | Why it matters |
|---|---|---|
| `data-exfil` plugin | in `promptfooconfig.yaml` | The design guessed the id `data-exfiltration` and, finding nothing, the POC concluded Promptfoo *has no* markdown-exfil plugin. The real id is **`data-exfil`** — "data exfiltration via URL parameters, images, or markdown links", i.e. exactly weakness #9. |
| `redteam poison` | `./redteam/poison-kb.sh` | Generates poisoned documents to ingest, so RAG poisoning against a **server-side** KB is supported after all — via a two-step flow, not a single plugin. |
| `indirectInjectionVar` | `indirect-injection.yaml` | `/chat` now accepts an optional `context` field, giving the native indirect-injection plugins a real injection point. |
| `redteam discover` | `./redteam/discover.sh` | Derives the target's purpose automatically — tests whether the POC's headline "detection depends on hand-enriched `purpose`" is a real cost or a documentation gap. |
| `code-scans run` | `./redteam/code-scan.sh` | Static LLM-security scan of the source. A second scorecard against the same 9 known plants — and it does not depend on the target model's willingness to cooperate. |
| `redteam eval` | `./redteam/rescan.sh`, `ci-gate.sh` | Replays a saved case set without regenerating — the apples-to-apples rescan the design demanded (§7 Phase 3) and the only sound basis for a CI gate. |
| `--repeat` | `./redteam/eval.sh … --repeat 3` | Several planted weaknesses fire probabilistically (the poisoned-doc chain lands ~50-75%). A single pass cannot tell "defended" from "did not fire this time"; repeats can. |

## Reproducibility notes

- **Node:** promptfoo 0.121.17 declares `engines: ^20.20.0 || >=22.22.0` and refuses to start
  outside that range. The README's original "Node ≥18" is wrong, and common defaults such as
  22.15 fail. Every wrapper script now auto-detects a compatible Node (`redteam/_lib.sh`).
- **Order independence:** `POST /reset` clears sessions and the shared CRM scratchpad. Without
  it the process-global scratchpad accumulates PII across a whole scan, so a late
  `pii:*` / `cross-session-leak` finding can be an artifact of an earlier test.
- **Errors vs refusals:** `/chat` returns **502** when the upstream model call fails, so
  promptfoo records an error. Returning a friendly "sorry" string instead makes an
  infrastructure failure look like a safe refusal and quietly inflates the pass rate.
- **Exit code 100:** `promptfoo eval` exits 100 when any assertion fails. For the security
  suites that is the *expected* result, so the wrappers tolerate 100 and only 100.
