#!/bin/bash
# harness/lib/env.sh — resolving the project root (the source of truth). hooks / tools / gate-tools / bin use only this file.
#
# Priority:
#   1. CLAUDE_PROJECT_DIR  Claude Code passes it to hooks. Fixture tests also point it at a temporary directory
#   2. the first directory with sprint.config.json, going up from cwd (the case of multiple projects in 1 git repository)
#   3. git rev-parse       the Bash of main has no CLAUDE_PROJECT_DIR
#   4. pwd
#
# How to read it (go relative from the caller's own location. Resolves to the real location even through a symbolic link):
#   harness/bin/*          . "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
#   harness/tools/*.sh     . "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
#   harness/gate-tools/*.sh . "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
#   harness/hooks/*.sh     . "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
# This file reads config.sh in the same directory. The caller reads only env.sh.

sprint_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  local d
  d=$(pwd)
  while [ "$d" != "/" ]; do
    if [ -f "$d/sprint.config.json" ]; then printf '%s\n' "$d"; return 0; fi
    d=$(dirname "$d")
  done
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ── time zone ──
# Write all record times (tools.jsonl, stage-transitions.jsonl, stage-tokens.jsonl, test-fails.json, and
# updated_at of flags.json) in this zone. The default is project.timezone of the config. The environment variable SPRINT_TZ has priority.
# When no config exists, write in the system default zone.
_sprint_tz() {
  if [ -n "${SPRINT_TZ:-}" ]; then printf '%s\n' "$SPRINT_TZ"; return 0; fi
  if sprint_config_exists; then sprint_config '.project.timezone // empty'; fi
}
sprint_date() { # <format arguments of date...>
  local tz
  tz=$(_sprint_tz)
  if [ -n "$tz" ]; then TZ="$tz" date "$@"; else date "$@"; fi
}

# ── launch through the gate ──
# gate-check.sh exports SPRINT_GATE=1 before the loop. A tool tells the case with sprint_via_gate
# (for example, size-audit treats 🟡 as a failure when run by hand, and as a pass when run through the gate).
sprint_via_gate() {
  [ "${SPRINT_GATE:-}" = "1" ]
}
