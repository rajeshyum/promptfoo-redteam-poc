#!/usr/bin/env bash
# Run the DEFAULT red-team scan (promptfooconfig.yaml) — the ~15 min demo pass.
# Thin wrapper over scan.sh, which is the generic runner for every config in this directory.
#
#   ./run.sh                     # this scan
#   ./scan.sh depth.yaml         # any other pass
#   ./scenarios.sh               # what every config/script covers, and its runtime
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/scan.sh" promptfooconfig.yaml "$@"
