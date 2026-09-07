#!/usr/bin/env bash
# Generate the §4.1 detection scorecard from every saved run (see scorecard.mjs).
#   ./scorecard.sh                # full report
#   ./scorecard.sh --markdown     # paste-ready table for docs/poc-results.md
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
require_node
exec node "$HERE/scorecard.mjs" "$@"
