#!/usr/bin/env bash
# TARGET DISCOVERY — runs Promptfoo's Target Discovery Agent against SupportBot.
#
# Why this is the most decision-relevant pass in the repo: the POC's headline finding is that
# detection collapsed to 0/40 with a thin `purpose` and only reached 12/40 after a human hand-
# wrote the app's real affordances into it. That finding is only actionable if you know
# whether the human work was avoidable. `redteam discover` interrogates the target and derives
# the purpose, tools and limitations automatically — so compare its output against the
# hand-written `purpose` in promptfooconfig.yaml:
#
#   * If discovery finds the account-id format, the tool names and the confidential document,
#     then "detection depends on purpose enrichment" is a documentation gap, not a real cost —
#     the tool can bootstrap itself and the rubric's "Time-to-first-value" row improves.
#   * If it misses them, the enrichment work is unavoidable per-target integration effort and
#     belongs in the adoption cost estimate.
#
# Either answer is a genuine finding. Record which one you got in docs/poc-results.md.
#
# Note: discovery drives the target with its own probe conversation, so SupportBot must be up.
# It uses the remote service (Promptfoo Cloud login required), like generation.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
setup
require_app
reset_app

cd "$HERE"
LOG="$OUT/discovered-purpose.txt"
echo "running the Target Discovery Agent against $APP_URL (this drives the live app)..."
pf redteam discover -c promptfooconfig.yaml 2>&1 | tee "$LOG"
echo
echo "saved: $LOG"
echo "Now diff it against the hand-written 'purpose:' block in promptfooconfig.yaml —"
echo "specifically whether it found: the acc_1001..acc_1004 id format, the three tool names,"
echo "and that the knowledge base holds an internal-only pricing/staff document."
