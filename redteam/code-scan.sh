#!/usr/bin/env bash
# STATIC code scan (`promptfoo code-scans run`) — a Promptfoo capability the POC never touched,
# and the natural second scorecard for this repo.
#
# The dynamic red-team asks "can I exploit the running app?". This asks "can the tool see the
# flaw in the source?". SupportBot is the ideal subject because the ground truth is already
# written down: 9 planted weaknesses, each mapped to a file and function in the README's
# "Planted weakness -> code map". So run this and fill a SECOND scorecard — how many of the 9
# does static analysis find, and does it find ones the dynamic scan missed?
#
# The interesting hypothesis to test: the two weaknesses the dynamic scan could NOT show
# (#1 leak-prone system prompt, #8 no output moderation) are plainly visible in the source.
# The dynamic scan missed them because gpt-4o-mini refused to cooperate — a static pass has no
# such dependency on the target model's alignment. If it flags them, the honest conclusion is
# that the two approaches are complementary, and the POC's "2 misses" is a property of
# dynamic testing rather than of Promptfoo.
#
# ⚠️ DATA RESIDENCY — read before running. This uploads source code to Promptfoo Cloud
#    (api.promptfoo.app) for analysis. It is a bigger disclosure than red-team generation
#    (which sends the purpose and generated prompts). Harmless for this throwaway repo of
#    fictional data; for a real service it is a security-review question in its own right,
#    and belongs in the §10 "Data residency" rubric row alongside the generation finding.
#
# Usage:
#   ./code-scan.sh                          # scan the whole repo, text output
#   ./code-scan.sh --format sarif           # SARIF for GitHub code scanning
#   ./code-scan.sh --min-severity high      # only high/critical
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
setup

cat <<EOF
This uploads the source under $ROOT to Promptfoo Cloud for analysis.
Target of the scan: supportbot/ (the deliberately-vulnerable app; fictional data only).
EOF
printf 'continue? [y/N] '
read -r reply
case "$reply" in [yY]*) ;; *) echo "aborted."; exit 0 ;; esac

pf code-scans run "$ROOT" \
  --guidance 'This is a deliberately-vulnerable sample LLM application used for authorized security testing. Report every LLM-specific weakness you find: prompt-injection surfaces, secrets embedded in system prompts, missing authorization on tool functions, SQL built by string interpolation, PII handling and cross-session state sharing, unscoped tool exposure, unmoderated model output, and unescaped markdown/link rendering that permits data exfiltration.' \
  "$@" 2>&1 | tee "$OUT/code-scan.txt"

echo
echo "saved: $OUT/code-scan.txt"
echo "Now compare the findings against the 9-row 'Planted weakness -> code map' in README.md"
echo "and record a static-analysis scorecard next to the dynamic one in docs/poc-results.md."
