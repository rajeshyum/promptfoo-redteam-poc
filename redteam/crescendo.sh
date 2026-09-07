#!/usr/bin/env bash
# Multi-turn (crescendo) pass on the two weaknesses the single-shot scan missed (#1, #8).
# Thin wrapper over scan.sh so this pass has a runnable entry point like every other config.
#
# ⚠️ crescendo needs stateful:true, which forces the whole run to execute SERIALLY, and each
#    test is a conversation of up to ~10 rounds against a ~47 s/turn agent. crescendo.yaml
#    keeps numTests at 1 per plugin for exactly this reason. Measured: ~1 min for 2 cases.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/scan.sh" crescendo.yaml "$@"
