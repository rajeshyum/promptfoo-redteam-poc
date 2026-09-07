#!/usr/bin/env bash
# Token / cost / wall-clock accounting for a run (see cost-report.mjs).
# Usage: ./cost-report.sh output/redteam-results.json [more.json ...]
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
require_node
exec node "$HERE/cost-report.mjs" "$@"
