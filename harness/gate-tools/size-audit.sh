#!/bin/bash
# File size audit — list the source files (src − tests of the config) over the limit
#
# Purpose: do not rely on manual copying for the handover note of files over the size limit.
#
# The verdict has 2 tiers. A single uniform limit does not work in operation, so reporting and rejection are separate.
#   up to SIZE_WARN            🟢 pass
#   SIZE_WARN+1 to SIZE_LIMIT  🟡 pass. Report them in the list every time
#   SIZE_LIMIT+1 or more       🔴 reject
#
# The exit code depends on how the tool is launched. The environment variable SPRINT_GATE (sprint_via_gate) switches it.
#   SPRINT_GATE=1 (through the gate): 🟢 0 / 🟡 0 / 🔴 2 (2 = impl failure. the failure class of gate-check.sh)
#   no SPRINT_GATE (by hand): 🟢 0 / 🟡 1 / 🔴 1
# A manual run makes 🟡 return 1 because, on an intentional check, a remaining excess
# must come back as a failure.
#
# Environment variables:
#   SIZE_WARN        warning threshold (default 800)
#   SIZE_LIMIT       rejection threshold (default 1200)
#   SIZE_AUDIT_ROOT  scan root. When unset, the git top level (for tests)
#   SPRINT_GATE      marks a launch through the gate. gate-check.sh exports it
#
# Run it by hand with `bash harness/bin/sprint size-audit`. Connected to the TEST gate (gates of sprint.config.json).
set -euo pipefail

WARN=${SIZE_WARN:-800}
LIMIT=${SIZE_LIMIT:-1200}

. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
ROOT="${SIZE_AUDIT_ROOT:-$(sprint_root)}"

# Scan targets = files that match src and do not match tests (globs of the config)
mapfile -t SRC_GLOBS < <(sprint_component_globs src)
mapfile -t TEST_GLOBS < <(sprint_component_globs tests)
TARGETS=$(comm -23 \
  <(sprint_glob_files -r "$ROOT" "${SRC_GLOBS[@]}") \
  <(sprint_glob_files -r "$ROOT" "${TEST_GLOBS[@]}"))

if [ -z "$TARGETS" ]; then
  echo "ok: no file over ${WARN} lines"
  exit 0
fi

# List the files over the warning threshold in descending order of line count
WARN_HITS=$(printf '%s\n' "$TARGETS" | sed "s|^|$ROOT/|" \
  | xargs -r -d '\n' wc -l 2>/dev/null \
  | grep -v ' total$' \
  | awk -v limit="$WARN" '$1 > limit { print $1 "\t" $2 }' \
  | sort -rn || true)

if [ -z "$WARN_HITS" ]; then
  echo "ok: no file over ${WARN} lines"
  exit 0
fi

WARN_COUNT=$(echo "$WARN_HITS" | wc -l | tr -d ' ')
OVER_HITS=$(echo "$WARN_HITS" | awk -F'\t' -v limit="$LIMIT" '$1 > limit' || true)

if [ -n "$OVER_HITS" ]; then
  OVER_COUNT=$(echo "$OVER_HITS" | wc -l | tr -d ' ')
  echo "size over ${LIMIT} lines: ${OVER_COUNT} file(s) — split each into ${WARN} lines or fewer"
  echo "$OVER_HITS" | sed "s|$ROOT/||"
  echo "(reference) over ${WARN} lines: ${WARN_COUNT} file(s)"
  echo "$WARN_HITS" | sed "s|$ROOT/||"
  # 2 through the gate (impl failure), 1 by hand
  if sprint_via_gate; then exit 2; fi
  exit 1
fi

echo "warn: over ${WARN} lines: ${WARN_COUNT} file(s) (pass up to ${LIMIT} lines)"
echo "$WARN_HITS" | sed "s|$ROOT/||"
# Pass through the gate. By hand, return it as a failure
if sprint_via_gate; then exit 0; fi
exit 1
