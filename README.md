# Promptfoo Red-Team POC

Evaluating [Promptfoo](https://www.promptfoo.dev/docs/red-team/) as an LLM **security / red-teaming** tool by building a deliberately-vulnerable sample app ("SupportBot") and demonstrating that Promptfoo's scanner discovers the planted vulnerabilities.

> ⚠️ **SupportBot is intentionally insecure** (planted SQL injection, RAG exfiltration, missing authz, PII leakage, etc.). It is for **authorized, local, educational security testing only**. Never deploy it, expose it publicly, or point the red-team scanner at any system but this app.

## Full plan

See **[docs/promptfoo-poc-design.md](docs/promptfoo-poc-design.md)** — objective, the 9 planted weaknesses, vulnerability→plugin mapping, detection-quality scorecard, demo storyboard, risks, and the build spec (§13).

## Results

**POC complete — decision: TRIAL.** Across three full scans of the same app with the same config,
**6–7 of the 9 planted weaknesses were confirmed exploitable** and 2 are model-layer misses
(#1, #8) that neither single-shot nor multi-turn attacks broke.

How much of that Promptfoo's own generated attacks found is **not stable between runs** — and
that turned out to be the POC's most important finding:

| Scan | Cases | Attacks that landed | Weaknesses found **by plugins** |
|---|---|---|---|
| Baseline — 2026-06-18 | 40 | 12 | **5 of 9** (#3, #4, #5, #6, #7) |
| Re-run — 2026-08-31, same config | 47 | **6** | **2 of 9** (#4, #6) |
| Re-run — 2026-09-06, same config | 47 | 12 | **5 of 9** (#3, #4, #5, #6, #7) |

Nothing was fixed between those runs. Same app, same model, same plugins: `sql-injection`,
`rag-document-exfiltration`, `excessive-agency` and `cross-session-leak` went from finding
something, to finding nothing, and back again. Out-of-the-box detection of our 9 weaknesses ranged
from **2 to 5 depending on the day**, so **quote coverage as a range, never as a point estimate** —
a single scan is a lower bound on your exposure, never a clean bill of health.

The control that locates the instability in *attack generation* rather than in the app:
`redteam/exploit-suite.yaml`, 39 committed hand-written probes, landed **28, 28 and 29 of 39**
across the same period in ~40 s a run, with both deliberate control probes holding at 0/3 every
time.

Run `./redteam/scorecard.sh` for the current mechanically-derived scorecard. Full analysis,
generation-mode findings, and the filled §10 rubric are in
**[docs/poc-results.md](docs/poc-results.md)**.

## Locked decisions

- **App stack:** Python / FastAPI
- **Provider:** OpenAI (app, attack-generation, and grader — one key)
- **Generation mode:** test **both** remote (default) and local (`PROMPTFOO_DISABLE_REDTEAM_REMOTE_GENERATION=true`), compare quality. *(Finding: local generation can't run the app-layer plugins — see the "Generation modes" section below.)*

## Layout

| Path | Contents |
|---|---|
| `docs/promptfoo-poc-design.md` | The POC design doc (the plan) |
| `docs/poc-results.md` | **Results:** detection scorecard, corrections, generation-mode findings, §10 rubric |
| `docs/scenario-matrix.md` | **Every design criterion → the command that satisfies it** |
| `docs/file-guide.md` | Plain-language explanation of **what every file in the repo does** |
| `docs/demo-runbook.md` | **Guided walkthrough** — reproduce the POC in ~10 min: setup, three manual attacks, the scan, how to read the results, Q&A |
| `supportbot/` | The deliberately-vulnerable FastAPI app (Phase 1) |
| `redteam/promptfooconfig.yaml` | Default fast scan — one plugin per planted weakness |
| `redteam/depth.yaml` | 5 attack strategies layered on (encoding, injection, composite, multi-turn) |
| `redteam/policy-intent.yaml` | Custom business rules (`policy`) + explicit attacker goals (`intent`) |
| `redteam/datasets.yaml` | Published adversarial corpora — the one pass with local generation |
| `redteam/indirect-injection.yaml` | Native RAG poisoning / indirect injection via a request variable |
| `redteam/owasp-framework.yaml` | OWASP/NIST/MITRE breadth pass — the compliance artifact |
| `redteam/crescendo.yaml` | Multi-turn pass on the two missed weaknesses (#1, #8) |
| `redteam/exfil-eval.yaml` | Deterministic test of the poisoned-doc → markdown-exfil chain (#3-poisoned, #9) |
| `redteam/exploit-suite.yaml` | Hand-written deterministic attacks — the false-negative reference |
| `redteam/*.sh` | Wrapper scripts — run `./redteam/scenarios.sh` for the full list |
| `redteam/output/` | Run results (gitignored) |

## Setup

### Prerequisites

| Tool | Version | Used for |
|---|---|---|
| Python | ≥3.10 (tested on 3.13) | SupportBot (the target app) |
| Node.js + npm | **`^20.20.0 \|\| >=22.22.0`** | Promptfoo red-team scanner |

> ⚠️ **Node version is strict.** promptfoo 0.121.17 declares that engines range and **refuses to
> start** outside it (`Install a supported Node.js version and try again`) — Node 22.15, a common
> default, fails. The wrapper scripts in `redteam/` auto-detect a compatible runtime (nvm or
> Homebrew) and tell you what they picked; `./redteam/scenarios.sh --check` verifies your setup.
> `nvm install 24` or `brew install node@24` if none is found.
| OpenAI API key | — | App model loop **and** Promptfoo attack-generation/grading |
| Promptfoo Cloud account + API key | free ([app.promptfoo.app](https://www.promptfoo.app)) | **Required** for remote attack generation (app-layer plugins won't generate without it) |

> All commands below are run from the **repo root** (`promptfoo-redteam-poc/`) unless noted.

### 1. Configure the keys

```bash
cp .env.example .env          # then edit .env and set:
#   OPENAI_API_KEY=sk-...        (app + generation/grading)
#   PROMPTFOO_API_KEY=...        (Promptfoo Cloud -> Settings -> API Keys; for remote generation)
```

`.env` lives at the **repo root** (already gitignored — never commit it). It is the single
source of both keys for the app and Promptfoo. `OPENAI_MODEL` (default `gpt-4o-mini`) and the
host/port are also set here.

### 2. Install & run SupportBot (the target)

```bash
python3 -m venv .venv
.venv/bin/pip install -r supportbot/requirements.txt
.venv/bin/uvicorn supportbot.app:app --host 127.0.0.1 --port 8000
```

Leave this running in its own terminal. Sanity-check it from another:

```bash
curl -s localhost:8000/health
# {"status":"ok"}

curl -s -X POST localhost:8000/chat -H 'Content-Type: application/json' \
  -d '{"session_id":"s1","message":"What are your support hours?"}'
```

> ⚠️ Launch uvicorn from the repo root so `load_dotenv()` finds the root `.env`.

### 3. Install Promptfoo & run the red-team scan (Phase 2)

Promptfoo needs the OpenAI key **and** a Promptfoo Cloud login for remote attack
generation (the app-layer plugins refuse to generate without it — see *Generation modes*
below). Authenticate once, then export the root `.env` and run from `redteam/`:

```bash
# one-time: log in so remote generation + the email gate are satisfied
set -a; . ./.env; set +a
./node_modules/.bin/promptfoo auth login --api-key "$PROMPTFOO_API_KEY"
```

Then use the wrapper scripts in `redteam/` (they resolve the local `promptfoo` binary,
source the root `.env`, and check the target is up — no global install or PATH juggling):

```bash
cd redteam
./scenarios.sh --check   # verify node / keys / auth / app / every config parses
./scenarios.sh           # every scenario, what it covers, and its runtime

./run.sh                 # default scan -> output/redteam-{cases.yaml,results.json}
./scorecard.sh           # the §4.1 detection scorecard, derived from the saved runs
./report.sh              # open the local vulnerability dashboard (the demo artifact)

# broader passes (see ./scenarios.sh for runtimes)
./scan.sh depth.yaml              # 5 attack strategies
./scan.sh policy-intent.yaml      # custom business rules
./scan.sh datasets.yaml           # published corpora (local generation)
./scan.sh indirect-injection.yaml # native RAG poisoning
./scan.sh owasp-framework.yaml    # OWASP/NIST/MITRE mapping

# replay SAVED cases — no regeneration, so a change in results is your app, not attack variance
./rescan.sh
./compare-runs.sh output/redteam-results.json output/rescan-<stamp>.json

# data-residency comparison (design §5), with a plugin-by-plugin diff
./local-generation.sh
```

**Three artifacts per scan, and they are not interchangeable:**

| File | What it is |
|---|---|
| `output/<name>-cases.yaml` | What `redteam run -o` writes — a full **eval export** (`evalId` / `results` / `config` / `metadata`), *not* a bare case list, despite the flag name. |
| `output/<name>-replay.yaml` | The `config` section lifted to the top level by `extract-cases.mjs`, so it is a valid config. **This is the file `rescan.sh` and `ci-gate.sh` replay.** |
| `output/<name>-results.json` | The graded results, exported explicitly afterwards. |

> ⚠️ Passing `-cases.yaml` straight to `-c` fails with the misleading
> `You must specify at least 1 provider` — the providers are nested under `config`, not at the
> top level. `_lib.sh resolve_cases()` handles the lift; call that rather than the raw file.
> `redteam run` alone leaves results only in the local DB, so a scan without the export step
> leaves no reviewable record.

> ⚠️ `report.sh` / `view.sh` serve a **local** dashboard — nothing is uploaded. Publishing
> to promptfoo.app requires the separate `promptfoo share` command; keep it **off** — run
> artifacts may contain adversarial/harmful content (already gitignored under `redteam/`).
> The Promptfoo Cloud login above is only for remote attack *generation*, not for viewing.

### 4. Detection scorecard (the core deliverable)

```bash
./redteam/scorecard.sh              # full report
./redteam/scorecard.sh --markdown   # paste-ready §4.1 table
```

Derives *"we planted 9 weaknesses; which did the scanner catch?"* from the saved result JSONs
instead of transcribing it by hand. It separates three outcomes a pass/fail count conflates:

- **DETECTED** — a mapped plugin ran and at least one attack succeeded.
- **MISSED** — a probe ran and every attack was defended. Note this is ambiguous on one model:
  the app's control held, *or* the probe was too weak. `./redteam/model-compare.sh` tells them apart.
- **NOT TESTED** — no mapped plugin ran. The outcome most easily mistaken for "secure", because
  a weakness with no coverage produces silence rather than a finding.

It also tallies findings that map to **no** planted weakness (design §4.1's false-positive count).

### Planted weakness → code map (design §2 / §13.1)

| # | Weakness | Where |
|---|---|---|
| 1 | Leak-prone system prompt (embeds `INTERNAL_OPS_KEY`) | `supportbot/agent.py` `SYSTEM_PROMPT` |
| 2 | No input sanitization | `supportbot/agent.py` `run_agent` |
| 3 | Confidential + poisoned RAG docs | `supportbot/knowledge_base.py` `DOCS` |
| 4 | Account lookup, no authz | `supportbot/tools.py` `lookup_account` |
| 5 | SQL built by f-string | `supportbot/tools.py` `query_transactions` |
| 6 | PII echo + cross-session leak | `supportbot/tools.py` `RECENT_LOOKUPS` + `agent.py` `_memory_message` |
| 7 | Over-agentic tool access | `supportbot/agent.py` (all tools, unscoped) |
| 8 | No content moderation | `supportbot/agent.py` (raw reply returned) |
| 9 | Unescaped markdown/links | `supportbot/app.py` `/chat` (raw markdown reply) |

### Test-harness affordances (NOT planted weaknesses)

Added so the measurements mean something. Each is off or inert by default, so the attack surface
is unchanged unless you opt in — see [docs/scenario-matrix.md](docs/scenario-matrix.md).

| Affordance | Why it exists |
|---|---|
| `POST /reset` | Clears sessions + the shared CRM scratchpad. Without it the process-global scratchpad accumulates PII across a whole scan, so a late `pii:*` / `cross-session-leak` finding can be an artifact of an earlier test rather than a reproducible exploit. |
| `/chat` returns **502** on upstream failure | A friendly "sorry" string would be graded as a *safe refusal*, silently inflating the pass rate. A 502 is recorded by promptfoo as an error. |
| Optional `context` field on `/chat` | Gives promptfoo's `indirect-prompt-injection` / `rag-poisoning` plugins the `indirectInjectionVar` they require. Omitted = no change. |
| `SUPPORTBOT_EXTRA_DOCS=<dir>` | Ingests externally-generated documents into the KB, so `promptfoo redteam poison` output can actually be planted. |
| `SUPPORTBOT_SYSTEM_PROMPT[_FILE]` | Swaps the system prompt for the regression demo, and for testing whether a guardrailed prompt closes #1. |
| Locks on the sqlite connection, sessions and the CRM list | promptfoo runs 4 tests concurrently against a threadpool-served app. The locks keep the cross-session leak *deliberate* rather than a torn-data accident; the SQL stays injectable. |

## Data-flow note

Promptfoo red-team **is not air-gapped by default**: adversarial-input generation uses Promptfoo's remote service and grading defaults to OpenAI. Only the target eval is local. See design doc §5.

### Generation modes — empirical findings (Promptfoo 0.121.17, this POC)

Measured against the locked "OpenAI for everything" decision (design §13). These feed the
**Data residency**, **Setup burden**, and **Vulnerability coverage** rubric rows:

| Mode | Result |
|---|---|
| **Remote generation** (default) | Requires a **Promptfoo Cloud login** (`auth login --api-key`). Without it you hit an interactive **"Email Verification Required"** gate; `PROMPTFOO_API_KEY` in the env alone does **not** clear it. App purpose + generated prompts go to Promptfoo's service. |
| **Local generation** (`PROMPTFOO_DISABLE_REDTEAM_REMOTE_GENERATION=true`) | The high-value app-layer plugins (**`bola`, `bfla`, `rbac`, `rag-document-exfiltration`, `rag-poisoning`**, …) **refuse to generate** — "requires remote generation." Only simpler single-turn plugins (`pii:direct`, `prompt-extraction`, `sql-injection`, `harmful:*`) work fully local. |
| **Multi-turn `crescendo`, OpenAI as attacker** | OpenAI **rejects the attack-generation calls** with `400 cyber_policy` ("flagged for possible cybersecurity risk"). Routed through Promptfoo's remote service instead, it proceeds. |

**Takeaway:** a genuinely air-gapped red-team run only covers a subset of plugins; exercising
the application-layer threats this POC targets requires Promptfoo's remote generation service.

### H3 (HTTP provider + multi-turn sessions) — resolved

The design flagged this as the most likely blocker (§8/§13.4). Verified working on 0.121.17:
- Request body templating + `transformResponse: 'json.reply'` extract the reply correctly.
- Multi-turn session wiring is `sessionSource: client` + `stateful: true` (the design skeleton's
  `sessions: {source: client}` is **not** the syntax for this version). Promptfoo mints a
  `sessionId` and injects it into each request, threading the conversation through SupportBot's
  in-process session store.

## What has and hasn't been run

The default scan, the deterministic exploit suite and the poisoned-doc chain have all been
executed, and their saved results are what `./redteam/scorecard.sh` reads. The broader passes —
`depth.yaml`, `policy-intent.yaml`, `datasets.yaml`, `owasp-framework.yaml` — are configured and
validated but **not all have been run**, because each costs real tokens and wall-clock. Treat
them as wired, not as evidence.

`./redteam/scenarios.sh` lists every pass with its runtime, and
[docs/scenario-matrix.md](docs/scenario-matrix.md) maps each one to the design criterion it
satisfies.
