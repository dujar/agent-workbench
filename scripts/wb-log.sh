#!/usr/bin/env bash
# Append one line to the workbench run log. The caller runs this after every
# agent returns, so there is an external record of who ran and what they said —
# independent of the counters agents keep about themselves.
#
# Usage: scripts/wb-log.sh <agent> <verdict> [note...]
#   scripts/wb-log.sh audit-agent "spec: 6 gaps" "round 1"
#   scripts/wb-log.sh implement-agent "MERGED" "step-3-auth"

set -uo pipefail
WB="${WB:-.agent-workbench}"
[ $# -ge 2 ] || { echo "usage: $0 <agent> <verdict> [note...]" >&2; exit 2; }

agent=$1; verdict=$2; shift 2; note="${*:-}"
mkdir -p "$WB"
LOG="$WB/run-log.md"

if [ ! -f "$LOG" ]; then
  { echo "# Run log"
    echo
    echo "Appended by the caller after each agent returns. Never rewritten —"
    echo "a verdict that keeps repeating is the thing you want to see."
    echo
    echo "| when | agent | verdict | note |"
    echo "|------|-------|---------|------|"
  } > "$LOG"
fi

printf '| %s | %s | %s | %s |\n' \
  "$(date -u +%Y-%m-%dT%H:%MZ)" "$agent" "${verdict//|/\\|}" "${note//|/\\|}" >> "$LOG"
