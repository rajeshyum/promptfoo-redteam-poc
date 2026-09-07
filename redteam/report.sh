#!/usr/bin/env bash
# Open the local Promptfoo red-team vulnerability dashboard — the stakeholder demo artifact.
# Reads the LOCAL results DB (~/.promptfoo/promptfoo.db); nothing is uploaded.
#
#   ./report.sh                 # newest red-team eval, browser opens on http://localhost:15500
#   ./report.sh --port 8080     # different port (15500 is promptfoo's default)
#   ./report.sh <evalId>        # a specific run — see ./report.sh --list
#   ./report.sh --list          # list eval ids without starting the server
#
# Ctrl-C to stop the server. For the text-only scorecard (no browser), use ./scorecard.sh.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
setup

if [ "${1:-}" = "--list" ]; then
  # `list evals -n 20` selects the 20 most recent but prints them oldest-first, so the run
  # you most likely want is the LAST row, not the first.
  echo "The 20 most recent local evals, oldest first (newest at the BOTTOM)."
  echo "Pass an id to ./report.sh to open that run:"
  exec "$PF" list evals -n 20
fi

echo "Starting the local red-team report server. Ctrl-C to stop."
exec "$PF" redteam report "$@"
