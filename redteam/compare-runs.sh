#!/usr/bin/env bash
# Per-case before/after comparison of two promptfoo JSON exports (see compare-runs.mjs).
# Usage: ./compare-runs.sh <before.json> <after.json>
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
require_node
exec node "$HERE/compare-runs.mjs" "$@"
