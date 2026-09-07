#!/usr/bin/env bash
# Open the general Promptfoo local results viewer — the side-by-side eval grid (every run,
# red-team and quality alike). Reads the LOCAL results DB; nothing is uploaded.
#
#   ./view.sh                   # newest eval, browser opens on http://localhost:15500
#   ./view.sh --port 8080
#   ./view.sh -y                # skip the "open browser?" prompt (for scripted demos)
#
# Use ./report.sh instead for the red-team-specific vulnerability dashboard (severity
# breakdown, per-plugin pass rates); this viewer is better for reading individual replies.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
setup

echo "Starting the local results viewer. Ctrl-C to stop."
exec "$PF" view "$@"
